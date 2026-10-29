# Firmware do Sintetizador MIDI para ESP32-S3 (`esp32_midi_synth`)

Este diretório contém o firmware em C/C++ (Arduino/ESP-IDF) para o **ESP32-S3** que recebe pacotes **MIDI 1.0 de 24 bits (3 bytes)** via **UART 8N1 a 115200 bps** provenientes do FPGA Cyclone V (**DE0-CV**), sintetiza o timbre de piano utilizando **TinySoundFont (`tsf.h`)** e envia o áudio digital por **I²S (44.1 kHz, 16-bit, Estéreo)** ao conversor **DAC PCM5102A**.

---

## 1. Estrutura de Arquivos

- `esp32_midi_synth.ino`: Sketch principal do ESP32-S3 com parser MIDI 1.0 auto-sincronizado pelo MSB, fila FreeRTOS thread-safe, renderização `TinySoundFont` em blocos de 64 frames (~1,45 ms) e saída DMA I²S.
- `sf2_to_header.py`: Utilitário em Python para converter qualquer arquivo SoundFont (`.sf2`) para o header C `piano_sf2.h`.
- `piano_sf2.h`: Header C contendo o SoundFont em array `const unsigned char g_piano_sf2[]`. Já vem pré-gerado com um SoundFont funcional mínimo para compilação imediata.

---

## 2. Como Preparar o Ambiente e o SoundFont

1. **Obter o `tsf.h` (TinySoundFont):**
   Baixe o arquivo single-header `tsf.h` oficial do repositório [TinySoundFont](https://github.com/schellingb/TinySoundFont/blob/master/tsf.h) e coloque-o dentro desta pasta (`esp32_midi_synth/tsf.h`).

2. **Converter um SoundFont de Piano (`.sf2`) para `piano_sf2.h`:**
   Para usar amostras reais de piano acústico (recomendado arquivo `.sf2` compacto de 500 KB a 4 MB para caber na Flash ou PSRAM do ESP32-S3):
   ```bash
   python esp32_midi_synth/sf2_to_header.py caminho/para/seu_piano.sf2
   ```

---

## 3. Ligações de Hardware (Pinagem Padrão)

### 3.1. FPGA DE0-CV → ESP32-S3 (UART 8N1 @ 115200 bps, 3.3V LVTTL)

| Sinal no FPGA (`piano_top.v`) | Pino no ESP32-S3 | Descrição |
|---|---|---|
| `saida_serial` (GPIO 3.3V) | `GPIO 18` (`UART_RX_PIN`) | Recepção serial MIDI (pacotes de 24 bits) |
| `GND` | `GND` | Referência comum obrigatória |

### 3.2. ESP32-S3 → Módulo DAC PCM5102A (I²S)

| Pino no ESP32-S3 | Pino no PCM5102A | Descrição |
|---|---|---|
| `GPIO 4` (`I2S_BCLK_PIN`) | `BCK` | Bit Clock I²S |
| `GPIO 5` (`I2S_LRCK_PIN`) | `LCK` / `WS` | Word Select (Left/Right Clock - 44.1 kHz) |
| `GPIO 6` (`I2S_DOUT_PIN`) | `DIN` | Dados de áudio PCM 16-bit Estéreo |
| `GND` | `SCK` | **Conectar ao GND** para ativar a PLL interna do PCM5102A |
| `5V` ou `3V3` | `VIN` | Alimentação do módulo DAC |
| `GND` | `GND` | Terra comum |

---

## 4. Protocolo MIDI 1.0 Recebido (24 bits = 3 bytes)

O parser serial sincroniza automaticamente os pacotes de 3 bytes pelo bit 7 (`MSB`):

| Evento | Byte 0 (`MSB = 1`) | Byte 1 (`MSB = 0`) | Byte 2 (`MSB = 0`) | Ação no `TinySoundFont` |
|---|---|---|---|---|
| **Note On** | `0x90` | `nota` (`0..127`) | `velocity` (`1..127`) | `tsf_note_on(g_tsf, 0, nota, velocity / 127.0f)` |
| **Note Off** | `0x80` (ou `0x90` com `vel=0`) | `nota` (`0..127`) | `0x00` | `tsf_note_off(g_tsf, 0, nota)` |
| **Control Change** | `0xB0` | `control` (`0..127`) | `valor` (`0..127`) | `tsf_channel_midi_control(g_tsf, 0, control, valor)` |
