// Sintetizador MIDI 1.0 em tempo real para ESP32-S3 com TinySoundFont (tsf.h)
// e saida de audio digital I2S para DAC externo PCM5102A (44.1 kHz, 16-bit,
// Estereo).
//
// Arquitetura:
//   - Recebe pacotes MIDI 1.0 de 24 bits (3 bytes) via UART1 em 115200 bps
//     (8N1) provenientes do FPGA Cyclone V (DE0-CV).
//   - Sincroniza os frames de 24 bits automaticamente pelo MSB:
//       * Status (MSB = 1, >= 0x80): inicia novo frame e guarda status.
//       * Dados  (MSB = 0, <  0x80): guarda nota (Byte 1) e vel (Byte 2).
//   - Enfileira os eventos MIDI em fila FreeRTOS thread-safe (sem bloqueio)
//     e protege o estado interno do TinySoundFont (tsf*) com mutex.
//   - Renderiza blocos curtos de 64 frames (~1.45 ms por bloco) em 44100 Hz
//     Estereo e transmite via DMA I2S ao DAC PCM5102A.
//
// Compatibilidade:
//   - ESP32-S3 (Arduino IDE / PlatformIO - Core ESP32 v2.x e v3.x).
//   - Requer `tsf.h` (TinySoundFont) e `piano_sf2.h` (gerado pelo script
//     `sf2_to_header.py`) na mesma pasta do sketch.

#include <Arduino.h>
#include <driver/i2s.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>

#define TSF_IMPLEMENTATION
#include "tsf.h"
#include "piano_sf2.h"

// Configuracao de Pinos e Parametros de Hardware (ESP32-S3)

// Pinos da UART1 conectada ao pino `saida_serial` do FPGA DE0-CV (3.3V LVTTL).
#ifndef UART_RX_PIN
#define UART_RX_PIN 18
#endif

#ifndef UART_TX_PIN
#define UART_TX_PIN 17
#endif

constexpr int kUartRxPin = UART_RX_PIN;
constexpr int kUartTxPin = UART_TX_PIN;
constexpr uint32_t kUartBaudRate = 115200;
constexpr int kUartRxBufSize = 1024;

// Pinos do barramento I2S conectados ao modulo DAC PCM5102A.
// (PCM5102A: SCK no GND, LCK -> LRCK, DIN -> DOUT, BCK -> BCLK).
#ifndef I2S_LRCK_PIN
#define I2S_LRCK_PIN 4
#endif

#ifndef I2S_DOUT_PIN
#define I2S_DOUT_PIN 5
#endif

#ifndef I2S_BCLK_PIN
#define I2S_BCLK_PIN 6
#endif

constexpr int kI2sLrckPin = I2S_LRCK_PIN;
constexpr int kI2sDoutPin = I2S_DOUT_PIN;
constexpr int kI2sBclkPin = I2S_BCLK_PIN;
constexpr i2s_port_t kI2sPortNum = I2S_NUM_0;

// Parametros de sintese e baixa latencia (< 3 ms).
constexpr int kSampleRateHz = 44100;
constexpr int kAudioBlockFrames = 64; // ~1.45 ms por bloco @ 44.1 kHz.
constexpr int kMaxPolyphonyVoices = 16;
constexpr float kGlobalGainDb = -6.0f; // -6 dB: nivel ideal para caixa de som ativa (1.05 V RMS) e previne clipping digital em polifonia.
constexpr UBaseType_t kMidiQueueLength = 128;

// Estruturas e Variaveis Globais

struct MidiEvent
{
  uint8_t status;
  uint8_t data1; // Nota MIDI (0..127) ou numero do Control Change.
  uint8_t data2; // Velocity (0..127) ou valor do Control Change.
};

static tsf *tsf_inst = nullptr;
static SemaphoreHandle_t tsf_mutex = nullptr;
static QueueHandle_t midi_queue = nullptr;

// Estado do parser MIDI 1.0 com sincronismo pelo MSB (bit 7).
static uint8_t status_byte = 0;
static uint8_t data_buf[2] = {0, 0};
static uint8_t data_idx = 0;

// Buffer intercalado Estereo (L, R) de 16 bits assinado.
static int16_t audio_buf[kAudioBlockFrames * 2];

// Inicializacao do Periferico I2S (PCM5102A)

static bool InitI2sPcm5102a()
{
  i2s_config_t i2s_cfg = {};
  i2s_cfg.mode = static_cast<i2s_mode_t>(I2S_MODE_MASTER | I2S_MODE_TX);
  i2s_cfg.sample_rate = kSampleRateHz;
  i2s_cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
  i2s_cfg.channel_format = I2S_CHANNEL_FMT_RIGHT_LEFT;
  i2s_cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
  i2s_cfg.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
  i2s_cfg.dma_buf_count = 4;
  i2s_cfg.dma_buf_len = kAudioBlockFrames;
  i2s_cfg.use_apll = false;
  i2s_cfg.tx_desc_auto_clear = true;

  if (i2s_driver_install(kI2sPortNum, &i2s_cfg, 0, nullptr) != ESP_OK)
  {
    return false;
  }

  i2s_pin_config_t pin_cfg = {};
  // PCM5102A gera MCLK internamente via PLL (SCK conectado ao GND).
  pin_cfg.mck_io_num = I2S_PIN_NO_CHANGE;
  pin_cfg.bck_io_num = kI2sBclkPin;
  pin_cfg.ws_io_num = kI2sLrckPin;
  pin_cfg.data_out_num = kI2sDoutPin;
  pin_cfg.data_in_num = I2S_PIN_NO_CHANGE;

  if (i2s_set_pin(kI2sPortNum, &pin_cfg) != ESP_OK)
  {
    return false;
  }

  i2s_zero_dma_buffer(kI2sPortNum);
  return true;
}

// Aplicacao Thread-Safe de Eventos MIDI no TinySoundFont

static void ApplyMidiEvent(const MidiEvent *ev)
{
  if (tsf_inst == nullptr || ev == nullptr)
  {
    return;
  }

  const uint8_t cmd_type = ev->status & 0xF0;
  const uint8_t nota = ev->data1 & 0x7F;
  const uint8_t velocity = ev->data2 & 0x7F;

  if (cmd_type == 0x90)
  {
    if (velocity > 0)
    {
      // Note On (0x90 com velocity > 0).
      tsf_note_on(tsf_inst, 0, nota,
                  static_cast<float>(velocity) / 127.0f);
    }
    else
    {
      // Note On com velocity == 0 equivale a Note Off no padrao MIDI 1.0.
      tsf_note_off(tsf_inst, 0, nota);
    }
  }
  else if (cmd_type == 0x80)
  {
    // Note Off (0x80).
    tsf_note_off(tsf_inst, 0, nota);
  }
  else if (cmd_type == 0xB0)
  {
    // Control Change (0xB0), ex: CC 64 (Sustain) ou CC 123 (All Notes Off).
    tsf_channel_midi_control(tsf_inst, 0, nota, velocity);
  }
}

// Parser UART MIDI 1.0 (Sincronismo Automatico de 24 bits pelo MSB)

static void EnqueueMidiEvent(uint8_t status, uint8_t d1, uint8_t d2)
{
  if (midi_queue != nullptr)
  {
    MidiEvent ev;
    ev.status = status;
    ev.data1 = d1;
    ev.data2 = d2;
    xQueueSend(midi_queue, &ev, 0);
  }
}

static void ProcessMidiByte(uint8_t byte_in)
{
  // Mensagens System Real-Time (0xF8..0xFF) tem 1 byte e nao afetam status.
  if (byte_in >= 0xF8)
  {
    return;
  }

  if ((byte_in & 0x80) != 0)
  {
    // Byte de Status (MSB == 1): alinha imediatamente o frame de 24 bits.
    status_byte = byte_in;
    data_idx = 0;
  }
  else if (status_byte != 0)
  {
    // Byte de Dados (MSB == 0): acumula nota e velocity.
    data_buf[data_idx++] = byte_in;

    if (data_idx >= 2)
    {
      EnqueueMidiEvent(status_byte, data_buf[0], data_buf[1]);
      data_idx = 0;
    }
  }
}

static void PollUartMidi()
{
  // Leitura da UART1 (FPGA DE0-CV via pino GPIO 18)
  while (Serial1.available() > 0)
  {
    ProcessMidiByte(static_cast<uint8_t>(Serial1.read()));
  }
}

// Task Dedicada de Renderizacao de Audio (Core 1)

static void AudioSynthTask(void *pv_parameters)
{
  (void)pv_parameters;
  MidiEvent ev;

  for (;;)
  {
    if (xSemaphoreTake(tsf_mutex, portMAX_DELAY) == pdTRUE)
    {
      // 1. Processa todos os pacotes MIDI recebidos desde o ultimo bloco.
      while (xQueueReceive(midi_queue, &ev, 0) == pdTRUE)
      {
        ApplyMidiEvent(&ev);
      }

      // 2. Renderiza bloco curto de audio estereo (64 frames = 128 int16_t).
      tsf_render_short(tsf_inst, audio_buf, kAudioBlockFrames, 0);

      xSemaphoreGive(tsf_mutex);
    }

    // 3. Transmite o bloco renderizado ao DAC PCM5102A via DMA I2S.
    size_t bytes_written = 0;
    i2s_write(kI2sPortNum, audio_buf, sizeof(audio_buf), &bytes_written,
              portMAX_DELAY);
  }
}

// Setup e Loop Principal (Core 0 / Loop de Leitura UART)

void setup()
{
  // Inicializa porta Serial USB para monitoramento e debug
  Serial.begin(115200);
  delay(100);
  Serial.println("\n[SISTEMA] Inicializando ESP32-S3 MIDI Synth...");

  // Inicializa UART1 em 115200 bps (8N1) para pacotes de 24 bits da FPGA DE0-CV (pino GPIO 18).
  Serial1.setRxBufferSize(kUartRxBufSize);
  Serial1.begin(kUartBaudRate, SERIAL_8N1, kUartRxPin, kUartTxPin);

  // Carrega o SoundFont embutido (piano_sf2.h) direto da Flash (0 bytes de RAM para amostras)
  Serial.println("[INFO] Carregando SoundFont de alta fidelidade...");
  tsf_inst = tsf_load_memory(g_piano_sf2, g_piano_sf2_len);
  if (tsf_inst == nullptr)
  {
    Serial.println("[ERRO] Falha ao carregar SoundFont embutido!");
    while (true)
    {
      delay(1000);
    }
  }
  Serial.println("[SUCESSO] SoundFont carregado direto da Flash!");

  // Primitivas de sincronizacao entre leitura UART e sintese de audio.
  tsf_mutex = xSemaphoreCreateMutex();
  midi_queue = xQueueCreate(kMidiQueueLength, sizeof(MidiEvent));

  // Configura saida estereo 44100 Hz e limite de polifonia (16 vozes).
  tsf_set_output(tsf_inst, TSF_STEREO_INTERLEAVED, kSampleRateHz,
                 kGlobalGainDb);
  tsf_set_max_voices(tsf_inst, kMaxPolyphonyVoices);

  // Inicializa periferico I2S para o DAC PCM5102A.
  if (!InitI2sPcm5102a())
  {
    Serial.println("[ERRO] Falha ao inicializar periferico I2S!");
    while (true)
    {
      delay(1000);
    }
  }

  // Inicia task de sintese em alta prioridade no Core 1 do ESP32-S3.
  xTaskCreatePinnedToCore(AudioSynthTask, "AudioSynthTask", 8192, nullptr,
                          configMAX_PRIORITIES - 2, nullptr, 1);

  Serial.println(
      "[OK] ESP32-S3 MIDI Synth (UART 115200 8N1 | I2S 44.1kHz 16-bit Stereo)");

  // Teste de boot: toca uma nota (Dó central - C4) para confirmar que o DAC e caixa estao ativos
  delay(100);
  EnqueueMidiEvent(0x90, 60, 80); // Note On: Do4 (nota 60), vel 80
}

void loop()
{
  // Le continuamente os bytes da Serial1 com latencia minima.
  PollUartMidi();
  vTaskDelay(1);
}