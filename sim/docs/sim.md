## 1. Arquitetura do Ambiente

A co-simulação fecha o ciclo completo entre a FPGA e o microcontrolador:

1. **FPGA (RTL ciclo a ciclo):** Executa o top-level `piano_top.v` recebendo estímulos de chaves e botões, gerenciando displays de 7 segmentos (`HEX5..HEX0`), LEDs modulados por PWM e gerando o fluxo serial UART 8N1 em 115200 bps (`saida_serial`).
2. **Receptor Serial Bit-Accurate:** Amostra e decodifica o pino serial nos tempos físicos simulados, verificando start/stop bits e alimentando o buffer de recepção `Serial1` do ESP32.
3. **Firmware ESP32-S3 (Código Real):** Compila diretamente `esp32_midi_synth.ino` com uma camada de abstração HAL determinística para a fila FreeRTOS, o parser MIDI e as tarefas de síntese `tsf.h`.
4. **Síntese e Auditoria:** Sintetiza o áudio via TinySoundFont utilizando `piano_sf2.h`, rastreia vozes ativas e envia os blocos de áudio PCM de 16 bits tanto para reprodução em tempo real quanto para exportação em `.wav`.

---

## 2. Bancada Virtual Interativa

### Como Iniciar

```powershell
python sim/virtual_bench.py
```

### Controles e Atalhos de Teclado

| Tecla / Botão | Ação / Função |
|---|---|
| **A, S, D, F, G, H, J** | Toca as teclas musicais (`Dó`, `Ré`, `Mi`, `Fá`, `Sol`, `Lá`, `Si`). |
| **W** | Alterna chave de Sustenido (`#`). |
| **Q / E** | Oitava Abaixo / Oitava Acima. |
| **M** | Botão Modo (`0: Livre`, `1: Aprender`, `2: Gravar`, `3: Demo`). |
| **N** | Botão Música (avança partituras da ROM). |
| **I** | Alterna intensidade/brilho do PWM dos LEDs. |
| **V** | Dispara o combo de Volume (`Modo + Intensidade` segurados). |
| **R** | Pulsa o Reset da FPGA. |
| **Check "Travar Tecla"** | Modo acordes: permite segurar múltiplas teclas com o clique do mouse. |

### Painéis de Diagnóstico Visual
- **Displays 7 Segmentos:** Renderização dos displays `HEX5..HEX0` (Modo, Oitava, Partitura, Nota e Sustenido).
- **LEDs da Placa:** `LEDR0..LEDR6` (modulados por PWM), `LED Sustenido`, `LED Oitava Up/Down` e indicador do servomotor do metrônomo.
- **Monitor do ESP32-S3:** Exibe em tempo real o último pacote MIDI recebido (`Status`, `Nota`, `Velocity`), número de vozes ativas no sintetizador TSF, medidor de nível sonoro (VU Meter) e alerta visual de nota presa (`ALERTA: NOTA PRESA`).

---

## 3. Suíte de Testes Automatizados

```powershell
python sim/tests/run_cosim_tests.py
```

1. **Auditoria de Ponto Flutuante (Xtensa Toolchain):** Compilação com `xtensa-esp32s3-elf-g++ -Werror=double-promotion` e checagem de símbolos via `nm` para garantir zero emulação de `double` por software (`__adddf3`, etc.).
2. **Lockstep RTL vs C++:** Comparação de 5.000 ciclos entre o motor C++ e a simulação compilada no ModelSim (`vlog`/`vsim`).
3. **12 Cenários Co-Simulados:**
   - Boot e autoteste do ESP32 (Dó4 com desligamento limpo).
   - Modo Livre: prioridade de notas, acordes e transições legato.
   - Troca de oitava e sustenido com tecla segurada (sem zumbis).
   - Combo de volume e restauração dos displays após 1 segundo.
   - Modo Aprendizado: trava de oitava/sustenido anti-pipoco da ROM.
   - Modo Gravação e Reprodução em RAM M10K (até o limite de endereço 1023).
   - Interrupção abrupta de reprodução com nota ativa (troca de modo/música).
   - Tolerância a ruídos UART com ressincronismo no byte de status.
   - Qualidade do áudio: ausência de clipping digital (`±32767`), ruído DC e silêncio anômalo.
4. **Verilog Linter:** Verificação estrutural do código RTL (`python scripts/lint_verilog.py`).

---

## 4. Simulação em Escala 1:1 (50 MHz Físicos)

Para rodar a co-simulação exatamente na mesma frequência e contagem de ciclos da placa física DE0-CV (sem fatores de aceleração temporal):

```powershell
.\sim\cosim_engine.exe --suite --full-50mhz
```

