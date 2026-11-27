// Motor Unificado de Co-Simulacao Ciclo-Exata: FPGA (Vpiano_top) + ESP32-S3 (esp32_midi_synth.ino)
// Compila diretamente o sketch real esp32_midi_synth.ino sem duplicacao de codigo,
// demodula o pino fisico saida_serial bit a bit (UART 8N1) e audita o sintetizador
// TinySoundFont (vozes ativas, pareamento MIDI e invariantes do sinal PCM).

#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vector>

#include "Vpiano_top.h"

// Inclui diretamente o firmware real do ESP32-S3 (zero codigo duplicado)
#include "../esp32_midi_synth/esp32_midi_synth.ino"

#ifdef _WIN32
#define COSIM_EXPORT extern "C" __declspec(dllexport)
#else
#define COSIM_EXPORT extern "C"
#endif

// Demodulador UART 8N1 bit-a-bit conectado ao pino saida_serial da FPGA
struct UartRxMonitor
{
  enum State
  {
    kIdle = 0,
    kStartBit = 1,
    kDataBits = 2,
    kStopBit = 3
  };

  State state;
  uint32_t clock_div;
  uint32_t wait_cycles;
  uint8_t bit_idx;
  uint8_t shift_reg;
  uint8_t prev_pin;
  uint32_t framing_errors;
  uint32_t bytes_received;

  void init(uint32_t div)
  {
    state = kIdle;
    clock_div = (div >= 2U) ? div : 2U;
    wait_cycles = 0;
    bit_idx = 0;
    shift_reg = 0;
    prev_pin = 1;
    framing_errors = 0;
    bytes_received = 0;
  }

  // Chamado a cada borda de subida do clock da FPGA
  bool step(uint8_t pin_val, uint8_t &out_byte)
  {
    uint8_t pin = pin_val & 1U;
    bool got_byte = false;

    switch (state)
    {
    case kIdle:
      if (prev_pin == 1U && pin == 0U)
      {
        // Borda de descida do start bit detectada: amostra no meio do start bit
        uint32_t half = clock_div / 2U;
        if (half <= 1U)
        {
          // Para divisores muito pequenos (ex: ClockDiv = 2 ou 3), ja estamos no meio
          state = kDataBits;
          wait_cycles = clock_div - 1U;
          bit_idx = 0;
          shift_reg = 0;
        }
        else
        {
          state = kStartBit;
          wait_cycles = half - 1U;
        }
      }
      break;

    case kStartBit:
      if (wait_cycles > 0U)
      {
        wait_cycles--;
      }
      if (wait_cycles == 0U)
      {
        if (pin != 0U)
        {
          framing_errors++;
          state = kIdle;
        }
        else
        {
          state = kDataBits;
          wait_cycles = clock_div;
          bit_idx = 0;
          shift_reg = 0;
        }
      }
      break;

    case kDataBits:
      if (wait_cycles > 0U)
      {
        wait_cycles--;
      }
      if (wait_cycles == 0U)
      {
        shift_reg |= static_cast<uint8_t>(pin << bit_idx);
        bit_idx++;
        if (bit_idx >= 8U)
        {
          state = kStopBit;
          wait_cycles = clock_div;
        }
        else
        {
          wait_cycles = clock_div;
        }
      }
      break;

    case kStopBit:
      if (wait_cycles > 0U)
      {
        wait_cycles--;
      }
      if (wait_cycles == 0U)
      {
        if (pin != 1U)
        {
          framing_errors++;
        }
        else
        {
          out_byte = shift_reg;
          bytes_received++;
          got_byte = true;
        }
        state = kIdle;
      }
      break;
    }

    prev_pin = pin;
    return got_byte;
  }
};

struct MidiLogEntry
{
  uint64_t cycle;
  uint8_t status;
  uint8_t data1;
  uint8_t data2;
};

struct CoSimContext
{
  Vpiano_top *fpga;
  UartRxMonitor uart_rx;

  // Escala temporal
  uint32_t cycles_per_uart_poll; // 1 ms equivalente
  uint32_t cycles_per_i2s_block; // 5.333 ms equivalente (256 frames @ 48 kHz)
  uint32_t uart_poll_counter;
  uint32_t i2s_block_counter;
  uint64_t total_cycles;

  // Monitoramento MIDI e pareamento Note On / Note Off
  std::vector<MidiLogEntry> midi_log;
  int32_t note_active_count[128];
  uint32_t note_on_total;
  uint32_t note_off_total;
  uint32_t overlap_violations;
  uint32_t orphan_note_offs;
  uint8_t last_midi_status;
  uint8_t last_midi_data1;
  uint8_t last_midi_data2;

  // Monitoramento e captura PCM (48 kHz 16-bit Stereo)
  std::vector<int16_t> pcm_recording;
  std::vector<int16_t> realtime_pcm_fifo;
  bool record_pcm;
  int32_t max_abs_sample;
  int32_t last_block_peak_l;
  int32_t last_block_peak_r;
  double last_block_rms;
  int64_t sum_samples_dc;
  double sum_sq_samples;
  uint64_t total_pcm_samples;
  uint32_t clipped_samples;
  uint32_t active_note_blocks;
  uint32_t active_note_silent_blocks;

  // Acumulador de brilho PWM dos LEDs para a bancada virtual
  uint32_t led_on_Accum[7];
  uint32_t led_sample_cycles;
  uint32_t stuck_voice_blocks;
  int32_t max_active_voices_seen;
};

static CoSimContext g_ctx;

// Inspeciona diretamente o estado interno do TinySoundFont (tsf_inst)
static int CountSustainedVoices(int only_key = -1)
{
  if (tsf_inst == nullptr || tsf_inst->voices == nullptr)
  {
    return 0;
  }
  int count = 0;
  for (int i = 0; i < tsf_inst->voiceNum; ++i)
  {
    const struct tsf_voice &v = tsf_inst->voices[i];
    if (v.playingPreset != -1 && v.ampenv.segment < TSF_SEGMENT_RELEASE)
    {
      if (only_key < 0 || v.playingKey == only_key)
      {
        count++;
      }
    }
  }
  return count;
}

static int CountTotalActiveVoices()
{
  if (tsf_inst == nullptr)
  {
    return 0;
  }
  return tsf_active_voice_count(tsf_inst);
}

static void OnMidiEventEnqueued(uint8_t status, uint8_t d1, uint8_t d2)
{
  MidiLogEntry entry;
  entry.cycle = g_ctx.total_cycles;
  entry.status = status;
  entry.data1 = d1;
  entry.data2 = d2;
  g_ctx.midi_log.push_back(entry);

  g_ctx.last_midi_status = status;
  g_ctx.last_midi_data1 = d1;
  g_ctx.last_midi_data2 = d2;

  uint8_t cmd = status & 0xF0U;
  uint8_t note = d1 & 0x7FU;
  uint8_t vel = d2 & 0x7FU;

  if (cmd == 0x90U && vel > 0U)
  {
    // Verifica se outra nota da FPGA ficou ligada sem Note Off previo
    for (int k = 0; k < 128; ++k)
    {
      if (g_ctx.note_active_count[k] > 0)
      {
        g_ctx.overlap_violations++;
      }
    }
    g_ctx.note_active_count[note]++;
    g_ctx.note_on_total++;
  }
  else if (cmd == 0x80U || (cmd == 0x90U && vel == 0U))
  {
    if (g_ctx.note_active_count[note] <= 0)
    {
      g_ctx.orphan_note_offs++;
    }
    else
    {
      g_ctx.note_active_count[note]--;
    }
    g_ctx.note_off_total++;
  }
}

static void OnI2sBlockWritten(const int16_t *samples, size_t stereo_frames)
{
  int32_t peak_l = 0;
  int32_t peak_r = 0;
  double block_energy = 0.0;
  size_t total_shorts = stereo_frames * 2U;

  for (size_t i = 0; i < stereo_frames; ++i)
  {
    int16_t s_l = samples[2U * i];
    int16_t s_r = samples[2U * i + 1U];
    int32_t abs_l = (s_l < 0) ? -static_cast<int32_t>(s_l) : static_cast<int32_t>(s_l);
    int32_t abs_r = (s_r < 0) ? -static_cast<int32_t>(s_r) : static_cast<int32_t>(s_r);

    if (abs_l > peak_l)
      peak_l = abs_l;
    if (abs_r > peak_r)
      peak_r = abs_r;
    if (abs_l > g_ctx.max_abs_sample)
      g_ctx.max_abs_sample = abs_l;
    if (abs_r > g_ctx.max_abs_sample)
      g_ctx.max_abs_sample = abs_r;

    if (abs_l >= 32767)
      g_ctx.clipped_samples++;
    if (abs_r >= 32767)
      g_ctx.clipped_samples++;

    g_ctx.sum_samples_dc += s_l + s_r;
    double fl = static_cast<double>(s_l);
    double fr = static_cast<double>(s_r);
    block_energy += fl * fl + fr * fr;
  }

  g_ctx.sum_sq_samples += block_energy;
  g_ctx.total_pcm_samples += total_shorts;
  g_ctx.last_block_peak_l = peak_l;
  g_ctx.last_block_peak_r = peak_r;
  g_ctx.last_block_rms =
      (total_shorts > 0) ? sqrt(block_energy / static_cast<double>(total_shorts)) : 0.0;

  int cur_tot_voices = CountTotalActiveVoices();
  if (cur_tot_voices > g_ctx.max_active_voices_seen)
  {
    g_ctx.max_active_voices_seen = cur_tot_voices;
  }

  if (CountSustainedVoices() > 0)
  {
    g_ctx.active_note_blocks++;
    if (peak_l == 0 && peak_r == 0)
    {
      g_ctx.active_note_silent_blocks++;
    }
    if (g_ctx.fpga != nullptr && g_ctx.fpga->debug_nota_tocando_tx() == 0U &&
        Serial1.available() == 0)
    {
      g_ctx.stuck_voice_blocks++;
    }
    else
    {
      g_ctx.stuck_voice_blocks = 0;
    }
  }
  else
  {
    g_ctx.stuck_voice_blocks = 0;
  }

  if (g_ctx.record_pcm)
  {
    g_ctx.pcm_recording.insert(g_ctx.pcm_recording.end(), samples,
                               samples + total_shorts);
  }
  if (g_ctx.realtime_pcm_fifo.size() < static_cast<size_t>(kSampleRateHz) * 2U)
  {
    g_ctx.realtime_pcm_fifo.insert(g_ctx.realtime_pcm_fifo.end(), samples,
                                   samples + total_shorts);
  }
}

static bool WriteWavFile(const char *filepath, const std::vector<int16_t> &pcm,
                         uint32_t sample_rate = static_cast<uint32_t>(kSampleRateHz))
{
  FILE *f = fopen(filepath, "wb");
  if (!f)
  {
    return false;
  }
  uint32_t data_bytes = static_cast<uint32_t>(pcm.size() * sizeof(int16_t));
  uint32_t riff_size = 36U + data_bytes;
  uint16_t audio_format = 1U; // PCM
  uint16_t num_channels = 2U; // Stereo
  uint16_t bits_per_sample = 16U;
  uint32_t byte_rate = sample_rate * num_channels * (bits_per_sample / 8U);
  uint16_t block_align = num_channels * (bits_per_sample / 8U);
  uint32_t fmt_chunk_size = 16U;

  fwrite("RIFF", 1, 4, f);
  fwrite(&riff_size, 4, 1, f);
  fwrite("WAVE", 1, 4, f);
  fwrite("fmt ", 1, 4, f);
  fwrite(&fmt_chunk_size, 4, 1, f);
  fwrite(&audio_format, 2, 1, f);
  fwrite(&num_channels, 2, 1, f);
  fwrite(&sample_rate, 4, 1, f);
  fwrite(&byte_rate, 4, 1, f);
  fwrite(&block_align, 2, 1, f);
  fwrite(&bits_per_sample, 2, 1, f);
  fwrite("data", 1, 4, f);
  fwrite(&data_bytes, 4, 1, f);
  if (!pcm.empty())
  {
    fwrite(pcm.data(), sizeof(int16_t), pcm.size(), f);
  }
  fclose(f);
  return true;
}

static void StepCycles(uint64_t num_cycles)
{
  Vpiano_top *fpga = g_ctx.fpga;
  for (uint64_t i = 0; i < num_cycles; ++i)
  {
    // Borda de descida
    fpga->clk = 0;
    fpga->eval();

    // Borda de subida
    fpga->clk = 1;
    fpga->eval();
    g_ctx.total_cycles++;

    // Acumula estado instantaneo dos LEDs vermelhos (PWM)
    uint8_t leds = fpga->led_vermelho;
    for (int b = 0; b < 7; ++b)
    {
      if ((leds >> b) & 1U)
      {
        g_ctx.led_on_Accum[b]++;
      }
    }
    g_ctx.led_sample_cycles++;

    // Demodula o pino fisico saida_serial bit a bit (8N1)
    uint8_t rx_byte = 0;
    if (g_ctx.uart_rx.step(fpga->saida_serial, rx_byte))
    {
      Serial1.pushRxByte(rx_byte);
    }

    // Task de leitura UART do ESP32 (a cada 1 ms equivalente)
    g_ctx.uart_poll_counter++;
    if (g_ctx.uart_poll_counter >= g_ctx.cycles_per_uart_poll)
    {
      g_ctx.uart_poll_counter = 0;
      loop();
    }

    // Task de sintese I2S do ESP32 (a cada bloco de 256 frames = 5.333 ms eq.)
    g_ctx.i2s_block_counter++;
    if (g_ctx.i2s_block_counter >= g_ctx.cycles_per_i2s_block)
    {
      g_ctx.i2s_block_counter = 0;
      sim_step_audio_block();
    }
  }
}

static void ResetFpga()
{
  Vpiano_top *fpga = g_ctx.fpga;
  fpga->gpio_keys = 0;
  fpga->btn_modo_n = 1;
  fpga->btn_musica_n = 1;
  fpga->btn_intensidade_n = 1;
  fpga->btn_oitava_up_n = 1;
  fpga->btn_oitava_down_n = 1;
  fpga->btn_sustenido = 0;
  fpga->reset_n = 0;
  StepCycles(6);
  fpga->reset_n = 1;
  StepCycles(10);
}

static void WaitUartAndAudioIdle(uint32_t extra_blocks = 2)
{
  // Aguarda eventual transmissao UART em curso (2 pacotes MIDI + poll + blocos I2S)
  uint32_t wait_c =
      (70U * g_ctx.fpga->param_clock_div_uart) + g_ctx.cycles_per_uart_poll * 2U +
      g_ctx.cycles_per_i2s_block * extra_blocks;
  StepCycles(wait_c);
}

static void PressControlBtn(uint8_t &btn_n)
{
  btn_n = 0;
  StepCycles(g_ctx.fpga->param_debounce_controle + 8U);
  btn_n = 1;
  StepCycles(g_ctx.fpga->param_debounce_controle + 8U);
}

static void InitCoSimEngine(bool full_50mhz, const char *rom_hex_path,
                            bool record_wav)
{
  // Limpa estado anterior se reinicializando
  if (g_ctx.fpga != nullptr)
  {
    delete g_ctx.fpga;
    g_ctx.fpga = nullptr;
  }
  if (tsf_inst != nullptr)
  {
    tsf_close(tsf_inst);
    tsf_inst = nullptr;
  }
  if (midi_queue != nullptr)
  {
    SimQueue *q = static_cast<SimQueue *>(midi_queue);
    free(q->storage);
    free(q);
    midi_queue = nullptr;
  }
  if (tsf_mutex != nullptr)
  {
    free(tsf_mutex);
    tsf_mutex = nullptr;
  }

  // Escala temporal:
  // 1:1 (50 MHz) vs Escala Proporcional Exata ~1:108.5 (ClockDivUart=4)
  uint32_t clk_div_uart = full_50mhz ? 434U : 4U;
  uint32_t tick_8ms = full_50mhz ? 400000U : 3686U;
  uint32_t db_ctrl = full_50mhz ? 400000U : 3686U;
  uint32_t db_key = full_50mhz ? 500000U : 4608U;

  g_ctx.fpga =
      new Vpiano_top(db_key, db_ctrl, clk_div_uart, tick_8ms, rom_hex_path);
  g_ctx.uart_rx.init(clk_div_uart);

  g_ctx.cycles_per_uart_poll = full_50mhz ? 50000U : 461U;
  g_ctx.cycles_per_i2s_block = full_50mhz ? 266667U : 2458U;
  g_ctx.uart_poll_counter = 0;
  g_ctx.i2s_block_counter = 0;
  g_ctx.total_cycles = 0;

  g_ctx.midi_log.clear();
  memset(g_ctx.note_active_count, 0, sizeof(g_ctx.note_active_count));
  g_ctx.note_on_total = 0;
  g_ctx.note_off_total = 0;
  g_ctx.overlap_violations = 0;
  g_ctx.orphan_note_offs = 0;
  g_ctx.last_midi_status = 0;
  g_ctx.last_midi_data1 = 0;
  g_ctx.last_midi_data2 = 0;

  g_ctx.pcm_recording.clear();
  g_ctx.realtime_pcm_fifo.clear();
  g_ctx.record_pcm = record_wav;
  g_ctx.max_abs_sample = 0;
  g_ctx.last_block_peak_l = 0;
  g_ctx.last_block_peak_r = 0;
  g_ctx.last_block_rms = 0.0;
  g_ctx.sum_samples_dc = 0;
  g_ctx.sum_sq_samples = 0.0;
  g_ctx.total_pcm_samples = 0;
  g_ctx.clipped_samples = 0;
  g_ctx.active_note_blocks = 0;
  g_ctx.active_note_silent_blocks = 0;
  memset(g_ctx.led_on_Accum, 0, sizeof(g_ctx.led_on_Accum));
  g_ctx.led_sample_cycles = 0;
  g_ctx.stuck_voice_blocks = 0;
  g_ctx.max_active_voices_seen = 0;

  // Registra callbacks no HAL do ESP32 e limpa estado de task anterior
  Esp32SimHalState &hal = sim_hal_state();
  hal.audio_task_fn = nullptr;
  hal.i2s_initialized = false;
  hal.i2s_yield_active = false;
  hal.on_i2s_write_cb = OnI2sBlockWritten;
  hal.on_midi_enqueue_cb = OnMidiEventEnqueued;
  hal.on_delay_ms_cb = nullptr;
  hal.total_i2s_frames = 0;
  hal.vtask_delay_calls = 0;

  Serial.setQuiet(true);
  Serial1.setQuiet(true);
  Serial1.clearRx();
  status_byte = 0;
  data_buf[0] = 0;
  data_buf[1] = 0;
  data_idx = 0;

  // Inicializa o firmware do ESP32 (setup() carrega SoundFont e toca nota de boot)
  setup();

  // Reseta a FPGA
  ResetFpga();
}

// ============================================================================
// Suite Automatizada de Testes Ponta-a-Ponta (FPGA -> UART 8N1 -> ESP32 -> PCM)
// ============================================================================

// Estima a frequencia fundamental (Hz) dos ultimos `window` frames (canal L)
// por autocorrelacao normalizada. Retorna 0 se nao houver sinal periodico.
static double MeasureTailFrequencyHz(size_t window)
{
  const std::vector<int16_t> &pcm = g_ctx.pcm_recording;
  if (pcm.size() / 2U < window)
  {
    return 0.0;
  }
  std::vector<double> x(window);
  size_t start = pcm.size() / 2U - window;
  double mean = 0.0;
  for (size_t i = 0; i < window; ++i)
  {
    x[i] = pcm[(start + i) * 2U];
    mean += x[i];
  }
  mean /= static_cast<double>(window);
  double energy = 0.0;
  for (size_t i = 0; i < window; ++i)
  {
    x[i] -= mean;
    energy += x[i] * x[i];
  }
  if (energy < 1.0)
  {
    return 0.0;
  }
  const int min_lag = kSampleRateHz / 1500;
  const int max_lag = kSampleRateHz / 40;
  std::vector<double> r(max_lag + 2, 0.0);
  double best = 0.0;
  for (int lag = min_lag; lag <= max_lag; ++lag)
  {
    double s = 0.0;
    for (size_t i = 0; i + lag < window; ++i)
    {
      s += x[i] * x[i + lag];
    }
    r[lag] = s / energy;
    if (r[lag] > best)
    {
      best = r[lag];
    }
  }
  if (best < 0.3)
  {
    return 0.0;
  }
  // Menor lag que seja maximo local com pelo menos 90% do melhor pico.
  for (int lag = min_lag + 1; lag < max_lag; ++lag)
  {
    if (r[lag] >= 0.9 * best && r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1])
    {
      double a = r[lag - 1], b = r[lag], c = r[lag + 1];
      double d = a - 2.0 * b + c;
      double off = (d != 0.0) ? 0.5 * (a - c) / d : 0.0;
      return static_cast<double>(kSampleRateHz) / (lag + off);
    }
  }
  return 0.0;
}

static int RunAutomatedSuite(bool full_50mhz, const char *wav_out_path,
                             const char *rom_hex_path)
{
  int failures = 0;
  auto check = [&](bool cond, const char *test_name, const char *detail) {
    if (!cond)
    {
      fprintf(stderr, "  [FALHA] %s: %s\n", test_name, detail);
      failures++;
    }
  };

  printf("====================================================================\n");
  printf(" SUITE DE CO-SIMULACAO LOGICA E AUDIO: FPGA CYCLONE V + ESP32-S3\n");
  printf(" Escala: %s\n",
         full_50mhz ? "1:1 (50 MHz Real)" : "Proporcional Exata (ClockDivUart=4)");
  printf("====================================================================\n");

  // --------------------------------------------------------------------------
  // Teste 1: Boot do ESP32 (setup() -> C4 Note On -> 350ms Audio -> Note Off)
  // --------------------------------------------------------------------------
  printf("[1/12] Auditando boot do ESP32-S3 (SoundFont + autoteste C4)...\n");
  InitCoSimEngine(full_50mhz, rom_hex_path, true);

  check(tsf_inst != nullptr, "ESP32_BOOT", "tsf_inst nulo apos setup()");
  check(g_ctx.midi_log.size() == 2U, "ESP32_BOOT",
        "setup() deveria enfileirar exatamente 2 eventos MIDI (Note On/Off C4)");
  if (g_ctx.midi_log.size() >= 2U)
  {
    check(g_ctx.midi_log[0].status == 0x90U && g_ctx.midi_log[0].data1 == 60U &&
              g_ctx.midi_log[0].data2 == 48U,
          "ESP32_BOOT_ON", "Evento Note On de boot incorreto");
    check(g_ctx.midi_log[1].status == 0x80U && g_ctx.midi_log[1].data1 == 60U,
          "ESP32_BOOT_OFF", "Evento Note Off de boot incorreto");
  }
  check(g_ctx.max_abs_sample > 500, "ESP32_BOOT_AUDIO",
        "Sinal PCM de boot silencioso ou amplitude insuficiente");

  // Processa 1 bloco I2S apos o Note Off de boot e verifica que nenhuma voz segue sustentada
  sim_step_audio_block();
  check(CountSustainedVoices() == 0, "ESP32_BOOT_RELEASE",
        "Voz de boot continuou em sustentacao apos Note Off");

  // Renderiza cauda de release (~1s) e verifica 0 vozes ativas
  for (int i = 0; i < 180; ++i)
  {
    sim_step_audio_block();
  }
  check(CountTotalActiveVoices() == 0, "ESP32_BOOT_ZERO_ZOMBIES",
        "Voz zumbi permaneceu ativa no TSF apos fim do release de boot");
  printf("      OK: SoundFont carregado, pico PCM = %d, 0 vozes zumbis.\n",
         g_ctx.max_abs_sample);

  // --------------------------------------------------------------------------
  // Teste 2: Modo 0 (Livre) — Prioridade, Acordes, Legato e Fallback
  // --------------------------------------------------------------------------
  printf("[2/12] Testando Modo 0 (Livre): prioridade de borda, acordes e legato...\n");
  size_t log_base = g_ctx.midi_log.size();
  Vpiano_top *fpga = g_ctx.fpga;

  auto set_mode = [&](uint8_t target_mode) {
    for (int tries = 0; tries < 4 && fpga->debug_modo_ativo() != target_mode; ++tries)
    {
      PressControlBtn(fpga->btn_modo_n);
    }
    check(fpga->debug_modo_ativo() == target_mode, "HELPER_SET_MODE",
          "Falha ao atingir modo alvo");
  };

  auto select_song = [&](uint8_t target_song) {
    for (int tries = 0; tries < 43 && fpga->debug_sel_musica() != target_song; ++tries)
    {
      PressControlBtn(fpga->btn_musica_n);
    }
    check(fpga->debug_sel_musica() == target_song, "HELPER_SELECT_SONG",
          "Falha ao selecionar musica alvo");
  };

  auto drain_tsf_voices = [&]() {
    for (int i = 0; i < 180; ++i)
    {
      sim_step_audio_block();
    }
  };

  auto trigger_vol_combo = [&]() {
    fpga->btn_modo_n = 0;
    StepCycles(fpga->param_debounce_controle + 10U);
    PressControlBtn(fpga->btn_intensidade_n);
    fpga->btn_modo_n = 1;
    StepCycles(fpga->param_debounce_controle + 10U);
  };

  auto measure_pcm_over_blocks = [&](int blocks, int32_t &out_peak, double &out_rms) {
    out_peak = 0;
    double sum_sq = 0.0;
    for (int b = 0; b < blocks; ++b)
    {
      StepCycles(g_ctx.cycles_per_i2s_block);
      int32_t p = (g_ctx.last_block_peak_l > g_ctx.last_block_peak_r)
                      ? g_ctx.last_block_peak_l
                      : g_ctx.last_block_peak_r;
      if (p > out_peak)
        out_peak = p;
      sum_sq += g_ctx.last_block_rms * g_ctx.last_block_rms;
    }
    out_rms = (blocks > 0) ? sqrt(sum_sq / static_cast<double>(blocks)) : 0.0;
  };

  // Pressiona Do4 (tecla 0)
  fpga->gpio_keys = 0x01U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(3);
  check(CountSustainedVoices(60) > 0, "LIVRE_C4_ON",
        "Voz de Do4 (60) nao ativou no TSF");
  check(g_ctx.last_block_rms > 20.0, "LIVRE_C4_RMS",
        "Energia RMS nula durante nota Do4 ativa");

  // Sem soltar Do4, pressiona Mi4 (tecla 2 -> 0x05) e depois Sol4 (tecla 4 -> 0x15)
  fpga->gpio_keys = 0x05U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(60) == 0 && CountSustainedVoices(64) > 0,
        "LIVRE_LEGATO_E4",
        "Troca legato C4->E4 deixou C4 sustentado ou nao ativou E4");

  fpga->gpio_keys = 0x15U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(64) == 0 && CountSustainedVoices(67) > 0,
        "LIVRE_LEGATO_G4",
        "Troca legato E4->G4 deixou E4 sustentado ou nao ativou G4");

  // Solta Sol4 mantendo Do4+Mi4 (0x05): deve fazer fallback para Mi4 (maior indice)
  fpga->gpio_keys = 0x05U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(67) == 0 && CountSustainedVoices(64) > 0,
        "LIVRE_FALLBACK_E4", "Soltar G4 nao retornou para tecla mantida E4");

  // Solta Mi4 mantendo Do4 (0x01): deve fazer fallback para Do4
  fpga->gpio_keys = 0x01U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(64) == 0 && CountSustainedVoices(60) > 0,
        "LIVRE_FALLBACK_C4", "Soltar E4 nao retornou para tecla mantida C4");

  // Solta todas as teclas
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices() == 0, "LIVRE_ALL_RELEASED",
        "Tecla continuou sustentada no TSF apos soltar todas as teclas fisicas");
  check(g_ctx.overlap_violations == 0, "LIVRE_NO_OVERLAP",
        "Violacao de sobreposicao: Note On emitido sem Note Off da nota anterior");
  printf("      OK: %zu eventos MIDI verificados sem sobreposicao.\n",
         g_ctx.midi_log.size() - log_base);

  // --------------------------------------------------------------------------
  // Teste 3: Troca de Oitava e Sustenido com Tecla Pressionada
  // --------------------------------------------------------------------------
  printf("[3/12] Testando mudanca de oitava e sustenido com tecla segurada...\n");
  fpga->gpio_keys = 0x01U; // Segura Do4 (60)
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(60) > 0, "OIT_HOLD_C4", "Do4 nao iniciou");

  // Ativa chave sustenido com tecla segurada -> deve desligar 60 e ligar 61 (Do#4)
  fpga->btn_sustenido = 1;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(60) == 0 && CountSustainedVoices(61) > 0,
        "OIT_HOLD_CS4", "Ativar sustenido nao desligou nota 60 ou nao ligou 61");

  // Sobe oitava com tecla segurada -> deve desligar 61 e ligar 73 (Do#5)
  PressControlBtn(fpga->btn_oitava_up_n);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(61) == 0 && CountSustainedVoices(73) > 0,
        "OIT_HOLD_CS5", "Subir oitava nao desligou nota 61 ou nao ligou 73");

  // Desce oitava de volta para 4 e desliga sustenido -> volta para 60 (Do4)
  PressControlBtn(fpga->btn_oitava_down_n);
  WaitUartAndAudioIdle(2);
  fpga->btn_sustenido = 0;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(73) == 0 && CountSustainedVoices(60) > 0,
        "OIT_HOLD_BACK_C4", "Retorno para Do4 falhou");

  // Solta tecla
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices() == 0, "OIT_HOLD_RELEASE",
        "Voz ficou presa apos trocas de oitava/sustenido");
  printf("      OK: Transicoes 60 -> 61 -> 73 -> 61 -> 60 -> Off sem voz presa.\n");

  // --------------------------------------------------------------------------
  // Teste 4: Combo de Volume (5 niveis: 100/75/50/25/0% + HEX + PCM Quadratico + Mute Demo)
  // --------------------------------------------------------------------------
  printf("[4/12] Testando 5 niveis de volume, displays HEX, PCM quadratico e mute mid-note...\n");
  drain_tsf_voices();

  int32_t livre_peaks[5] = {0, 0, 0, 0, 0};
  double livre_rms[5] = {0.0, 0.0, 0.0, 0.0, 0.0};

  // Mede baseline 100% no Modo Livre (Re4 = 62, vel = 64 = kVelRef)
  fpga->gpio_keys = 0x02U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(g_ctx.last_midi_status == 0x90U && g_ctx.last_midi_data1 == 62U &&
            g_ctx.last_midi_data2 == 64U,
        "VOL_LIVRE_VEL_64", "Velocity inicial 100% nao foi 64");
  measure_pcm_over_blocks(8, livre_peaks[0], livre_rms[0]);
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  drain_tsf_voices();

  struct VolSpec
  {
    uint8_t state;
    uint8_t vel;
    uint8_t h5;
    uint8_t h4;
    uint8_t h3;
    uint8_t h2;
    const char *label;
  };
  static const VolSpec kVolSteps[5] = {
      {1U, 48U, 0x7FU, 0x78U, 0x12U, 0x0CU, " 75P"},
      {2U, 32U, 0x7FU, 0x12U, 0x40U, 0x0CU, " 50P"},
      {3U, 16U, 0x7FU, 0x24U, 0x12U, 0x0CU, " 25P"},
      {4U, 0U, 0x7FU, 0x7FU, 0x40U, 0x0CU, "  0P"},
      {0U, 64U, 0x79U, 0x40U, 0x40U, 0x0CU, "100P"},
  };

  int32_t peak_100_restored = 0;
  double rms_100_restored = 0.0;
  for (int i = 0; i < 5; ++i)
  {
    const VolSpec &vs = kVolSteps[i];
    fpga->btn_modo_n = 0;
    StepCycles(fpga->param_debounce_controle + 10U);
    PressControlBtn(fpga->btn_intensidade_n);
    check(fpga->debug_modo_ativo() == 0U, "VOL_COMBO_MODE_STAY",
          "Modo alterou indevidamente durante combo");
    check(fpga->debug_mostra_vol() == 1U && fpga->debug_volume() == vs.state,
          "VOL_COMBO_STATE", "Estado de volume nao avancou como esperado");
    check(fpga->hex5_modo == vs.h5 && fpga->hex4_oitava == vs.h4 &&
              fpga->hex3_musica_dezena == vs.h3 &&
              fpga->hex2_musica_unidade == vs.h2,
          "VOL_COMBO_HEX", "Displays HEX5..2 nao exibiram percentual esperado");
    fpga->btn_modo_n = 1;
    StepCycles(fpga->param_debounce_controle + 10U);
    check(fpga->debug_modo_ativo() == 0U, "VOL_COMBO_RELEASE_NO_MODE_CHANGE",
          "Soltar btn_modo apos combo trocou de modo indevidamente!");

    drain_tsf_voices();
    size_t midi_before = g_ctx.midi_log.size();
    fpga->gpio_keys = 0x02U;
    StepCycles(fpga->param_debounce_tecla + 10U);
    WaitUartAndAudioIdle(2);
    if (vs.state == 4U)
    {
      check(g_ctx.midi_log.size() == midi_before, "VOL_MUTE_NO_MIDI",
            "Volume 0% emitiu evento MIDI ao pressionar tecla");
      check(CountSustainedVoices() == 0, "VOL_MUTE_ZERO_VOICES",
            "Volume 0% ativou voz no TSF");
      measure_pcm_over_blocks(4, livre_peaks[4], livre_rms[4]);
      check(livre_peaks[4] == 0, "VOL_MUTE_ZERO_PCM",
            "Volume 0% produziu audio PCM nao nulo");
    }
    else
    {
      check(g_ctx.last_midi_status == 0x90U && g_ctx.last_midi_data1 == 62U &&
                g_ctx.last_midi_data2 == vs.vel,
            "VOL_COMBO_MIDI_VEL", "Velocity MIDI divergiu do nivel de volume");
      check(CountSustainedVoices(62) > 0, "VOL_COMBO_VOICE_ON",
            "Voz nao sustentou no nivel de volume ativo");
      if (vs.state == 0U)
      {
        measure_pcm_over_blocks(8, peak_100_restored, rms_100_restored);
      }
      else
      {
        measure_pcm_over_blocks(8, livre_peaks[vs.state], livre_rms[vs.state]);
      }
    }
    fpga->gpio_keys = 0x00U;
    StepCycles(fpga->param_debounce_tecla + 10U);
    WaitUartAndAudioIdle(2);
    drain_tsf_voices();
  }

  check(livre_peaks[0] > livre_peaks[1] && livre_peaks[1] > livre_peaks[2] &&
            livre_peaks[2] > livre_peaks[3] && livre_peaks[3] > 0,
        "VOL_LIVRE_PEAK_SCALING",
        "Picos PCM em Modo Livre nao decresceram monotonicamente (100>75>50>25>0)");
  check(livre_rms[0] > livre_rms[1] && livre_rms[1] > livre_rms[2] &&
            livre_rms[2] > livre_rms[3] && livre_rms[3] > 0.0,
        "VOL_LIVRE_RMS_SCALING",
        "RMS PCM em Modo Livre nao decresceu monotonicamente (100>75>50>25>0)");
  check(livre_rms[2] < 0.45 * livre_rms[0] && livre_rms[3] < 0.20 * livre_rms[0],
        "VOL_LIVRE_QUADRATIC_CURVE",
        "Atenuacao quadratica (50%/25% vs 100%) fora da faixa esperada");
  check(peak_100_restored > (livre_peaks[0] * 7) / 10, "VOL_LIVRE_100_RESTORED",
        "Retorno de 0% para 100% nao restaurou amplitude plena");

  // Avanca 1.0 s (125 * CiclosTick8ms) para verificar fim do timer mostra_vol
  StepCycles(125ULL * fpga->param_ciclos_tick_8ms + 20U);
  check(fpga->debug_mostra_vol() == 0U && fpga->hex5_modo == 0x40U &&
            fpga->hex4_oitava == 0x19U && fpga->hex3_musica_dezena == 0x7FU &&
            fpga->hex2_musica_unidade == 0x7FU,
        "VOL_COMBO_TIMER_EXPIRE",
        "Displays HEX5..2 nao retornaram ao normal apos 1s de mostra_vol");

  // Testa escala quadratica no Modo Demo (Musica 6: vel_rom=64, dur=40) e paridade com Modo Livre
  drain_tsf_voices();
  int32_t livre_c4_pk = 0;
  double livre_c4_rms = 0.0;
  fpga->gpio_keys = 0x01U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  measure_pcm_over_blocks(6, livre_c4_pk, livre_c4_rms);
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  drain_tsf_voices();

  select_song(6U);
  auto run_demo_first_note_pcm = [&](uint8_t exp_vel, int32_t &out_pk, double &out_rms) {
    set_mode(3U);
    drain_tsf_voices();
    fpga->gpio_keys = 0x01U;
    StepCycles(fpga->param_debounce_tecla + 10U);
    fpga->gpio_keys = 0x00U;
    StepCycles(fpga->param_debounce_tecla + 10U);
    WaitUartAndAudioIdle(2);
    check(g_ctx.last_midi_status == 0x90U && g_ctx.last_midi_data1 == 60U &&
              g_ctx.last_midi_data2 == exp_vel,
          "VOL_DEMO_VEL", "Velocity MIDI no Demo divergiu do nivel de volume");
    check(CountSustainedVoices(60) > 0, "VOL_DEMO_VOICE_ON",
          "Nota da Demo nao ativou no TSF");
    measure_pcm_over_blocks(6, out_pk, out_rms);
  };

  int32_t demo_pk_100 = 0, demo_pk_50 = 0, demo_pk_25 = 0;
  double demo_rms_100 = 0.0, demo_rms_50 = 0.0, demo_rms_25 = 0.0;
  run_demo_first_note_pcm(64U, demo_pk_100, demo_rms_100);
  check(livre_c4_rms > 0.0 &&
            fabs(demo_rms_100 - livre_c4_rms) <= 0.10 * livre_c4_rms,
        "VOL_LIVRE_DEMO_PARITY",
        "RMS PCM do Modo Demo divergiu do Modo Livre em 100%");
  set_mode(0U);
  WaitUartAndAudioIdle(2);
  drain_tsf_voices();

  trigger_vol_combo(); // 75%
  trigger_vol_combo(); // 50%
  run_demo_first_note_pcm(32U, demo_pk_50, demo_rms_50);
  set_mode(0U);
  WaitUartAndAudioIdle(2);
  drain_tsf_voices();

  trigger_vol_combo(); // 25%
  run_demo_first_note_pcm(16U, demo_pk_25, demo_rms_25);

  check(demo_pk_100 > demo_pk_50 && demo_pk_50 > demo_pk_25 && demo_pk_25 > 0,
        "VOL_DEMO_PEAK_SCALING",
        "Picos PCM no Demo nao decresceram (100>50>25)");
  check(demo_rms_100 > demo_rms_50 && demo_rms_50 > demo_rms_25 &&
            demo_rms_25 < 0.25 * demo_rms_100,
        "VOL_DEMO_QUADRATIC_SCALING",
        "RMS PCM no Demo nao seguiu escala quadratica esperada");

  // Com a nota C4 ainda em execucao no Modo Demo (dur=40 ticks), aplica mute (25% -> 0%)
  check(CountSustainedVoices(60) > 0, "VOL_DEMO_MUTE_PRE_ACTIVE",
        "Nota do Demo encerrou antes do mute mid-note");
  trigger_vol_combo(); // 25% -> 0%
  WaitUartAndAudioIdle(2);
  check(fpga->debug_modo_ativo() == 3U && fpga->debug_volume() == 4U,
        "VOL_DEMO_MUTE_STATE", "Combo para 0% no meio da Demo nao manteve Modo 3");
  check(g_ctx.last_midi_status == 0x80U && g_ctx.last_midi_data1 == 60U,
        "VOL_DEMO_MUTE_IMMEDIATE_OFF",
        "Mute (0%) no meio da nota Demo nao enviou Note Off imediato!");
  check(CountSustainedVoices() == 0, "VOL_DEMO_MUTE_ZERO_VOICES",
        "Voz permaneceu sustentada apos mute mid-note no Demo");

  // Restaura Modo 0, Musica 0 e Volume 100%
  set_mode(0U);
  trigger_vol_combo(); // 0% -> 100%
  select_song(0U);
  StepCycles(125ULL * fpga->param_ciclos_tick_8ms + 20U);
  WaitUartAndAudioIdle(2);
  drain_tsf_voices();
  printf("      OK: 5 niveis (peaks %d/%d/%d/%d/0), escala quadratica e mute mid-note validados.\n",
         livre_peaks[0], livre_peaks[1], livre_peaks[2], livre_peaks[3]);

  // --------------------------------------------------------------------------
  // Teste 5: Modo 1 (Aprendizado) — Trava Anti-Pipoco e Metronomo
  // --------------------------------------------------------------------------
  printf("[5/12] Testando Modo 1 (Aprendizado): trava anti-pipoco e avanco ROM...\n");
  // Seleciona musica 6 (Do_Re_Mi_Fa: C4=60, D4=62, E4=64, F4=65)
  for (int m = 0; m < 6; ++m)
  {
    PressControlBtn(fpga->btn_musica_n);
  }
  PressControlBtn(fpga->btn_modo_n); // Entra no Modo 1 (Aprendizado)
  StepCycles(10);
  check(fpga->debug_modo_ativo() == 1U, "APRE_ENTER", "Nao entrou no Modo 1");
  check(fpga->debug_sel_musica() == 6U, "APRE_SONG_6", "Musica 6 nao selecionada");
  check(fpga->hex5_modo == 0x79U && fpga->hex4_oitava == 0x19U &&
            fpga->hex3_musica_dezena == 0x7FU &&
            fpga->hex2_musica_unidade == 0x02U && fpga->hex1_nota == 0x46U,
        "APRE_HEX_DISPLAYS",
        "Displays HEX5..1 nao exibem Modo 1, Oitava 4, Musica ' 6' e Nota 'C'");

  // Pressiona tecla errada (Sol = tecla 4) -> endereco deve permanecer em 0
  fpga->gpio_keys = 0x10U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(fpga->debug_endereco_ram() == 0U, "APRE_WRONG_KEY_NO_ADV",
        "Nota errada avancou endereco da partitura no Modo 1");
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);

  // Pressiona tecla certa (Do = tecla 0) -> acerta e permanece em kEsperaSoltar
  fpga->gpio_keys = 0x01U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(60) > 0, "APRE_RIGHT_KEY_C4",
        "Nota correta C4 nao tocou no Modo 1");

  // Verifica trava anti-pipoco (r_oitava_apre_reg / r_sustenido_apre_reg):
  // Com a tecla ainda segurada no Modo 1, acionar btn_sustenido e btn_oitava_up
  // NAO pode alterar oitava_atual/sustenido_atual nem causar re-ataque MIDI!
  size_t midi_count_while_held = g_ctx.midi_log.size();
  fpga->btn_sustenido = 1;
  StepCycles(fpga->param_debounce_tecla + 10U);
  PressControlBtn(fpga->btn_oitava_up_n);
  WaitUartAndAudioIdle(2);
  check(fpga->debug_oitava_atual() == 4U && fpga->debug_sustenido_atual() == 0U,
        "APRE_ANTIPOP_LATCH_LOCKED",
        "Oitava ou sustenido em uso mudou com tecla pressionada no Modo 1");
  check(g_ctx.midi_log.size() == midi_count_while_held &&
            CountSustainedVoices(60) > 0,
        "APRE_ANTIPOP_NO_REATTACK",
        "Pipoco MIDI (re-ataque espurio) gerado com tecla mantida no Modo 1");

  // Ao soltar a tecla fisica, avanca para addr 1 (Re4 = 62) e acende led_oitava_down
  // pois oitava_livre subiu para 5 enquanto a nota esperada da ROM pede oitava 4
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(fpga->debug_endereco_ram() == 1U, "APRE_ADVANCE_ADDR_1",
        "Endereco da partitura nao avancou para 1 apos soltar nota correta");
  check(fpga->hex1_nota == 0x21U, "APRE_HEX1_D",
        "HEX1 nao exibe proxima nota d (0x21)");
  check(fpga->led_oitava_down == 1U && fpga->led_oitava_up == 0U,
        "APRE_LED_OITAVA_DOWN",
        "led_oitava_down nao acendeu quando oitava_livre (5) > oitava_esperada (4)");
  // Restaura oitava_livre para 4 e sustenido para 0
  PressControlBtn(fpga->btn_oitava_down_n);
  fpga->btn_sustenido = 0;
  StepCycles(fpga->param_debounce_tecla + 10U);
  check(fpga->led_oitava_down == 0U, "APRE_LED_OITAVA_MATCH",
        "led_oitava_down nao apagou ao igualar oitava 4");
  check(CountSustainedVoices() == 0, "APRE_RELEASE_CLEAN",
        "Voz ficou presa no Modo 1");
  printf("      OK: Modo Aprendizado e trava anti-pipoco validados com 0 re-ataques.\n");

  // --------------------------------------------------------------------------
  // Teste 6: Modo 2 (Gravacao RAM): Precisao Temporal (Duracao+Pausa), Playback e M10K
  // --------------------------------------------------------------------------
  printf("[6/12] Testando Modo 2 (Gravacao RAM): duracao, pausa pos-nota, playback e M10K...\n");
  const uint32_t db_key = fpga->param_debounce_tecla;
  const uint32_t tick_8ms = fpga->param_ciclos_tick_8ms;

  auto decode_ram_word = [](uint32_t word, uint8_t &nota, uint8_t &vel,
                            uint8_t &dur, uint8_t &pausa) {
    nota = static_cast<uint8_t>(word & 0x7FU);
    vel = static_cast<uint8_t>((word >> 7) & 0x7FU);
    dur = static_cast<uint8_t>((word >> 14) & 0xFFU);
    pausa = static_cast<uint8_t>((word >> 22) & 0xFFU);
  };

  set_mode(2U); // Modo 1 -> Modo 2 (Gravacao)
  check(fpga->debug_modo_ativo() == 2U, "GRAV_ENTER", "Nao entrou no Modo 2");
  check(fpga->debug_sel_musica() == 42U, "GRAV_SEL_42",
        "Modo 2 nao selecionou slot 42");

  // Espera 8 ticks ANTES da 1a nota: NAO deve ser gravado como pausa
  StepCycles(8ULL * tick_8ms);

  // Grava 3 notas com duracoes (4, 8, 3) e pausas inter-notas (5, 2) distintas
  // Nota 0: C4 (60), dur=4, pausa=5
  fpga->gpio_keys = 0x01U;
  StepCycles(3ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x00U;
  StepCycles(5ULL * tick_8ms + tick_8ms / 2U);

  // Nota 1: E4 (64), dur=8, pausa=2
  fpga->gpio_keys = 0x04U;
  StepCycles(7ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x00U;
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);

  // Nota 2: G4 (67), dur=3; depois espera 10 ticks antes de sair do Modo 2
  fpga->gpio_keys = 0x10U;
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x00U;
  StepCycles(10ULL * tick_8ms + db_key + 20U);
  WaitUartAndAudioIdle(2);

  check(fpga->debug_endereco_ram() == 3U && fpga->debug_grav_tem_dados() == 1U &&
            fpga->debug_ultimo_end_gravado() == 2U,
        "GRAV_THREE_NOTES_ADDR",
        "Endereco ou ultimo_end_gravado incorreto apos gravar 3 notas");

  {
    uint8_t n0, v0, d0, p0, n1, v1, d1, p1, n2, v2, d2, p2;
    decode_ram_word(fpga->debug_read_ram(0U), n0, v0, d0, p0);
    decode_ram_word(fpga->debug_read_ram(1U), n1, v1, d1, p1);
    decode_ram_word(fpga->debug_read_ram(2U), n2, v2, d2, p2);
    check(n0 == 60U && v0 == 64U && d0 == 4U && p0 == 5U, "GRAV_WORD0_TIMING",
          "Palavra 0 RAM divergiu (esperado C4, vel=64, dur=4, pausa=5)");
    check(n1 == 64U && v1 == 64U && d1 == 8U && p1 == 2U, "GRAV_WORD1_TIMING",
          "Palavra 1 RAM divergiu (esperado E4, vel=64, dur=8, pausa=2)");
    check(n2 == 67U && v2 == 64U && d2 == 3U && p2 == 0U, "GRAV_WORD2_TIMING",
          "Palavra 2 RAM divergiu (esperado G4, vel=64, dur=3, pausa=0)");
  }

  // Reproduz no Modo 3 (Demo slot 42) e mede duracoes e pausas reais em ciclos MIDI
  set_mode(3U);
  select_song(42U);
  WaitUartAndAudioIdle(2);
  size_t log_before_timing_demo = g_ctx.midi_log.size();
  fpga->gpio_keys = 0x01U;
  StepCycles(db_key + 10U);
  fpga->gpio_keys = 0x00U;
  StepCycles(27ULL * tick_8ms);
  WaitUartAndAudioIdle(3);

  {
    size_t count = g_ctx.midi_log.size() - log_before_timing_demo;
    check(count == 6U, "DEMO_TIMING_EVENT_COUNT",
          "Playback de 3 notas deveria gerar exatamente 6 eventos MIDI");
    if (count >= 6U)
    {
      const MidiLogEntry *ev = &g_ctx.midi_log[log_before_timing_demo];
      check(ev[0].status == 0x90U && ev[0].data1 == 60U &&
                ev[1].status == 0x80U && ev[1].data1 == 60U &&
                ev[2].status == 0x90U && ev[2].data1 == 64U &&
                ev[3].status == 0x80U && ev[3].data1 == 64U &&
                ev[4].status == 0x90U && ev[4].data1 == 67U &&
                ev[5].status == 0x80U && ev[5].data1 == 67U,
            "DEMO_TIMING_NOTE_SEQ",
            "Sequencia MIDI no playback da gravacao temporizada incorreta");
      double dur0_t = static_cast<double>(ev[1].cycle - ev[0].cycle) / tick_8ms;
      double gap0_t = static_cast<double>(ev[2].cycle - ev[1].cycle) / tick_8ms;
      double dur1_t = static_cast<double>(ev[3].cycle - ev[2].cycle) / tick_8ms;
      double gap1_t = static_cast<double>(ev[4].cycle - ev[3].cycle) / tick_8ms;
      double dur2_t = static_cast<double>(ev[5].cycle - ev[4].cycle) / tick_8ms;
      check(dur0_t >= 3.4 && dur0_t <= 4.6 && gap0_t >= 4.4 && gap0_t <= 5.6 &&
                dur1_t >= 7.4 && dur1_t <= 8.6 && gap1_t >= 1.4 && gap1_t <= 2.6 &&
                dur2_t >= 2.4 && dur2_t <= 3.6,
            "DEMO_TIMING_REAL_MEASURED",
            "Duracoes ou pausas medidas no playback Demo diferem do gravado");
    }
  }
  check(CountSustainedVoices() == 0, "DEMO_RAM_CLEAN_END",
        "Voz ficou presa apos playback da gravacao temporizada");

  // Testa tambem escrita na fronteira superior da RAM M10K (addr 1022 -> 1023) e trava em 1023
  set_mode(2U);
  fpga->debug_set_endereco_ram(1022U);
  fpga->gpio_keys = 0x10U; // Sol4 (67) no endereco 1022
  StepCycles(2ULL * tick_8ms);
  fpga->gpio_keys = 0x00U;
  StepCycles(db_key + 20U);
  WaitUartAndAudioIdle(2);
  check(fpga->debug_endereco_ram() == 1023U, "GRAV_UPPER_BOUND_1023",
        "Endereco RAM nao avancou para o limite superior 1023");
  check((fpga->debug_read_ram(1022U) & 0x7FU) == 67U, "GRAV_RAM_WORD_1022",
        "Palavra na posicao 1022 da RAM M10K nao armazenou Sol4 (67)");

  // Com endereco ja em 1023 (capacidade maxima), pressionar A4 (0x20) nao deve sobrescrever nem dar wrap-around
  fpga->gpio_keys = 0x20U;
  StepCycles(2ULL * tick_8ms);
  fpga->gpio_keys = 0x00U;
  StepCycles(db_key + 20U);
  WaitUartAndAudioIdle(2);
  check(fpga->debug_endereco_ram() == 1023U, "GRAV_CAP_1023_ADDR",
        "Endereco RAM saiu de 1023 ao tentar gravar com RAM cheia");
  check(fpga->debug_ultimo_end_gravado() == 1022U, "GRAV_CAP_1023_LAST_WRITTEN",
        "ultimo_end_gravado alterou indevidamente com RAM cheia em 1023");
  check((fpga->debug_read_ram(0U) & 0x7FU) == 60U, "GRAV_CAP_1023_NO_WRAP_OVERWRITE",
        "Endereco 0 foi sobrescrito indevidamente por wrap-around em 1023");

  // Verifica que playback Demo partindo de 1022 reproduz Sol4 (67) e encerra ao atingir 1023
  set_mode(3U);
  select_song(42U);
  WaitUartAndAudioIdle(2);
  {
    size_t log_before_cap_demo = g_ctx.midi_log.size();
    fpga->gpio_keys = 0x01U;
    for (uint32_t c = 0; c < db_key + 20U && fpga->debug_fsm_state() != 13U; ++c)
    {
      StepCycles(1);
    }
    check(fpga->debug_fsm_state() == 13U, "DEMO_CAP_1022_START",
          "Demo nao iniciou estado kDemoTocaNota");
    fpga->debug_set_endereco_ram(1022U);
    fpga->gpio_keys = 0x00U;
    StepCycles(db_key + 8ULL * tick_8ms);
    WaitUartAndAudioIdle(2);
    size_t cap_cnt = g_ctx.midi_log.size() - log_before_cap_demo;
    check(cap_cnt == 2U &&
              g_ctx.midi_log[log_before_cap_demo].status == 0x90U &&
              g_ctx.midi_log[log_before_cap_demo].data1 == 67U &&
              g_ctx.midi_log[log_before_cap_demo + 1U].status == 0x80U &&
              g_ctx.midi_log[log_before_cap_demo + 1U].data1 == 67U,
          "DEMO_CAP_1022_PLAY_SOL4",
          "Playback Demo a partir de 1022 nao reproduziu apenas Sol4 (67)");
    check(fpga->debug_fsm_state() == 15U && fpga->debug_endereco_ram() == 0U &&
              CountSustainedVoices() == 0,
          "DEMO_CAP_1022_CLEAN_STOP",
          "Playback Demo partindo de 1022 nao encerrou limpo em kIniciaDemo");
  }
  printf("      OK: Gravacao (dur=4/8/3, pausa=5/2), playback medido, trava 1023 e Demo 1022 OK.\n");

  // --------------------------------------------------------------------------
  // Teste 7: Polifonia / Legato Overlap na Gravacao (Modo 2) e Demo (Modo 3)
  // --------------------------------------------------------------------------
  printf("[7/12] Testando Polifonia / Legato Overlap na gravacao (C4->E4->G4->E4->C4)...\n");
  set_mode(0U);
  set_mode(2U); // Reinicia endereco de gravacao para 0
  // C4 (3 ticks) -> +E4 (3 ticks) -> +G4 (3 ticks) -> solta G4 (fallback E4, 3 ticks)
  // -> solta E4 (fallback C4, 3 ticks) -> solta C4
  fpga->gpio_keys = 0x01U;
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x05U;
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x15U;
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x05U;
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x01U;
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x00U;
  StepCycles(db_key + 20U);
  WaitUartAndAudioIdle(2);

  check(fpga->debug_ultimo_end_gravado() == 4U && fpga->debug_endereco_ram() == 5U,
        "GRAV_LEGATO_COUNT_5",
        "Sobreposicao legato de 5 eventos nao gravou 5 posicoes na RAM");
  {
    static const uint8_t kExpLegato[5] = {60U, 64U, 67U, 64U, 60U};
    for (int idx = 0; idx < 5; ++idx)
    {
      uint8_t n, v, d, p;
      decode_ram_word(fpga->debug_read_ram(static_cast<uint16_t>(idx)), n, v, d, p);
      check(n == kExpLegato[idx] && v == 64U && d == 3U && p == 0U,
            "GRAV_LEGATO_RAM_WORD",
            "Nota legato gravada na RAM divergiu de (nota, vel=64, dur=3, pausa=0)");
    }
  }

  // Reproduz no Modo 3 e confirma todas as 5 notas sequenciais sem sobreposicao
  set_mode(3U);
  select_song(42U);
  WaitUartAndAudioIdle(2);
  size_t log_before_legato = g_ctx.midi_log.size();
  uint32_t overlaps_before_legato = g_ctx.overlap_violations;
  fpga->gpio_keys = 0x01U;
  StepCycles(db_key + 10U);
  fpga->gpio_keys = 0x00U;
  StepCycles(20ULL * tick_8ms);
  WaitUartAndAudioIdle(3);

  {
    static const uint8_t kExpLegato[5] = {60U, 64U, 67U, 64U, 60U};
    size_t count = g_ctx.midi_log.size() - log_before_legato;
    check(count == 10U, "DEMO_LEGATO_EVENT_COUNT",
          "Playback legato deveria gerar 10 eventos MIDI (5 On + 5 Off)");
    if (count >= 10U)
    {
      for (int idx = 0; idx < 5; ++idx)
      {
        const MidiLogEntry &e_on = g_ctx.midi_log[log_before_legato + idx * 2];
        const MidiLogEntry &e_off = g_ctx.midi_log[log_before_legato + idx * 2 + 1];
        check(e_on.status == 0x90U && e_on.data1 == kExpLegato[idx] &&
                  e_off.status == 0x80U && e_off.data1 == kExpLegato[idx],
              "DEMO_LEGATO_PLAYBACK_SEQ",
              "Sequencia MIDI no playback legato divergiu de C4->E4->G4->E4->C4");
      }
    }
  }
  check(g_ctx.overlap_violations == overlaps_before_legato &&
            CountSustainedVoices() == 0,
        "DEMO_LEGATO_NO_OVERLAP",
        "Playback legato gerou violacao de sobreposicao ou deixou voz presa");
  printf("      OK: 5 notas legato (60,64,67,64,60) gravadas e reproduzidas sem overlap.\n");

  // --------------------------------------------------------------------------
  // Teste 8: Persistencia da RAM M10K entre Modos, Aprendizado e Sobrescrita
  // --------------------------------------------------------------------------
  printf("[8/12] Testando persistencia da RAM entre modos (1->2->3->0->1) e sobrescrita...\n");
  set_mode(2U);
  fpga->gpio_keys = 0x01U; // C4 (60)
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x00U;
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x04U; // E4 (64)
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x00U;
  StepCycles(db_key + 20U);
  WaitUartAndAudioIdle(2);
  check(fpga->debug_grav_tem_dados() == 1U && fpga->debug_ultimo_end_gravado() == 1U,
        "PERSIST_RECORDED_2", "Gravacao de 2 notas nao atualizou ultimo_end_gravado=1");

  // Toca a musica gravada no Modo 1 (Aprendizado) ate o fim e auto-reinicio
  set_mode(1U);
  select_song(42U);
  auto play_2note_ram_in_modo1 = [&](const char *tag) {
    uint32_t sc_before = fpga->debug_score_count();
    check(fpga->debug_endereco_ram() == 0U && fpga->hex1_nota == 0x46U, tag,
          "Modo 1 nao iniciou na nota 0 (C4)");
    fpga->gpio_keys = 0x01U;
    StepCycles(db_key + 20U);
    fpga->gpio_keys = 0x00U;
    StepCycles(db_key + 20U);
    check(fpga->debug_endereco_ram() == 1U && fpga->hex1_nota == 0x06U, tag,
          "Modo 1 nao avancou para nota 1 (E4)");
    fpga->gpio_keys = 0x04U;
    StepCycles(db_key + 20U);
    fpga->gpio_keys = 0x00U;
    StepCycles(db_key + 30U);
    WaitUartAndAudioIdle(2);
    check(fpga->debug_endereco_ram() == 0U && fpga->hex1_nota == 0x46U &&
              fpga->debug_score_count() == sc_before + 1U,
          tag, "Modo 1 nao reiniciou automaticamente para addr 0 apos fim da RAM");
  };
  play_2note_ram_in_modo1("PERSIST_MODO1_PASS1");

  // Cicla por TODOS os modos (1 -> 2 -> 3 -> 0 -> 1) SEM pressionar teclas no Modo 2
  PressControlBtn(fpga->btn_modo_n); // 1 -> 2
  check(fpga->debug_modo_ativo() == 2U && fpga->debug_grav_tem_dados() == 1U &&
            fpga->debug_ultimo_end_gravado() == 1U,
        "PERSIST_ENTER_MODO2_NO_WIPE",
        "Entrar no Modo 2 sem pressionar teclas apagou dados gravados!");
  PressControlBtn(fpga->btn_modo_n); // 2 -> 3
  PressControlBtn(fpga->btn_modo_n); // 3 -> 0
  PressControlBtn(fpga->btn_modo_n); // 0 -> 1
  check(fpga->debug_modo_ativo() == 1U && fpga->debug_grav_tem_dados() == 1U &&
            fpga->debug_ultimo_end_gravado() == 1U,
        "PERSIST_FULL_CYCLE_INTACT",
        "Dados da RAM nao persistiram apos ciclo completo 1->2->3->0->1");

  // Confirma que Modo 1 e Modo 3 continuam reproduzindo a gravacao de 2 notas intacta
  play_2note_ram_in_modo1("PERSIST_MODO1_PASS2");

  set_mode(3U);
  check(fpga->debug_sel_musica() == 42U, "PERSIST_MODO3_SEL42",
        "Slot 42 nao permaneceu selecionado");
  WaitUartAndAudioIdle(2);
  size_t log_persist_demo = g_ctx.midi_log.size();
  fpga->gpio_keys = 0x01U;
  StepCycles(db_key + 10U);
  fpga->gpio_keys = 0x00U;
  StepCycles(14ULL * tick_8ms);
  WaitUartAndAudioIdle(2);
  check((g_ctx.midi_log.size() - log_persist_demo) == 4U &&
            g_ctx.midi_log[log_persist_demo].data1 == 60U &&
            g_ctx.midi_log[log_persist_demo + 2].data1 == 64U,
        "PERSIST_MODO3_INTACT",
        "Demo slot 42 nao reproduziu as 2 notas intactas apos passar pelo Modo 2");

  // Agora entra no Modo 2 e grava 1 nota (A4 = 69) para validar sobrescrita intencional
  set_mode(2U);
  fpga->gpio_keys = 0x20U; // A4 (69)
  StepCycles(2ULL * tick_8ms + tick_8ms / 2U);
  fpga->gpio_keys = 0x00U;
  StepCycles(db_key + 20U);
  WaitUartAndAudioIdle(2);
  check(fpga->debug_grav_tem_dados() == 1U && fpga->debug_ultimo_end_gravado() == 0U &&
            (fpga->debug_read_ram(0U) & 0x7FU) == 69U,
        "PERSIST_INTENTIONAL_OVERWRITE",
        "Gravar nova nota no Modo 2 nao sobrescreveu ultimo_end_gravado=0 com A4(69)");
  set_mode(3U);
  WaitUartAndAudioIdle(2);
  size_t log_overwrite_demo = g_ctx.midi_log.size();
  fpga->gpio_keys = 0x01U;
  StepCycles(db_key + 10U);
  fpga->gpio_keys = 0x00U;
  StepCycles(8ULL * tick_8ms);
  WaitUartAndAudioIdle(2);
  check((g_ctx.midi_log.size() - log_overwrite_demo) == 2U &&
            g_ctx.midi_log[log_overwrite_demo].status == 0x90U &&
            g_ctx.midi_log[log_overwrite_demo].data1 == 69U,
        "PERSIST_OVERWRITE_PLAYBACK",
        "Playback apos sobrescrita nao tocou estritamente 1 nota A4(69)");
  printf("      OK: Persistencia intacta atraves de 1->2->3->0->1 e sobrescrita A4(69) OK.\n");

  // --------------------------------------------------------------------------
  // Teste 9: Modo 1 (Aprendizado) — Pontuacao de Ritmo + Auto-Reinicio
  // --------------------------------------------------------------------------
  printf("[9/12] Testando avaliacao de ritmo no Modo 1 (taps 53%% vs exato 100%%) e auto-reinicio...\n");
  set_mode(1U);
  select_song(6U); // Do_Re_Mi_Fa (7 notas: dur=40, pausa=5)
  check(fpga->debug_endereco_ram() == 0U && fpga->debug_acertos() == 0U &&
            fpga->debug_erros() == 0U && fpga->debug_pontos_apre() == 0U,
        "RHYTHM_INIT_CLEAN",
        "Contadores do Modo 1 nao iniciaram zerados na musica 6");

  // Passada 1: taps curtos (1-2 ticks) com gap 0 ticks entre notas
  uint32_t scores_before_p1 = fpga->debug_score_count();
  for (int k = 0; k < 7; ++k)
  {
    fpga->gpio_keys = static_cast<uint8_t>(1U << k);
    StepCycles(db_key + 20U);
    fpga->gpio_keys = 0x00U;
    StepCycles((k < 6) ? 10U : (db_key + 30U));
  }
  WaitUartAndAudioIdle(2);
  check(fpga->debug_score_count() == scores_before_p1 + 1U, "RHYTHM_P1_SCORE_LATCHED",
        "Score da Passada 1 nao foi disparado ao fim da musica");
  check(fpga->debug_last_score() == 53U, "RHYTHM_P1_LOW_SCORE",
        "Taps curtos e sem pausa deveriam resultar em score 53% (0 erros)");
  check(fpga->debug_endereco_ram() == 0U && fpga->debug_acertos() == 0U &&
            fpga->debug_erros() == 0U && fpga->debug_pontos_apre() == 0U &&
            fpga->hex1_nota == 0x46U,
        "RHYTHM_P1_AUTORESTART",
        "Modo 1 nao reiniciou endereco e contadores apos Passada 1");

  // Passada 2 (imediata apos auto-reinicio): segura 40 ticks e pausa 5 ticks
  uint32_t scores_before_p2 = fpga->debug_score_count();
  for (int k = 0; k < 7; ++k)
  {
    fpga->gpio_keys = static_cast<uint8_t>(1U << k);
    StepCycles(39ULL * tick_8ms + tick_8ms / 2U);
    fpga->gpio_keys = 0x00U;
    StepCycles((k < 6) ? (5ULL * tick_8ms + tick_8ms / 2U) : (db_key + 30U));
  }
  WaitUartAndAudioIdle(2);
  check(fpga->debug_score_count() == scores_before_p2 + 1U, "RHYTHM_P2_SCORE_LATCHED",
        "Score da Passada 2 nao foi disparado ao fim da musica");
  check(fpga->debug_last_score() == 100U, "RHYTHM_P2_100_SCORE",
        "Execucao no ritmo exato (dur=40, pausa=5) deveria resultar em 100%");
  check(fpga->debug_endereco_ram() == 0U && fpga->debug_acertos() == 0U &&
            fpga->debug_erros() == 0U && fpga->debug_pontos_apre() == 0U,
        "RHYTHM_P2_AUTORESTART",
        "Modo 1 nao reiniciou endereco e contadores apos Passada 2");
  printf("      OK: Passada 1 = 53%%, Passada 2 = 100%%, auto-reinicio e contadores OK.\n");

  // --------------------------------------------------------------------------
  // Teste 10: Interrupcao Abrupta no Meio de Nota Ativa (Modo 3 Demo e Modo 1 Aprendizado)
  // --------------------------------------------------------------------------
  printf("[10/12] Testando interrupcao abrupta com nota ativa (Demo e Aprendizado)...\n");
  set_mode(3U);
  select_song(4U); // Clair de Lune (primeira nota = 67 com duracao longa)
  check(fpga->debug_sel_musica() == 4U, "DEMO_SONG_4", "Musica 4 nao selecionada");

  // Inicia Demo (Clair de Lune)
  fpga->gpio_keys = 0x01U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 2U * fpga->param_ciclos_tick_8ms);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(67) > 0, "DEMO_INTERRUPT_NOTE_ACTIVE",
        "Nota 67 de Clair de Lune nao estava ativa antes da interrupcao");

  // Interrompe trocando de musica no meio da nota ativa!
  PressControlBtn(fpga->btn_musica_n);
  WaitUartAndAudioIdle(3);
  check(CountSustainedVoices() == 0, "DEMO_INTERRUPT_BY_MUSIC_BTN",
        "Trocar de musica com nota ativa na Demo deixou voz presa no ESP32!");

  // Inicia novamente na musica 6 (Do_Re_Mi_Fa) e interrompe trocando de MODO!
  select_song(6U);
  fpga->gpio_keys = 0x01U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 2U * fpga->param_ciclos_tick_8ms);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices() > 0, "DEMO_INTERRUPT2_NOTE_ACTIVE",
        "Nota da Demo nao estava ativa antes da troca de modo");

  // Troca de Modo 3 -> Modo 0 (Livre) no meio da nota ativa
  PressControlBtn(fpga->btn_modo_n);
  WaitUartAndAudioIdle(3);
  check(fpga->debug_modo_ativo() == 0U, "DEMO_INTERRUPT_TO_LIVRE",
        "Nao retornou ao Modo 0 (Livre)");
  check(CountSustainedVoices() == 0, "DEMO_INTERRUPT_BY_MODE_BTN",
        "Trocar de modo com nota ativa na Demo deixou voz presa no ESP32!");

  // Agora testa interrupcao no Modo 1 (Aprendizado) com tecla pressionada:
  // Entra no Modo 1 (musica 6), acerta e segura Do4 (60), depois interrompe trocando de modo!
  PressControlBtn(fpga->btn_modo_n); // Modo 0 -> Modo 1 (Aprendizado)
  fpga->gpio_keys = 0x01U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  check(CountSustainedVoices(60) > 0, "APRE_INTERRUPT_NOTE_ACTIVE",
        "Nota 60 nao estava ativa no Modo 1 antes da interrupcao");
  PressControlBtn(fpga->btn_modo_n); // Modo 1 -> Modo 2
  fpga->gpio_keys = 0x00U;
  StepCycles(fpga->param_debounce_tecla + 10U);
  WaitUartAndAudioIdle(2);
  PressControlBtn(fpga->btn_modo_n); // Modo 2 -> Modo 3
  PressControlBtn(fpga->btn_modo_n); // Modo 3 -> Modo 0
  select_song(0U);
  WaitUartAndAudioIdle(2);
  check(fpga->debug_modo_ativo() == 0U && CountSustainedVoices() == 0,
        "APRE_INTERRUPT_CLEAN",
        "Interrupcao de nota ativa no Modo 1 deixou voz presa no ESP32!");
  printf("      OK: Interrupcoes na Demo (Modo 3) e Aprendizado (Modo 1) limpas.\n");

  // --------------------------------------------------------------------------
  // Teste 11: Robustez UART MIDI e Estresse de Polifonia (Voice Stealing >7 Vozes Mono)
  // --------------------------------------------------------------------------
  printf("[11/12] Testando ressincronismo UART MIDI e voice-stealing (>%d vozes mono TSF)...\n",
         kMaxPolyphonyVoices);
  // Injeta bytes orfaos sem status (quando status_byte ja existe) e frame truncado
  Serial1.pushRxByte(0x90U); // Status Note On
  Serial1.pushRxByte(0x3CU); // Data 1 parcial (sem velocity!)
  // Agora chega um novo Status Note On real com byte System Real-Time (0xFE) intercalado
  Serial1.pushRxByte(0x90U);
  Serial1.pushRxByte(69U);   // La4 (440 Hz)
  Serial1.pushRxByte(0xFEU); // Active Sensing (deve ser ignorado sem corromper o frame)
  Serial1.pushRxByte(100U);  // Velocity 100
  loop();
  sim_step_audio_block();
  check(CountSustainedVoices(69) > 0 && CountSustainedVoices(60) == 0,
        "UART_RESYNC_NOTE_ON",
        "Parser MIDI nao descartou frame truncado ou falhou com byte 0xFE");

  // Desliga La4 via Note On com velocity 0 (padrao MIDI 1.0 running status / 0x90 vel 0)
  Serial1.pushRxByte(0x90U);
  Serial1.pushRxByte(69U);
  Serial1.pushRxByte(0U);
  loop();
  sim_step_audio_block();
  check(CountSustainedVoices() == 0, "UART_RESYNC_NOTE_OFF_VEL0",
        "Note On com velocity 0 nao desligou a voz de La4 (69)");

  // Estresse de polifonia: toca rapidamente 9 notas distintas pela FPGA (> limite de 7 vozes mono)
  // para forcar o algoritmo de voice-stealing do TinySoundFont (kMaxPolyphonyVoices = 7)
  g_ctx.max_active_voices_seen = 0;
  static const uint8_t kTrillKeys[7] = {0x01U, 0x02U, 0x04U, 0x08U,
                                        0x10U, 0x20U, 0x40U};
  for (int k = 0; k < 7; ++k)
  {
    fpga->gpio_keys = kTrillKeys[k];
    StepCycles(fpga->param_debounce_tecla + 10U);
    WaitUartAndAudioIdle(1);
    fpga->gpio_keys = 0x00U;
    StepCycles(fpga->param_debounce_tecla + 10U);
    WaitUartAndAudioIdle(1);
  }
  fpga->btn_sustenido = 1;
  StepCycles(fpga->param_debounce_tecla + 10U);
  for (int k = 0; k < 2; ++k)
  {
    fpga->gpio_keys = kTrillKeys[k];
    StepCycles(fpga->param_debounce_tecla + 10U);
    WaitUartAndAudioIdle(1);
    fpga->gpio_keys = 0x00U;
    StepCycles(fpga->param_debounce_tecla + 10U);
    WaitUartAndAudioIdle(1);
  }
  fpga->btn_sustenido = 0;
  StepCycles(fpga->param_debounce_tecla + 10U);

  check(g_ctx.max_active_voices_seen == kMaxPolyphonyVoices,
        "TSF_POLYPHONY_VOICE_STEALING",
        "Estresse de polifonia nao atingiu ou excedeu o teto de 7 vozes mono do TSF");
  check(CountSustainedVoices() == 0, "TSF_POLYPHONY_RELEASED",
        "Voz ficou sustentada apos rajada de voice-stealing");
  printf("      OK: Ressincronismo UART e voice-stealing (%d/%d vozes) validados.\n",
         g_ctx.max_active_voices_seen, kMaxPolyphonyVoices);

  // --------------------------------------------------------------------------
  // Teste de Afinacao: nota tocada (medida no PCM) vs nota MIDI esperada
  // Valida notas naturais, sustenidos e mudancas de oitava via FPGA
  // --------------------------------------------------------------------------
  printf("[PITCH] Medindo a frequencia/nota real tocada no PCM para todas as teclas...\n");
  {
    fpga->gpio_keys = 0x00U;
    fpga->btn_sustenido = 0;
    StepCycles(fpga->param_debounce_tecla + 10U);
    WaitUartAndAudioIdle(4);
    for (int i = 0; i < 200; ++i)
    {
      sim_step_audio_block();
    }

    auto test_note_pitch = [&](uint8_t keys_mask, int expected_midi, const char *label) {
      fpga->gpio_keys = keys_mask;
      StepCycles(fpga->param_debounce_tecla + 10U);
      WaitUartAndAudioIdle(40);
      double f = MeasureTailFrequencyHz(8192);
      double midi_f = (f > 0.0) ? 69.0 + 12.0 * log2(f / 440.0) : -1.0;
      double expected_f = 440.0 * pow(2.0, (expected_midi - 69) / 12.0);
      printf("      %-7s esperado MIDI %2d (%.1f Hz) | medido %.1f Hz (nota %.2f)\n",
             label, expected_midi, expected_f, f, midi_f);
      check(f > 0.0 && fabs(midi_f - expected_midi) < 0.5, "PITCH_NOTE", label);
      fpga->gpio_keys = 0x00U;
      StepCycles(fpga->param_debounce_tecla + 10U);
      WaitUartAndAudioIdle(4);
      for (int i = 0; i < 180; ++i)
      {
        sim_step_audio_block();
      }
    };

    // 1. Oitava 4 (Natural)
    static const char *kNatNames[7] = {"Do4", "Re4", "Mi4", "Fa4", "Sol4", "La4", "Si4"};
    static const int kNatMidi[7] = {60, 62, 64, 65, 67, 69, 71};
    printf("    --- 1. Oitava 4 (Notas Naturais) ---\n");
    for (int k = 0; k < 7; ++k)
    {
      test_note_pitch(static_cast<uint8_t>(1U << k), kNatMidi[k], kNatNames[k]);
    }

    // 2. Oitava 4 com Sustenido (#)
    static const char *kSharpNames[7] = {"Do#4", "Re#4", "Mi#4", "Fa#4", "Sol#4", "La#4", "Si#4"};
    static const int kSharpMidi[7] = {61, 63, 65, 66, 68, 70, 72};
    printf("    --- 2. Oitava 4 com Sustenido (#) ---\n");
    fpga->btn_sustenido = 1;
    StepCycles(fpga->param_debounce_tecla + 10U);
    for (int k = 0; k < 7; ++k)
    {
      test_note_pitch(static_cast<uint8_t>(1U << k), kSharpMidi[k], kSharpNames[k]);
    }
    fpga->btn_sustenido = 0;
    StepCycles(fpga->param_debounce_tecla + 10U);

    // 3. Oitava 5 (Oitava Acima)
    printf("    --- 3. Oitava 5 (Oitava Acima) ---\n");
    PressControlBtn(fpga->btn_oitava_up_n);
    test_note_pitch(0x01U, 72, "Do5");
    test_note_pitch(0x04U, 76, "Mi5");
    test_note_pitch(0x20U, 81, "La5");

    // 4. Oitava 3 (Oitava Abaixo)
    printf("    --- 4. Oitava 3 (Oitava Abaixo) ---\n");
    PressControlBtn(fpga->btn_oitava_down_n); // Volta para Oitava 4
    PressControlBtn(fpga->btn_oitava_down_n); // Vai para Oitava 3
    test_note_pitch(0x01U, 48, "Do3");
    test_note_pitch(0x10U, 55, "Sol3");
    test_note_pitch(0x20U, 57, "La3");

    // Retorna para Oitava 4 para manter invariantes
    PressControlBtn(fpga->btn_oitava_up_n);
    WaitUartAndAudioIdle(4);
  }
  // --------------------------------------------------------------------------
  // Teste 12: Invariantes Globais de Audio PCM, Filas e Vozes
  // --------------------------------------------------------------------------
  printf("[12/12] Verificando invariantes globais (PCM, filas, framing, zero zumbis)...\n");
  // Renderiza cauda final de release para confirmar retorno a 0 vozes totais
  for (int i = 0; i < 200; ++i)
  {
    sim_step_audio_block();
  }

  int active_notes_remaining = 0;
  for (int k = 0; k < 128; ++k)
  {
    if (g_ctx.note_active_count[k] != 0)
    {
      active_notes_remaining++;
    }
  }

  double dc_offset =
      (g_ctx.total_pcm_samples > 0)
          ? (static_cast<double>(g_ctx.sum_samples_dc) /
             static_cast<double>(g_ctx.total_pcm_samples))
          : 0.0;
  double global_rms =
      (g_ctx.total_pcm_samples > 0)
          ? sqrt(g_ctx.sum_sq_samples /
                 static_cast<double>(g_ctx.total_pcm_samples))
          : 0.0;

  SimQueue *mq = static_cast<SimQueue *>(midi_queue);

  check(g_ctx.uart_rx.framing_errors == 0U, "GLOBAL_UART_FRAMING",
        "Erros de framing 8N1 detectados na linha saida_serial");
  check(Serial1.rxOverflows() == 0U, "GLOBAL_SERIAL1_OVERFLOW",
        "Overflow no buffer de recepcao da Serial1");
  check(mq != nullptr && mq->overflow_count == 0U, "GLOBAL_QUEUE_OVERFLOW",
        "Overflow na fila FreeRTOS midi_queue");
  check(g_ctx.overlap_violations == 0U, "GLOBAL_MIDI_OVERLAP",
        "Violacoes de sobreposicao de notas MIDI");
  check(g_ctx.orphan_note_offs == 0U, "GLOBAL_MIDI_ORPHAN_OFF",
        "Note Off orfao detectado");
  check(active_notes_remaining == 0, "GLOBAL_MIDI_PAIRING",
        "Notas MIDI permaneceram abertas sem Note Off");
  check(CountSustainedVoices() == 0 && CountTotalActiveVoices() == 0,
        "GLOBAL_TSF_ZERO_VOICES",
        "Vozes permaneceram ativas no TSF ao final da suite");
  check(g_ctx.clipped_samples == 0U, "GLOBAL_PCM_NO_CLIPPING",
        "Amostras com clipping digital (|sample| == 32767) detectadas");
  check(fabs(dc_offset) < 200.0, "GLOBAL_PCM_DC_OFFSET",
        "DC offset anomalo no sinal PCM sintetizado");
  check(g_ctx.active_note_silent_blocks == 0U, "GLOBAL_PCM_NO_DROPOUTS",
        "Blocos I2S completamente silenciosos durante notas sustentadas");

  if (wav_out_path != nullptr && wav_out_path[0] != '\0')
  {
    bool ok_wav = WriteWavFile(wav_out_path, g_ctx.pcm_recording, kSampleRateHz);
    check(ok_wav, "GLOBAL_WAV_EXPORT", "Falha ao gravar arquivo .wav de saida");
    if (ok_wav)
    {
      printf("      Arquivo WAV exportado: %s (%zu frames estereo, %.2f s)\n",
             wav_out_path, g_ctx.pcm_recording.size() / 2U,
             static_cast<double>(g_ctx.pcm_recording.size() / 2U) /
                 static_cast<double>(kSampleRateHz));
    }
  }

  // Exporta relatorio estruturado de eventos MIDI e metricas PCM
  {
    const char *report_path = "sim/cosim_report.json";
    FILE *rf = fopen(report_path, "w");
    if (rf != nullptr)
    {
      fprintf(rf, "{\n");
      fprintf(rf, "  \"passed\": %s,\n", (failures == 0) ? "true" : "false");
      fprintf(rf, "  \"failures\": %d,\n", failures);
      fprintf(rf, "  \"full_50mhz\": %s,\n", full_50mhz ? "true" : "false");
      fprintf(rf, "  \"total_fpga_cycles\": %llu,\n",
              static_cast<unsigned long long>(g_ctx.total_cycles));
      fprintf(rf, "  \"uart_bytes_received\": %u,\n",
              g_ctx.uart_rx.bytes_received);
      fprintf(rf, "  \"uart_framing_errors\": %u,\n",
              g_ctx.uart_rx.framing_errors);
      fprintf(rf, "  \"midi_note_on_count\": %u,\n", g_ctx.note_on_total);
      fprintf(rf, "  \"midi_note_off_count\": %u,\n", g_ctx.note_off_total);
      fprintf(rf, "  \"midi_overlap_violations\": %u,\n",
              g_ctx.overlap_violations);
      fprintf(rf, "  \"pcm_stereo_frames\": %llu,\n",
              static_cast<unsigned long long>(g_ctx.total_pcm_samples / 2U));
      fprintf(rf, "  \"pcm_peak_abs\": %d,\n", g_ctx.max_abs_sample);
      fprintf(rf, "  \"pcm_rms\": %.2f,\n", global_rms);
      fprintf(rf, "  \"pcm_dc_offset\": %.4f,\n", dc_offset);
      fprintf(rf, "  \"pcm_clipped_samples\": %u,\n", g_ctx.clipped_samples);
      fprintf(rf, "  \"tsf_final_active_voices\": %d,\n",
              CountTotalActiveVoices());
      fprintf(rf, "  \"midi_events\": [\n");
      for (size_t idx = 0; idx < g_ctx.midi_log.size(); ++idx)
      {
        const MidiLogEntry &ev = g_ctx.midi_log[idx];
        fprintf(
            rf,
            "    {\"cycle\": %llu, \"status\": \"0x%02X\", \"note\": %u, \"velocity\": %u}%s\n",
            static_cast<unsigned long long>(ev.cycle), ev.status, ev.data1,
            ev.data2, (idx + 1U < g_ctx.midi_log.size()) ? "," : "");
      }
      fprintf(rf, "  ]\n}\n");
      fclose(rf);
      printf("      Relatorio de eventos : %s (%zu eventos MIDI)\n",
             report_path, g_ctx.midi_log.size());
    }
  }

  printf("--------------------------------------------------------------------\n");
  printf(" RESUMO DA AUDITORIA:\n");
  printf("   Ciclos de clock FPGA simulados : %llu\n",
         static_cast<unsigned long long>(g_ctx.total_cycles));
  printf("   Bytes UART 8N1 demodulados     : %u (erros framing: %u)\n",
         g_ctx.uart_rx.bytes_received, g_ctx.uart_rx.framing_errors);
  printf("   Eventos MIDI (Note On / Off)   : %u On / %u Off (fila max: %u/%u)\n",
         g_ctx.note_on_total, g_ctx.note_off_total,
         mq ? mq->high_water_mark : 0U, mq ? mq->capacity : 0U);
  printf("   Amostras PCM 16-bit geradas    : %llu (pico: %d, RMS: %.1f, DC: %.2f)\n",
         static_cast<unsigned long long>(g_ctx.total_pcm_samples),
         g_ctx.max_abs_sample, global_rms, dc_offset);
  printf("   Clipping digital / Vozes presas: %u / %d\n",
         g_ctx.clipped_samples, CountTotalActiveVoices());
  printf("--------------------------------------------------------------------\n");

  if (failures == 0)
  {
    printf(" RESULTADO FINAL: TODOS OS 12 CENARIOS E INVARIANTES PASSARAM!\n");
    printf("====================================================================\n");
    return 0;
  }
  else
  {
    printf(" RESULTADO FINAL: FALHOU COM %d ERRO(S)!\n", failures);
    printf("====================================================================\n");
    return 1;
  }
}

// ============================================================================
// Gerador de Vetor de Lockstep Ciclo-a-Ciclo para Comparacao com ModelSim
// ============================================================================

static int RunLockstepDump(const char *out_path, const char *rom_hex_path)
{
  FILE *f = fopen(out_path, "w");
  if (!f)
  {
    fprintf(stderr, "[ERRO] Nao foi possivel abrir %s para escrita.\n", out_path);
    return 1;
  }

  // Usa os mesmos parametros rapidos do testbench para exercitar todos os modos
  Vpiano_top dut(4, 4, 2, 60, rom_hex_path);
  dut.clk = 0;
  dut.reset_n = 0;
  dut.gpio_keys = 0;
  dut.btn_modo_n = 1;
  dut.btn_musica_n = 1;
  dut.btn_intensidade_n = 1;
  dut.btn_oitava_up_n = 1;
  dut.btn_oitava_down_n = 1;
  dut.btn_sustenido = 0;
  dut.eval();

  for (uint32_t cyc = 0; cyc < 5000U; ++cyc)
  {
    // Aplica estimulos deterministicos no negedge (cyc)
    dut.clk = 0;
    if (cyc == 4)
      dut.reset_n = 1;
    // Modo 0: toca tecla 0 (C4), acorde 0+2 (C4+E4), solta E4, troca sustenido, oitava +/- e brilho PWM
    if (cyc == 20)
      dut.gpio_keys = 0x01;
    if (cyc == 150)
      dut.gpio_keys = 0x05;
    if (cyc == 240)
      dut.gpio_keys = 0x01;
    if (cyc == 300)
      dut.btn_sustenido = 1;
    if (cyc == 420)
      dut.btn_oitava_up_n = 0;
    if (cyc == 432)
      dut.btn_oitava_up_n = 1;
    if (cyc == 540)
      dut.btn_oitava_down_n = 0;
    if (cyc == 552)
      dut.btn_oitava_down_n = 1;
    if (cyc == 600)
      dut.gpio_keys = 0x00;
    if (cyc == 750)
      dut.btn_intensidade_n = 0;
    if (cyc == 762)
      dut.btn_intensidade_n = 1;
    if (cyc == 900)
      dut.btn_sustenido = 0;
    // Combo de volume (Modo + Intensidade)
    if (cyc == 950)
      dut.btn_modo_n = 0;
    if (cyc == 970)
      dut.btn_intensidade_n = 0;
    if (cyc == 985)
      dut.btn_intensidade_n = 1;
    if (cyc == 1000)
      dut.btn_modo_n = 1;
    // Seleciona musica 4 (Clair de Lune: primeira nota G4 = tecla 4 = 0x10)
    if (cyc >= 1050 && cyc < 1130)
      dut.btn_musica_n = ((cyc % 20) < 10) ? 0 : 1;
    if (cyc == 1130)
      dut.btn_musica_n = 1;
    // Vai para Modo 1 (Aprendizado) e testa tecla errada (0x01) + tecla certa (0x10) + avanco ROM
    if (cyc == 1160)
      dut.btn_modo_n = 0;
    if (cyc == 1170)
      dut.btn_modo_n = 1;
    if (cyc == 1190)
      dut.gpio_keys = 0x01;
    if (cyc == 1215)
      dut.gpio_keys = 0x00;
    if (cyc == 1235)
      dut.gpio_keys = 0x10;
    if (cyc == 1265)
      dut.gpio_keys = 0x00;
    // Vai para Modo 2 (Gravacao) e grava nota na RAM M10K
    if (cyc == 1300)
      dut.btn_modo_n = 0;
    if (cyc == 1310)
      dut.btn_modo_n = 1;
    if (cyc == 1350)
      dut.gpio_keys = 0x01;
    if (cyc == 1550)
      dut.gpio_keys = 0x00;
    // Vai para Modo 3 (Demo) e dispara Demo na musica 4
    if (cyc == 1900)
      dut.btn_modo_n = 0;
    if (cyc == 1910)
      dut.btn_modo_n = 1;
    if (cyc == 1950)
      dut.gpio_keys = 0x01;
    if (cyc == 1965)
      dut.gpio_keys = 0x00;

    // Cicla os 5 niveis de volume (1->2->3->4[mudo]->0[100%]) durante Demo
    if (cyc == 2300)
      dut.btn_modo_n = 0;
    if (cyc == 2320)
      dut.btn_intensidade_n = 0;
    if (cyc == 2332)
      dut.btn_intensidade_n = 1;
    if (cyc == 2350)
      dut.btn_intensidade_n = 0;
    if (cyc == 2362)
      dut.btn_intensidade_n = 1;
    if (cyc == 2380)
      dut.btn_intensidade_n = 0;
    if (cyc == 2392)
      dut.btn_intensidade_n = 1;
    if (cyc == 2452)
      dut.btn_intensidade_n = 0;
    if (cyc == 2464)
      dut.btn_intensidade_n = 1;
    if (cyc == 2480)
      dut.btn_modo_n = 1;

    // Volta para Modo 0 e seleciona musica 42 (RAM): 4 + 38 = 42
    if (cyc == 2500)
      dut.btn_modo_n = 0;
    if (cyc == 2510)
      dut.btn_modo_n = 1;
    if (cyc >= 2540 && cyc < 3300)
      dut.btn_musica_n = (((cyc - 2540) % 20) < 10) ? 0 : 1;
    if (cyc == 3300)
      dut.btn_musica_n = 1;

    // Vai para Modo 2 (Gravacao) e grava legato (C4->E4) + pausa + G4 na RAM
    if (cyc == 3320)
      dut.btn_modo_n = 0;
    if (cyc == 3330)
      dut.btn_modo_n = 1;
    if (cyc == 3350)
      dut.btn_modo_n = 0;
    if (cyc == 3360)
      dut.btn_modo_n = 1;
    if (cyc == 3390)
      dut.gpio_keys = 0x01;
    if (cyc == 3520)
      dut.gpio_keys = 0x05;
    if (cyc == 3595)
      dut.gpio_keys = 0x00;
    if (cyc == 3730)
      dut.gpio_keys = 0x10;
    if (cyc == 3805)
      dut.gpio_keys = 0x00;

    // Vai para Modo 3 (Demo) e reproduz gravacao RAM (persistencia)
    if (cyc == 3830)
      dut.btn_modo_n = 0;
    if (cyc == 3840)
      dut.btn_modo_n = 1;
    if (cyc == 3860)
      dut.gpio_keys = 0x01;
    if (cyc == 3872)
      dut.gpio_keys = 0x00;

    // Vai para Modo 0 -> Modo 1 na musica 42 (RAM), completa 3 notas e testa auto-reinicio
    if (cyc == 4460)
      dut.btn_modo_n = 0;
    if (cyc == 4470)
      dut.btn_modo_n = 1;
    if (cyc == 4490)
      dut.btn_modo_n = 0;
    if (cyc == 4500)
      dut.btn_modo_n = 1;
    if (cyc == 4525)
      dut.gpio_keys = 0x01;
    if (cyc == 4545)
      dut.gpio_keys = 0x00;
    if (cyc == 4570)
      dut.gpio_keys = 0x04;
    if (cyc == 4590)
      dut.gpio_keys = 0x00;
    if (cyc == 4615)
      dut.gpio_keys = 0x10;
    if (cyc == 4635)
      dut.gpio_keys = 0x00;
    if (cyc == 4720)
      dut.gpio_keys = 0x01;
    if (cyc == 4740)
      dut.gpio_keys = 0x00;

    dut.eval();

    // Borda de subida
    dut.clk = 1;
    dut.eval();

    fprintf(f, "%u %u %02x %u %u %u %u %u %u | %u %u %02x %u %u %u %02x %02x %02x %02x %02x %02x\n",
            dut.reset_n, dut.gpio_keys, dut.btn_modo_n, dut.btn_musica_n,
            dut.btn_intensidade_n, dut.btn_oitava_up_n, dut.btn_oitava_down_n,
            dut.btn_sustenido, cyc, dut.saida_serial, dut.servo_controle,
            dut.led_vermelho, dut.led_sustenido, dut.led_oitava_up,
            dut.led_oitava_down, dut.hex5_modo, dut.hex4_oitava,
            dut.hex3_musica_dezena, dut.hex2_musica_unidade, dut.hex1_nota,
            dut.hex0_sustenido);
  }

  fclose(f);
  return 0;
}

// ============================================================================
// API Exportada (DLL / CLI Interativo) para a Bancada Virtual (virtual_bench.py)
// ============================================================================

struct CoSimBenchStatus
{
  uint8_t hex5_modo;
  uint8_t hex4_oitava;
  uint8_t hex3_musica_dezena;
  uint8_t hex2_musica_unidade;
  uint8_t hex1_nota;
  uint8_t hex0_sustenido;
  uint8_t led_vermelho_pwm[7]; // 0..255 brilho medio no frame
  uint8_t led_sustenido;
  uint8_t led_oitava_up;
  uint8_t led_oitava_down;
  uint8_t servo_controle;
  uint8_t modo_ativo;
  uint8_t oitava_atual;
  uint8_t sustenido_atual;
  uint8_t sel_musica;
  uint8_t volume_state;
  uint8_t mostra_vol;
  uint16_t endereco_partitura;
  int32_t tsf_active_voices;
  int32_t tsf_sustained_voices;
  int32_t peak_l;
  int32_t peak_r;
  uint8_t last_midi_status;
  uint8_t last_midi_data1;
  uint8_t last_midi_data2;
  uint32_t midi_note_on_count;
  uint32_t midi_note_off_count;
  uint32_t uart_bytes_count;
  uint32_t overlap_violations;
  uint8_t stuck_note_alert;
  uint8_t metro_posicao;
  uint8_t led_brightness_state;
};

COSIM_EXPORT int cosim_init(int full_50mhz, const char *rom_hex_path)
{
  InitCoSimEngine(full_50mhz != 0,
                  (rom_hex_path && rom_hex_path[0]) ? rom_hex_path
                                                    : "music/partituras.hex",
                  false);
  // Descarta o audio do autoteste de boot para iniciar a bancada pronta para tocar
  for (int i = 0; i < 160; ++i)
  {
    sim_step_audio_block();
  }
  g_ctx.realtime_pcm_fifo.clear();
  return 0;
}

COSIM_EXPORT void cosim_set_inputs(uint8_t gpio_keys, uint8_t btn_sustenido,
                                   uint8_t btn_modo_n, uint8_t btn_musica_n,
                                   uint8_t btn_intensidade_n,
                                   uint8_t btn_oitava_up_n,
                                   uint8_t btn_oitava_down_n, uint8_t reset_n)
{
  if (!g_ctx.fpga)
    return;
  g_ctx.fpga->gpio_keys = gpio_keys & 0x7FU;
  g_ctx.fpga->btn_sustenido = btn_sustenido & 1U;
  g_ctx.fpga->btn_modo_n = btn_modo_n & 1U;
  g_ctx.fpga->btn_musica_n = btn_musica_n & 1U;
  g_ctx.fpga->btn_intensidade_n = btn_intensidade_n & 1U;
  g_ctx.fpga->btn_oitava_up_n = btn_oitava_up_n & 1U;
  g_ctx.fpga->btn_oitava_down_n = btn_oitava_down_n & 1U;
  g_ctx.fpga->reset_n = reset_n & 1U;
}

// Avanca o motor pelo numero exato de blocos de audio I2S (cada bloco = 256 frames = 5.333 ms)
// e retorna as amostras PCM estereo intercaladas em out_pcm_stereo (256 * num_blocks * 2 int16_t).
COSIM_EXPORT int cosim_step_audio_blocks(int num_blocks, int16_t *out_pcm_stereo,
                                         CoSimBenchStatus *out_status)
{
  if (!g_ctx.fpga || num_blocks <= 0)
    return 0;

  g_ctx.realtime_pcm_fifo.clear();
  memset(g_ctx.led_on_Accum, 0, sizeof(g_ctx.led_on_Accum));
  g_ctx.led_sample_cycles = 0;

  uint64_t cycles_to_run =
      static_cast<uint64_t>(num_blocks) * g_ctx.cycles_per_i2s_block;
  StepCycles(cycles_to_run);

  size_t desired_shorts = static_cast<size_t>(num_blocks) * kAudioBlockFrames * 2U;
  while (g_ctx.realtime_pcm_fifo.size() < desired_shorts)
  {
    sim_step_audio_block();
  }

  if (out_pcm_stereo != nullptr)
  {
    memcpy(out_pcm_stereo, g_ctx.realtime_pcm_fifo.data(),
           desired_shorts * sizeof(int16_t));
  }

  if (out_status != nullptr)
  {
    Vpiano_top *f = g_ctx.fpga;
    out_status->hex5_modo = f->hex5_modo;
    out_status->hex4_oitava = f->hex4_oitava;
    out_status->hex3_musica_dezena = f->hex3_musica_dezena;
    out_status->hex2_musica_unidade = f->hex2_musica_unidade;
    out_status->hex1_nota = f->hex1_nota;
    out_status->hex0_sustenido = f->hex0_sustenido;
    uint32_t denom = (g_ctx.led_sample_cycles > 0U) ? g_ctx.led_sample_cycles : 1U;
    for (int b = 0; b < 7; ++b)
    {
      out_status->led_vermelho_pwm[b] = static_cast<uint8_t>(
          (g_ctx.led_on_Accum[b] * 255ULL) / denom);
    }
    out_status->led_sustenido = f->led_sustenido;
    out_status->led_oitava_up = f->led_oitava_up;
    out_status->led_oitava_down = f->led_oitava_down;
    out_status->servo_controle = f->servo_controle;
    out_status->modo_ativo = f->debug_modo_ativo();
    out_status->oitava_atual = f->debug_oitava_atual();
    out_status->sustenido_atual = f->debug_sustenido_atual();
    out_status->sel_musica = f->debug_sel_musica();
    out_status->volume_state = f->debug_volume();
    out_status->mostra_vol = f->debug_mostra_vol();
    out_status->endereco_partitura = f->debug_endereco_ram();
    out_status->tsf_active_voices = CountTotalActiveVoices();
    out_status->tsf_sustained_voices = CountSustainedVoices();
    out_status->peak_l = g_ctx.last_block_peak_l;
    out_status->peak_r = g_ctx.last_block_peak_r;
    out_status->last_midi_status = g_ctx.last_midi_status;
    out_status->last_midi_data1 = g_ctx.last_midi_data1;
    out_status->last_midi_data2 = g_ctx.last_midi_data2;
    out_status->midi_note_on_count = g_ctx.note_on_total;
    out_status->midi_note_off_count = g_ctx.note_off_total;
    out_status->uart_bytes_count = g_ctx.uart_rx.bytes_received;
    out_status->overlap_violations = g_ctx.overlap_violations;
    out_status->stuck_note_alert =
        (g_ctx.overlap_violations > 0U || g_ctx.stuck_voice_blocks > 4U) ? 1U : 0U;
    out_status->metro_posicao = f->debug_metro_posicao();
    out_status->led_brightness_state = f->debug_estado_intensidade();
  }

  return static_cast<int>(desired_shorts / 2U);
}

static int RunInteractivePipeLoop(bool full_50mhz, const char *rom_hex_path)
{
  cosim_init(full_50mhz ? 1 : 0, rom_hex_path);
  printf("READY\n");
  fflush(stdout);

  char line[256];
  std::vector<int16_t> pcm_buf(kAudioBlockFrames * 2 * 4);
  CoSimBenchStatus st = {};

  while (fgets(line, sizeof(line), stdin))
  {
    if (strncmp(line, "QUIT", 4) == 0)
    {
      break;
    }
    else if (strncmp(line, "SET ", 4) == 0)
    {
      unsigned int keys = 0, sust = 0, modo_n = 1, mus_n = 1, int_n = 1,
                   up_n = 1, dn_n = 1, rst_n = 1;
      if (sscanf(line + 4, "%u %u %u %u %u %u %u %u", &keys, &sust, &modo_n,
                 &mus_n, &int_n, &up_n, &dn_n, &rst_n) >= 7)
      {
        cosim_set_inputs(static_cast<uint8_t>(keys), static_cast<uint8_t>(sust),
                         static_cast<uint8_t>(modo_n),
                         static_cast<uint8_t>(mus_n),
                         static_cast<uint8_t>(int_n),
                         static_cast<uint8_t>(up_n),
                         static_cast<uint8_t>(dn_n),
                         static_cast<uint8_t>(rst_n));
      }
      printf("OK\n");
      fflush(stdout);
    }
    else if (strncmp(line, "STEP", 4) == 0)
    {
      int blocks = 1;
      sscanf(line + 4, "%d", &blocks);
      if (blocks < 1)
        blocks = 1;
      if (blocks > 16)
        blocks = 16;
      pcm_buf.resize(static_cast<size_t>(blocks) * kAudioBlockFrames * 2U);
      cosim_step_audio_blocks(blocks, pcm_buf.data(), &st);
      printf("STATE %02x %02x %02x %02x %02x %02x %u %u %u %u %u %u %u %u %u %d %d %d %d %02x %02x %02x\n",
             st.hex5_modo, st.hex4_oitava, st.hex3_musica_dezena,
             st.hex2_musica_unidade, st.hex1_nota, st.hex0_sustenido,
             st.led_vermelho_pwm[0], st.led_vermelho_pwm[1],
             st.led_vermelho_pwm[2], st.led_vermelho_pwm[3],
             st.led_vermelho_pwm[4], st.led_vermelho_pwm[5],
             st.led_vermelho_pwm[6], st.led_sustenido, st.modo_ativo,
             st.tsf_active_voices, st.tsf_sustained_voices, st.peak_l,
             st.peak_r, st.last_midi_status, st.last_midi_data1,
             st.last_midi_data2);
      fflush(stdout);
    }
  }
  return 0;
}

int main(int argc, char **argv)
{
  bool mode_suite = true;
  bool mode_interactive = false;
  bool full_50mhz = false;
  const char *wav_path = "sim/cosim_output.wav";
  const char *rom_hex_path = "music/partituras.hex";
  const char *lockstep_path = nullptr;

  for (int i = 1; i < argc; ++i)
  {
    if (strcmp(argv[i], "--suite") == 0)
    {
      mode_suite = true;
      mode_interactive = false;
    }
    else if (strcmp(argv[i], "--interactive") == 0)
    {
      mode_interactive = true;
      mode_suite = false;
    }
    else if (strcmp(argv[i], "--full-50mhz") == 0)
    {
      full_50mhz = true;
    }
    else if (strcmp(argv[i], "--wav") == 0 && i + 1 < argc)
    {
      wav_path = argv[++i];
    }
    else if (strcmp(argv[i], "--rom") == 0 && i + 1 < argc)
    {
      rom_hex_path = argv[++i];
    }
    else if (strcmp(argv[i], "--lockstep-dump") == 0 && i + 1 < argc)
    {
      lockstep_path = argv[++i];
    }
  }

  if (lockstep_path != nullptr)
  {
    return RunLockstepDump(lockstep_path, rom_hex_path);
  }
  if (mode_interactive)
  {
    return RunInteractivePipeLoop(full_50mhz, rom_hex_path);
  }
  (void)mode_suite;
  return RunAutomatedSuite(full_50mhz, wav_path, rom_hex_path);
}
