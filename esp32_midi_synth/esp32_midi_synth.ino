/*
 * esp32_midi_synth.ino
 *
 * Sintetizador MIDI 1.0 em tempo real para ESP32-S3 com TinySoundFont (tsf.h)
 * e saída de áudio digital I2S para DAC externo PCM5102A (44.1 kHz, 16-bit, Estéreo).
 *
 * Arquitetura:
 *   - Recebe pacotes MIDI 1.0 de 24 bits (3 bytes) via UART1 em 115200 bps (8N1)
 *     provenientes do FPGA Cyclone V (DE0-CV).
 *   - Sincroniza os frames de 24 bits automaticamente pelo bit mais significativo (MSB):
 *       * Byte de Status (MSB = 1, >= 0x80): inicia novo frame e armazena status_byte.
 *       * Bytes de Dados (MSB = 0, <  0x80): armazena nota (Byte 1) e velocity (Byte 2).
 *   - Enfileira os eventos MIDI em uma fila FreeRTOS thread-safe (sem bloqueio da UART)
 *     e protege o estado interno do TinySoundFont (tsf*) com mutex.
 *   - Renderiza blocos curtos de 64 frames (~1,45 ms por bloco) em 44100 Hz Estéreo
 *     e transmite via DMA I2S ao DAC PCM5102A.
 *
 * Compatibilidade:
 *   - ESP32-S3 (Arduino IDE / PlatformIO - Core ESP32 v2.x e v3.x).
 *   - Requer o arquivo single-header `tsf.h` (TinySoundFont de Bernhard Schelling)
 *     e `piano_sf2.h` (gerado por `sf2_to_header.py`) na mesma pasta do sketch.
 */

#include <Arduino.h>
#include <driver/i2s.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>

#define TSF_IMPLEMENTATION
#include "tsf.h"
#include "piano_sf2.h"

// ============================================================================
// Configuração de Pinos e Parâmetros de Hardware (ESP32-S3)
// ============================================================================

// Pinos da UART1 conectada ao pino `saida_serial` do FPGA DE0-CV (3.3V LVTTL)
#ifndef UART_RX_PIN
#define UART_RX_PIN       18
#endif

#ifndef UART_TX_PIN
#define UART_TX_PIN       17
#endif

#define UART_BAUD_RATE    115200
#define UART_RX_BUF_SIZE  1024

// Pinos do barramento I2S conectados ao módulo DAC PCM5102A
// (No PCM5102A: SCK conectado ao GND, BCK -> I2S_BCLK_PIN, DIN -> I2S_DOUT_PIN, LCK -> I2S_LRCK_PIN)
#ifndef I2S_BCLK_PIN
#define I2S_BCLK_PIN      4
#endif

#ifndef I2S_LRCK_PIN
#define I2S_LRCK_PIN      5
#endif

#ifndef I2S_DOUT_PIN
#define I2S_DOUT_PIN      6
#endif

#define I2S_PORT_NUM      I2S_NUM_0

// Parâmetros de síntese e baixa latência (< 3 ms)
#define SAMPLE_RATE_HZ        44100
#define AUDIO_BLOCK_FRAMES    64      // 64 frames @ 44.1 kHz = ~1.45 ms por bloco
#define MAX_POLYPHONY_VOICES  16
#define GLOBAL_GAIN_DB        0.0f
#define MIDI_QUEUE_LENGTH     128

// ============================================================================
// Estruturas e Variáveis Globais
// ============================================================================

typedef struct {
    uint8_t status;
    uint8_t data1; // Nota MIDI (0..127) ou número do Control Change
    uint8_t data2; // Velocity (0..127) ou valor do Control Change
} midi_event_t;

static tsf*              g_tsf       = NULL;
static SemaphoreHandle_t g_tsf_mutex = NULL;
static QueueHandle_t     g_midi_q    = NULL;

// Estado do parser MIDI 1.0 com sincronismo pelo MSB (bit 7)
static uint8_t g_status_byte = 0;
static uint8_t g_data_buf[2] = {0, 0};
static uint8_t g_data_idx    = 0;

// Buffer intercalado Estéreo (L, R) de 16 bits assinado
static int16_t g_audio_buf[AUDIO_BLOCK_FRAMES * 2];

// ============================================================================
// Inicialização do Periférico I2S (PCM5102A)
// ============================================================================

static bool init_i2s_pcm5102a(void) {
    i2s_config_t i2s_cfg = {};
    i2s_cfg.mode                 = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX);
    i2s_cfg.sample_rate          = SAMPLE_RATE_HZ;
    i2s_cfg.bits_per_sample      = I2S_BITS_PER_SAMPLE_16BIT;
    i2s_cfg.channel_format       = I2S_CHANNEL_FMT_RIGHT_LEFT;
    i2s_cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
    i2s_cfg.intr_alloc_flags     = ESP_INTR_FLAG_LEVEL1;
    i2s_cfg.dma_buf_count        = 4;
    i2s_cfg.dma_buf_len          = AUDIO_BLOCK_FRAMES;
    i2s_cfg.use_apll             = false;
    i2s_cfg.tx_desc_auto_clear   = true;

    if (i2s_driver_install(I2S_PORT_NUM, &i2s_cfg, 0, NULL) != ESP_OK) {
        return false;
    }

    i2s_pin_config_t pin_cfg = {};
    pin_cfg.mck_io_num   = I2S_PIN_NO_CHANGE; // PCM5102A gera MCLK internamente via PLL (SCK no GND)
    pin_cfg.bck_io_num   = I2S_BCLK_PIN;
    pin_cfg.ws_io_num    = I2S_LRCK_PIN;
    pin_cfg.data_out_num = I2S_DOUT_PIN;
    pin_cfg.data_in_num  = I2S_PIN_NO_CHANGE;

    if (i2s_set_pin(I2S_PORT_NUM, &pin_cfg) != ESP_OK) {
        return false;
    }

    i2s_zero_dma_buffer(I2S_PORT_NUM);
    return true;
}

// ============================================================================
// Aplicação Thread-Safe de Eventos MIDI no TinySoundFont
// ============================================================================

static void apply_midi_event(const midi_event_t* ev) {
    if (g_tsf == NULL) {
        return;
    }

    const uint8_t cmd_type = ev->status & 0xF0;
    const uint8_t nota     = ev->data1 & 0x7F;
    const uint8_t velocity = ev->data2 & 0x7F;

    if (cmd_type == 0x90) {
        if (velocity > 0) {
            // Note On (0x90 com velocity > 0)
            tsf_note_on(g_tsf, 0, nota, (float)velocity / 127.0f);
        } else {
            // Note On com velocity == 0 equivale a Note Off no padrão MIDI 1.0
            tsf_note_off(g_tsf, 0, nota);
        }
    } else if (cmd_type == 0x80) {
        // Note Off (0x80)
        tsf_note_off(g_tsf, 0, nota);
    } else if (cmd_type == 0xB0) {
        // Control Change (0xB0), ex: CC 64 (Sustain Pedal) ou CC 123 (All Notes Off)
        tsf_channel_midi_control(g_tsf, 0, nota, velocity);
    }
}

// ============================================================================
// Parser UART MIDI 1.0 (Sincronismo Automático de 24 bits pelo MSB)
// ============================================================================

static void poll_uart_midi(void) {
    while (Serial1.available() > 0) {
        const uint8_t byte_in = (uint8_t)Serial1.read();

        // Mensagens System Real-Time (0xF8..0xFF) têm 1 byte e não alteram o Running Status
        if (byte_in >= 0xF8) {
            continue;
        }

        if ((byte_in & 0x80) != 0) {
            // Byte de Status (MSB == 1): alinha imediatamente o início do frame de 24 bits
            g_status_byte = byte_in;
            g_data_idx    = 0;
        } else if (g_status_byte != 0) {
            // Byte de Dados (MSB == 0): acumula nota e velocity
            g_data_buf[g_data_idx++] = byte_in;

            if (g_data_idx >= 2) {
                midi_event_t ev;
                ev.status = g_status_byte;
                ev.data1  = g_data_buf[0];
                ev.data2  = g_data_buf[1];

                // Zera o índice mantendo g_status_byte para suportar Running Status
                g_data_idx = 0;

                // Envia para a fila consumida antes da renderização de cada bloco de áudio
                if (g_midi_q != NULL) {
                    xQueueSend(g_midi_q, &ev, 0);
                }
            }
        }
    }
}

// ============================================================================
// Task Dedicada de Renderização de Áudio (Core 1)
// ============================================================================

static void audio_synth_task(void* pvParameters) {
    (void)pvParameters;
    midi_event_t ev;

    for (;;) {
        if (xSemaphoreTake(g_tsf_mutex, portMAX_DELAY) == pdTRUE) {
            // 1. Processa todos os pacotes MIDI recebidos desde o último bloco
            while (xQueueReceive(g_midi_q, &ev, 0) == pdTRUE) {
                apply_midi_event(&ev);
            }

            // 2. Renderiza um bloco curto de áudio estéreo intercalado (64 frames = 128 int16_t)
            tsf_render_short(g_tsf, g_audio_buf, AUDIO_BLOCK_FRAMES, 0);

            xSemaphoreGive(g_tsf_mutex);
        }

        // 3. Transmite o bloco renderizado ao DAC PCM5102A via DMA I2S
        size_t bytes_written = 0;
        i2s_write(
            I2S_PORT_NUM,
            (const void*)g_audio_buf,
            sizeof(g_audio_buf),
            &bytes_written,
            portMAX_DELAY
        );
    }
}

// ============================================================================
// Setup e Loop Principal (Core 0 / Loop de Leitura UART)
// ============================================================================

void setup() {
    Serial.begin(115200);

    // Inicializa UART1 em 115200 bps (8N1) para receber os pacotes de 24 bits do FPGA
    Serial1.setRxBufferSize(UART_RX_BUF_SIZE);
    Serial1.begin(UART_BAUD_RATE, SERIAL_8N1, UART_RX_PIN, UART_TX_PIN);

    // Primitivas de sincronização entre leitura UART e síntese de áudio
    g_tsf_mutex = xSemaphoreCreateMutex();
    g_midi_q    = xQueueCreate(MIDI_QUEUE_LENGTH, sizeof(midi_event_t));

    // Carrega o SoundFont (.sf2) da memória Flash/PSRAM
    g_tsf = tsf_load_memory(g_piano_sf2, sizeof(g_piano_sf2));
    if (g_tsf == NULL) {
        Serial.println("[ERRO] Falha ao carregar SoundFont (g_piano_sf2) na memoria!");
        while (true) {
            delay(1000);
        }
    }

    // Configura saída estéreo 44100 Hz e limite de polifonia (16 vozes simultâneas)
    tsf_set_output(g_tsf, TSF_STEREO_INTERLEAVED, SAMPLE_RATE_HZ, GLOBAL_GAIN_DB);
    tsf_set_max_voices(g_tsf, MAX_POLYPHONY_VOICES);

    // Inicializa periférico I2S para o DAC PCM5102A
    if (!init_i2s_pcm5102a()) {
        Serial.println("[ERRO] Falha ao inicializar o periferico I2S para o PCM5102A!");
        while (true) {
            delay(1000);
        }
    }

    // Inicia task de síntese em alta prioridade no Core 1 do ESP32-S3
    xTaskCreatePinnedToCore(
        audio_synth_task,
        "AudioSynthTask",
        8192,
        NULL,
        configMAX_PRIORITIES - 2,
        NULL,
        1
    );

    Serial.println("[OK] ESP32-S3 MIDI Synth iniciado (UART 115200 8N1 | I2S 44.1kHz 16-bit Stereo).");
}

void loop() {
    // Lê continuamente os bytes da Serial1 com latência mínima
    poll_uart_midi();
    vTaskDelay(1);
}
