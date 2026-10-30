# Documentação da Arquitetura Implementada: Piano Digital FPGA + MIDI 1.0 + ESP32-S3

## 1. Objetivo do Projeto

Substituir o subsistema de geração de áudio por onda quadrada em buzzer piezoelétrico (`gerador_audio.v` e `frequencia_lut.v`) por um sistema de síntese de piano acústico baseado em amostras (**SoundFont `.sf2`**) executado em um **ESP32-S3** conectado a um conversor **DAC I²S PCM5102A** e caixa de som ativa.

A arquitetura implementada preserva todos os **4 modos de operação** do piano na placa **DE0-CV (Cyclone V @ 50 MHz)**:
- **Modo 0 — Livre:** Execução em tempo real pelas 7 teclas físicas, botão de sustenido e controle de oitavas expandido (**oitavas 1 a 7**).
- **Modo 1 — Aprendizado:** Guia visual nos LEDs vermelhos, displays de 7 segmentos (`HEX0`..`HEX5`) e metrônomo mecânico via servomotor (`SG90`), aguardando o usuário pressionar a nota correta para avançar.
- **Modo 2 — Gravação:** Captura em tempo real na RAM (`sync_ram`) das notas tocadas pelo usuário, registrando tanto a duração de cada nota quanto a pausa entre notas consecutivas com resolução de `8 ms`.
- **Modo 3 — Demonstração:** Reprodução sequencial automática das 39 músicas em ROM (`sync_rom`) ou da música gravada pelo usuário na RAM (`sync_ram`), respeitando fielmente a nota MIDI, a dinâmica (*velocity*), a duração e a pausa de cada evento.

---

## 2. Visão Geral da Arquitetura

```text
Pré-Processamento (PC)                  FPGA Cyclone V (DE0-CV @ 50 MHz)
┌─────────────────────────┐             ┌──────────────────────────────────────────────────┐
│ Arquivos .mid / Acervo  │             │ Teclas (1..7) + Sustenido + Oitava (1..7)        │
│            ↓            │             │                        ↓                         │
│  scripts/midi_to_rom.py │             │           codificador_midi (Nota 0..127)         │
│  (Sustain CC64 embutido │             │                        │                         │
│   na duração da nota)   │             │ 39x sync_rom (30b) ──► mux_musicas (30b)         │
│            ↓            │             │ 1x  sync_ram (30b) ──► │       ↓                 │
│   Musicas/*.txt (30b)   ├────────────►│                 decodificador_midi (UI/LEDs/HEX) │
└─────────────────────────┘             │                        ↓                         │
                                        │        Temporizador 8 ms (Demo / Gravação)       │
                                        │                        ↓                         │
                                        │     gerenciador_midi_tx (Anti-Race Condition)    │
                                        │                        ↓                         │
                                        │         tx_serial_8N1 (115200 bps, 8N1)          │
                                        └────────────────────────┬─────────────────────────┘
                                                                 │ UART 8N1 (Pacotes 24 bits)
                                                                 ▼
                                        ┌──────────────────────────────────────────────────┐
                                        │                    ESP32-S3                      │
                                        │  Parser MIDI 1.0 (Auto-sincronismo pelo bit 7)   │
                                        │                        ↓                         │
                                        │   TinySoundFont (tsf.h) + SoundFont (piano_sf2)  │
                                        └────────────────────────┬─────────────────────────┘
                                                                 │ I²S (44.1 kHz, 16-bit, Estéreo)
                                                                 ▼
                                        ┌──────────────────────────────────────────────────┐
                                        │        DAC PCM5102A ──► Caixa de Som Ativa       │
                                        └──────────────────────────────────────────────────┘
```

---

## 3. Protocolo Serial: MIDI 1.0 Puro em UART 8N1 (Pacotes de 24 bits)

Em vez de um protocolo proprietário de 7 bits com bytes de escape (`7E`/`7F`/`7D`), foi adotado o protocolo **MIDI 1.0 Puro sobre UART 8N1 a 115200 bps**:

- **Camada Física (`tx_serial_8N1.v`):**
  - Taxa de transmissão: **115.200 bps** (`CLOCK_DIV = 434` ciclos de clock a 50 MHz por bit).
  - Quadro serial de 10 bits: `1 Start Bit (0)` + `8 Data Bits (LSB primeiro)` + `1 Stop Bit (1)`, sem bit de paridade (**8N1**).
  - Tempo de transmissão: `86,8 µs` por byte (`~260,4 µs` para um pacote completo de 24 bits / 3 bytes).

- **Estrutura do Pacote de 24 bits (3 Bytes):**

| Evento | Byte 0 (Status, `MSB = 1`) | Byte 1 (Nota, `MSB = 0`) | Byte 2 (Velocity, `MSB = 0`) | Descrição |
|---|---|---|---|---|
| **Note On** | `8'h90` (`1001_0000`) | `{1'b0, nota_midi[6:0]}` | `{1'b0, velocity[6:0]}` | Inicia a reprodução da nota com a intensidade especificada (`1..127`). |
| **Note Off** | `8'h80` (`1000_0000`) | `{1'b0, nota_midi[6:0]}` | `8'h00` (`0000_0000`) | Encerra a sustentação da nota, iniciando a fase de *release* no sintetizador. |

- **Auto-Sincronismo pelo MSB (Bit 7):**
  - No padrão MIDI 1.0, exclusivamente o **Byte de Status (Byte 0)** possui o bit mais significativo igual a `1` (`byte >= 0x80`).
  - Todos os **Bytes de Dados (Bytes 1 e 2)** possuem o bit mais significativo igual a `0` (`0x00 .. 0x7F`).
  - Dessa forma, o receptor no ESP32-S3 sincroniza a janela de 24 bits instantaneamente sempre que recebe um byte com `MSB == 1`, eliminando qualquer possibilidade de desalinhamento de frame sem necessidade de delimitadores ou sequências de escape.

---

## 4. Formato da Palavra de 30 Bits nas Memórias (`sync_rom` e `sync_ram`)

As **39 ROMs de músicas (`sync_rom`)** e a **RAM de gravação do usuário (`sync_ram`)** possuem **1024 posições de 30 bits** cada:

```text
  29          22 21          14 13           7 6            0
┌───────────────┬───────────────┬──────────────┬──────────────┐
│  PAUSA [7:0]  │ DURACAO [7:0] │ VELOCITY[6:0]│ NOTA_MIDI[6:0│
└───────────────┴───────────────┴──────────────┴──────────────┘
     8 bits          8 bits          7 bits         7 bits
```

| Bits | Campo | Largura | Descrição |
|---|---|---|---|
| `[29:22]` | `PAUSA` | 8 bits | Tempo em silêncio após o `Note Off` até o início da próxima nota, em múltiplos de `8 ms` (`0` a `255` ticks = `0 ms` a `2,04 s`). |
| `[21:14]` | `DURACAO` | 8 bits | Tempo em que a nota permanece ativa entre `Note On` e `Note Off`, em múltiplos de `8 ms` (`1` a `255` ticks = `8 ms` a `2,04 s`). |
| `[13:7]` | `VELOCITY` | 7 bits | Intensidade MIDI de ataque da nota (`1..127`). Escalada pelo seletor de volume global do FPGA (`100%`, `75%` ou `50%`). |
| `[6:0]` | `NOTA_MIDI` | 7 bits | Número oficial da nota MIDI (`24` = Dó1 / `C1` até `107` = Si7 / `B7`; `60` = Dó4 / `C4`). O valor `0` indica **Fim de Música**. |

### Orçamento de Memória M10K no Cyclone V (DE0-CV)
- Cada memória de `1024 × 30 bits` utiliza **3 blocos M10K** (cada bloco M10K do Cyclone V suporta até `1024 × 10 bits`).
- Total utilizado pelas 39 ROMs + 1 RAM: $40 \times 3 = \mathbf{120\text{ blocos M10K}}$ de **308 blocos disponíveis** na FPGA (**38,9% de ocupação**), cabendo com ampla folga na síntese do Quartus Prime.

---

## 5. Pré-Processamento de MIDI e Tratamento do Pedal de Sustain (`CC 64`)

O script [`scripts/midi_to_rom.py`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/scripts/midi_to_rom.py) converte arquivos `.mid` padrão (como `debussy-clair-de-lune.mid`) e o acervo musical em arquivos `.txt` de 30 bits para inicialização das ROMs (`$readmemb`):

1. **Sustentação por Pedal (`Control Change 64` Embutido na `DURACAO`):**
   - Quando o arquivo MIDI ativa o pedal de sustain (`CC 64 >= 64`), qualquer evento `Note Off` que ocorra enquanto o pedal estiver pressionado tem seu encerramento retido até o instante em que o pedal é solto (`CC 64 < 64`) ou até um novo ataque da mesma nota.
   - A duração efetiva resultante (do `Note On` até o fim real da sustentação) é quantizada em ticks de `8 ms` e gravada diretamente no campo `DURACAO[7:0]`, reproduzindo o efeito de sustentação do piano sem exigir transmissão extra de eventos de pedal.
2. **Redução Monofônica Inteligente (*Melody Priority*):**
   - Em passagens polifônicas ou arpejos sobrepostos, o conversor prioriza a nota melódica principal e ajusta automaticamente `DURACAO` e `PAUSA` a partir do delta de tempo real (`delta_ticks`) até a nota seguinte.

---

## 6. Módulos RTL Criados e Atualizados

### 6.1. Novos Módulos Sintetizáveis
- [`codificador_midi.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/codificador_midi.v): Converte `(oitava[2:0], sustenido, nota_id[2:0])` para o número de nota MIDI padrão (`nota_midi[6:0] = 12 * (oitava + 1) + semitom`), cobrindo das oitavas 1 a 7 (`24..107`) usando apenas somas e deslocamentos combinacionais (zero multiplicadores ou divisores).
- [`decodificador_midi.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/decodificador_midi.v): Operação inversa pura sem uso de operadores `/` ou `%`, convertendo `nota_midi[6:0]` lida da ROM/RAM em `(oitava[2:0], sustenido, nota_id[2:0])` para acionamento dos displays `HEX4`/`HEX1`/`HEX0`, LEDs das teclas e comparador do Modo Aprendizado.
- [`tx_serial_8N1.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/tx_serial_8N1.v), [`tx_serial_8N1_fd.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/tx_serial_8N1_fd.v) e [`tx_serial_8N1_uc.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/tx_serial_8N1_uc.v): Transmissor serial UART 8N1 parametrizável (`CLOCK_DIV = 434` para 115200 bps a 50 MHz).
- [`gerenciador_midi_tx.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/gerenciador_midi_tx.v): Máquina de estados anti-*race-condition* que reconcilia continuamente `nota_desejada[6:0]` com `nota_tocando_reg[6:0]`:
  - Se a nota desejada mudar enquanto uma nota estava soando (ex.: execução em *legato*, mudança de oitava/sustenido com tecla pressionada ou troca de modo/música), envia primeiro o pacote de 24 bits **`Note Off` (`0x80`)** da nota anterior e, logo ao terminar os 3 bytes, envia o pacote **`Note On` (`0x90`)** da nova nota, impedindo notas presas (*stuck notes*) ou perda de eventos durante os `260 µs` de ocupação da UART.

### 6.2. Módulos Atualizados
- [`guarda_oitava.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/guarda_oitava.v): Faixa de oitavas expandida de `1` (`3'b001`) a `7` (`3'b111`), com valor inicial `4` (`3'b100`) no reset.
- [`mux_musicas.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/mux_musicas.v): Barramentos de entrada (`d0..d39`) e saída (`out`) ampliados de 7 bits para **30 bits** (`[29:0]`).
- [`unidade_controle.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/unidade_controle.v): FSM atualizada para gravar na RAM (`GRAVA_ESCREVE` / `GRAVA_PROXIMO`) após a medição completa da duração da nota e da pausa subsequente, além de gravar a palavra sentinela de fim de música (`30'd0` em `GRAVA_FIM`) caso o usuário encerre a gravação pelo botão de modo.
- [`fluxo_dados.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/fluxo_dados.v): Integração das 39 ROMs e 1 RAM de 30 bits, substituição do gerador de onda quadrada pelo pipeline MIDI (`codificador_midi`, `decodificador_midi`, `gerenciador_midi_tx`), escalonamento de *velocity* por hardware (`100%`, `75%`, `50%`) e contadores de ticks de `8 ms` para reprodução no Modo Demonstração e captura no Modo Gravação.
- [`piano_top.v`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/piano_top.v): Substituição da saída `buzzer` pela saída `saida_serial` (UART 8N1 115200 bps rumo ao ESP32-S3), mantendo intactos os displays `HEX0..HEX5`, LEDs e servomotor do metrônomo.

---

## 7. Arquitetura do Firmware C no ESP32-S3 (`esp32_midi_synth/`)

O diretório [`esp32_midi_synth/`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/esp32_midi_synth) contém a implementação completa para o microcontrolador **ESP32-S3**:

- [`esp32_midi_synth/esp32_midi_synth.ino`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/esp32_midi_synth/esp32_midi_synth.ino):
  - **Recepção UART1 (`115200 bps`, `SERIAL_8N1`):** Lê os bytes enviados pelo pino `saida_serial` do FPGA (pino padrão `GPIO 18`) e sincroniza o frame de 24 bits pelo bit 7 (`byte & 0x80`).
  - **Sincronização Multi-Core sem Race Conditions:** O loop de leitura UART empacota os eventos MIDI completos (`status`, `nota`, `velocity`) em uma fila FreeRTOS (`g_midi_q`), enquanto uma *task* dedicada de alta prioridade no Core 1 (`audio_synth_task`) consome a fila protegida por mutex (`g_tsf_mutex`) imediatamente antes de renderizar cada bloco de áudio.
  - **Síntese com `TinySoundFont` (`tsf.h`):** Carrega o SoundFont a partir da memória (`tsf_load_memory(g_piano_sf2, sizeof(g_piano_sf2))`), opera em `44100 Hz` Estéreo com até `16` vozes de polifonia (`tsf_set_max_voices(g_tsf, 16)`) e renderiza blocos curtos de `64` frames (`~1,45 ms` de latência por bloco) via `tsf_render_short()`.
  - **Saída Digital I²S para `PCM5102A`:** Transmite os blocos PCM de 16 bits Estéreo via DMA I²S (`GPIO 4` = `BCLK`, `GPIO 5` = `LRCK/WS`, `GPIO 6` = `DOUT/DIN`) diretamente para o DAC `PCM5102A`.
- [`esp32_midi_synth/sf2_to_header.py`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/esp32_midi_synth/sf2_to_header.py) e [`esp32_midi_synth/piano_sf2.h`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/esp32_midi_synth/piano_sf2.h):
  - Script utilitário em Python que converte qualquer arquivo SoundFont `.sf2` de piano em um array C (`const unsigned char g_piano_sf2[]`) pronto para compilação junto ao sketch.

### 7.1. Otimização de Memória no `TinySoundFont` (Acesso Direto à Flash / Zero RAM para Samples)
- **Desafio Original:** O motor `TinySoundFont` (`tsf.h`) por padrão converte todas as amostras PCM de 16 bits para ponto flutuante de 32 bits em tempo de inicialização, alocando $2 \times$ o tamanho das amostras em memória RAM dinâmica. Para um banco de alta fidelidade como o **Steinway Grand Piano** (`Keyzone_Steinway_Grand_Piano_ULTRA_LITE.sf2`, 14.36 MB), isso exigiria mais de 28,8 MB de RAM livre, ultrapassando os 8 MB de PSRAM do ESP32-S3 DevKitC (N16R8).
- **Implementação da Opção 2:**
  - Modificado o [`esp32_midi_synth/tsf.h`](file:///c:/Users/gabri/Documents/POLI_Docs/Lab%20Dig/Projeto/esp32_midi_synth/tsf.h) para expor um ponteiro direto (`direct_ptr`) ao fluxo mapeado em memória Flash (`PROGMEM` / MMU).
  - Em `tsf_load_samples()`, quando o ponteiro direto está disponível, o buffer flutuante é ignorado e a alocação de RAM para amostras passa a ser de **0 bytes**.
  - No laço interno de interpolação e síntese (`tsf_voice_render()`), a leitura é feita diretamente da Flash como amostras de 16 bits com sinal (`const short *`), aplicando a normalização `(1.0f / 32767.0f)` dinamicamente por frame.
  - **Resultado:** A alocação de RAM caiu de **28,87 MB** para apenas **157 KB** (redução de 99,45%), viabilizando o uso do Steinway Grand Piano completo de 14.36 MB com fidelidade acústica máxima.
