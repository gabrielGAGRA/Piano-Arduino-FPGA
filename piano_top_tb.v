// Descricao: Testbench auto-verificavel de integracao para o piano_top.
// Funcionamento: Valida Modo Livre (Note On/Off serial), Modo Gravacao e
// Demonstracao via RAM (com medicao de duracao), e reproducao da ROM Clair de Lune.

`timescale 1ns / 1ps
`default_nettype none

module piano_top_tb;

  localparam ClkPeriodNs      = 20;
  localparam DebounceTecla    = 10;
  localparam DebounceControle = 10;
  localparam ClockDivUart     = 4;
  localparam CiclosTick8ms    = 200;
  localparam WatchdogMaxNs    = 50_000_000;

  reg        clk;
  reg        reset_n;
  reg  [6:0] gpio_keys;
  reg        btn_modo_n;
  reg        btn_musica_n;
  reg        btn_intensidade_n;
  reg        btn_oitava_up_n;
  reg        btn_oitava_down_n;
  reg        btn_sustenido;
  reg        hcsr04_echo;

  wire       saida_serial;
  wire       saida_serial_dashboard;
  wire       servo_controle;
  wire       hcsr04_trigger;
  wire [6:0] led_vermelho;
  wire       led_sustenido;
  wire       led_oitava_up;
  wire       led_oitava_down;
  wire [6:0] hex5_modo;
  wire [6:0] hex4_oitava;
  wire [6:0] hex3_musica_dezena;
  wire [6:0] hex2_musica_unidade;
  wire [6:0] hex1_nota;
  wire [6:0] hex0_sustenido;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  piano_top #(
    .DebounceTecla   (DebounceTecla),
    .DebounceControle(DebounceControle),
    .ClockDivUart   (ClockDivUart),
    .CiclosTick8ms  (CiclosTick8ms)
  ) piano_top_inst (
    .clk                   (clk),
    .reset_n               (reset_n),
    .gpio_keys             (gpio_keys),
    .btn_modo_n            (btn_modo_n),
    .btn_musica_n          (btn_musica_n),
    .btn_intensidade_n     (btn_intensidade_n),
    .btn_oitava_up_n       (btn_oitava_up_n),
    .btn_oitava_down_n     (btn_oitava_down_n),
    .btn_sustenido         (btn_sustenido),
    .hcsr04_echo           (hcsr04_echo),
    .saida_serial          (saida_serial),
    .saida_serial_dashboard(saida_serial_dashboard),
    .servo_controle        (servo_controle),
    .hcsr04_trigger        (hcsr04_trigger),
    .led_vermelho          (led_vermelho),
    .led_sustenido         (led_sustenido),
    .led_oitava_up         (led_oitava_up),
    .led_oitava_down       (led_oitava_down),
    .hex5_modo             (hex5_modo),
    .hex4_oitava           (hex4_oitava),
    .hex3_musica_dezena    (hex3_musica_dezena),
    .hex2_musica_unidade   (hex2_musica_unidade),
    .hex1_nota             (hex1_nota),
    .hex0_sustenido        (hex0_sustenido)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Watchdog da simulacao estourou em piano_top_tb!", $time);
    $finish;
  end

  task setup;
    begin
      gpio_keys         <= 7'b0000000;
      btn_modo_n        <= 1'b1;
      btn_musica_n      <= 1'b1;
      btn_intensidade_n <= 1'b1;
      btn_oitava_up_n   <= 1'b1;
      btn_oitava_down_n <= 1'b1;
      btn_sustenido     <= 1'b0;
      hcsr04_echo       <= 1'b0;
      reset_n           <= 1'b0;
      repeat (4) @(posedge clk);
      @(negedge clk);
      reset_n           <= 1'b1;
      repeat (6) @(posedge clk);
      #1;
      if (saida_serial === 1'bx || saida_serial_dashboard === 1'bx ||
          hcsr04_trigger === 1'bx || led_vermelho === 7'bxxxxxxx) begin
        $display("[FATAL] %0t ns: Saida X apos reset em piano_top_tb.", $time);
        $finish;
      end
    end
  endtask

  task press_btn_modo;
    begin
      @(negedge clk);
      btn_modo_n <= 1'b0;
      repeat (DebounceControle + 3) @(posedge clk);
      @(negedge clk);
      btn_modo_n <= 1'b1;
      repeat (DebounceControle + 3) @(posedge clk);
    end
  endtask

  task press_btn_musica;
    begin
      @(negedge clk);
      btn_musica_n <= 1'b0;
      repeat (DebounceControle + 3) @(posedge clk);
      @(negedge clk);
      btn_musica_n <= 1'b1;
      repeat (DebounceControle + 3) @(posedge clk);
    end
  endtask

  task receive_uart_byte(
    output [7:0] rx_byte
  );
    integer bit_idx;
    begin
      @(negedge saida_serial);
      repeat (ClockDivUart / 2) @(posedge clk);
      #1;
      if (saida_serial !== 1'b0) begin
        $display("[FALHA] %0t ns | Erro no start bit UART: esperado 0, obtido %b",
          $time, saida_serial);
        errors = errors + 1;
      end
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        repeat (ClockDivUart) @(posedge clk);
        #1;
        rx_byte[bit_idx] = saida_serial;
      end
      repeat (ClockDivUart) @(posedge clk);
      #1;
      if (saida_serial !== 1'b1) begin
        $display("[FALHA] %0t ns | Erro no stop bit UART: esperado 1, obtido %b",
          $time, saida_serial);
        errors = errors + 1;
      end
    end
  endtask

  task receive_and_verify_midi_packet(
    input [23:0]  expected_packet,
    input [255:0] test_tag
  );
    reg [7:0]  b0;
    reg [7:0]  b1;
    reg [7:0]  b2;
    reg [23:0] actual_packet;
    begin
      receive_uart_byte(b0);
      receive_uart_byte(b1);
      receive_uart_byte(b2);
      actual_packet = {b0, b1, b2};
      if (actual_packet !== expected_packet) begin
        $display("[FALHA] %0t ns | %0s: esperado 24'h%06h, obtido 24'h%06h",
          $time, test_tag, expected_packet, actual_packet);
        errors = errors + 1;
      end
    end
  endtask

  task press_btn_oitava_up;
    begin
      @(negedge clk);
      btn_oitava_up_n <= 1'b0;
      repeat (DebounceControle + 3) @(posedge clk);
      @(negedge clk);
      btn_oitava_up_n <= 1'b1;
      repeat (DebounceControle + 3) @(posedge clk);
    end
  endtask

  task press_btn_oitava_down;
    begin
      @(negedge clk);
      btn_oitava_down_n <= 1'b0;
      repeat (DebounceControle + 3) @(posedge clk);
      @(negedge clk);
      btn_oitava_down_n <= 1'b1;
      repeat (DebounceControle + 3) @(posedge clk);
    end
  endtask

  task press_combo_volume;
    begin
      @(negedge clk);
      btn_modo_n <= 1'b0;
      repeat (DebounceControle + 3) @(posedge clk);
      @(negedge clk);
      btn_intensidade_n <= 1'b0;
      repeat (DebounceControle + 3) @(posedge clk);
      @(negedge clk);
      btn_intensidade_n <= 1'b1;
      repeat (DebounceControle + 3) @(posedge clk);
      @(negedge clk);
      btn_modo_n <= 1'b1;
      repeat (DebounceControle + 3) @(posedge clk);
    end
  endtask

  task test_modo_livre_midi;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      gpio_keys <= 7'b0000001;

      receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "LIVRE_NOTE_ON_C4");

      @(negedge clk);
      gpio_keys <= 7'b0000000;

      receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0}, "LIVRE_NOTE_OFF_C4");
      repeat (10) @(posedge clk);

      // Teste de alternancia rapida entre notas distintas: C4 -> D4
      // Deve enviar estritamente Note On(D4) sem disparar Note On fantasma de C4
      @(negedge clk);
      gpio_keys <= 7'b0000010; // Tecla D4

      receive_and_verify_midi_packet({8'h90, 8'd62, 8'd64}, "LIVRE_NOTE_ON_D4_SEM_FANTASMA");

      @(negedge clk);
      gpio_keys <= 7'b0000000;

      receive_and_verify_midi_packet({8'h80, 8'd62, 8'd0}, "LIVRE_NOTE_OFF_D4");
      repeat (10) @(posedge clk);
    end
  endtask

  task test_todas_notas_e_sustenidos_midi;
    integer k;
    reg [6:0] exp_nat[0:6];
    reg [6:0] exp_sharp[0:6];
    begin
      tests_run = tests_run + 1;
      setup();

      exp_nat[0] = 7'd60; // Do4
      exp_nat[1] = 7'd62; // Re4
      exp_nat[2] = 7'd64; // Mi4
      exp_nat[3] = 7'd65; // Fa4
      exp_nat[4] = 7'd67; // Sol4
      exp_nat[5] = 7'd69; // La4
      exp_nat[6] = 7'd71; // Si4

      exp_sharp[0] = 7'd61; // Do#4
      exp_sharp[1] = 7'd63; // Re#4
      exp_sharp[2] = 7'd65; // Mi#4 (Fa4)
      exp_sharp[3] = 7'd66; // Fa#4
      exp_sharp[4] = 7'd68; // Sol#4
      exp_sharp[5] = 7'd70; // La#4
      exp_sharp[6] = 7'd72; // Si#4 (Do5)

      // 1. Testa todas as 7 teclas naturais em Oitava 4
      for (k = 0; k < 7; k = k + 1) begin
        @(negedge clk);
        gpio_keys <= (7'b0000001 << k);
        receive_and_verify_midi_packet({8'h90, 1'b0, exp_nat[k], 8'd64}, "NAT_NOTE_ON");

        @(negedge clk);
        gpio_keys <= 7'b0000000;
        receive_and_verify_midi_packet({8'h80, 1'b0, exp_nat[k], 8'd0}, "NAT_NOTE_OFF");
        repeat (10) @(posedge clk);
      end

      // 2. Testa todas as 7 teclas com sustenido (#) em Oitava 4
      @(negedge clk);
      btn_sustenido <= 1'b1;
      repeat (5) @(posedge clk);

      for (k = 0; k < 7; k = k + 1) begin
        @(negedge clk);
        gpio_keys <= (7'b0000001 << k);
        receive_and_verify_midi_packet({8'h90, 1'b0, exp_sharp[k], 8'd64}, "SHARP_NOTE_ON");

        @(negedge clk);
        gpio_keys <= 7'b0000000;
        receive_and_verify_midi_packet({8'h80, 1'b0, exp_sharp[k], 8'd0}, "SHARP_NOTE_OFF");
        repeat (10) @(posedge clk);
      end

      @(negedge clk);
      btn_sustenido <= 1'b0;
      repeat (5) @(posedge clk);

      // 3. Testa mudanca de oitava acima (Oitava 5)
      press_btn_oitava_up();
      @(negedge clk);
      gpio_keys <= 7'b0000001; // Do5 = 72
      receive_and_verify_midi_packet({8'h90, 8'd72, 8'd64}, "OCT5_DO_NOTE_ON");
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd72, 8'd0}, "OCT5_DO_NOTE_OFF");
      repeat (10) @(posedge clk);

      // 4. Testa mudanca de oitava abaixo duas vezes (Oitava 3)
      press_btn_oitava_down(); // Volta para 4
      press_btn_oitava_down(); // Vai para 3
      @(negedge clk);
      gpio_keys <= 7'b0000001; // Do3 = 48
      receive_and_verify_midi_packet({8'h90, 8'd48, 8'd64}, "OCT3_DO_NOTE_ON");
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd48, 8'd0}, "OCT3_DO_NOTE_OFF");
      repeat (10) @(posedge clk);
    end
  endtask

  task test_gravacao_e_demonstracao_ram;
    integer idx;
    integer cyc;
    time    t_on1;
    time    t_off1;
    time    t_on2;
    time    t_off2;
    time    t_tick;
    begin
      tests_run = tests_run + 1;
      t_tick    = CiclosTick8ms * ClkPeriodNs;
      setup();

      for (idx = 0; idx < 42; idx = idx + 1) begin
        press_btn_musica();
      end

      press_btn_modo();
      press_btn_modo();

      // 1. Espera antes da 1a nota no Modo 2 NAO pode virar pausa apos a 1a nota
      repeat (5 * CiclosTick8ms) @(posedge clk);

      // 2. Grava 2 notas com duracoes distintas e pausa entre elas:
      // Nota 1 (C4): ~2 ticks; Pausa: ~3 ticks; Nota 2 (E4): ~5 ticks
      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "GRAV_N1_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "GRAV_N1_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd64, 8'd64}, "GRAV_N2_ON");
          receive_and_verify_midi_packet({8'h80, 8'd64, 8'd0},   "GRAV_N2_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 10) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat ((3 * CiclosTick8ms) + DebounceTecla + 10) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000100;
          repeat ((5 * CiclosTick8ms) + DebounceTecla + 10) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 4) @(posedge clk);
        end
      join

      press_btn_modo();

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "DEMO_RAM_N1_ON");
          t_on1 = $time;
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "DEMO_RAM_N1_OFF");
          t_off1 = $time;
          receive_and_verify_midi_packet({8'h90, 8'd64, 8'd64}, "DEMO_RAM_N2_ON");
          t_on2 = $time;
          receive_and_verify_midi_packet({8'h80, 8'd64, 8'd0},   "DEMO_RAM_N2_OFF");
          t_off2 = $time;

          if (((t_off1 - t_on1) < (2 * t_tick)) || ((t_off1 - t_on1) >= (4 * t_tick))) begin
            $display("[FALHA] %0t ns | DEMO_RAM_N1_DUR: esperado [2..4) ticks, obtido %0d ns",
              $time, (t_off1 - t_on1));
            errors = errors + 1;
          end
          if (((t_on2 - t_off1) < (3 * t_tick)) || ((t_on2 - t_off1) >= (5 * t_tick))) begin
            $display("[FALHA] %0t ns | DEMO_RAM_N1_PAUSA: esperado [3..5) ticks, obtido %0d ns",
              $time, (t_on2 - t_off1));
            errors = errors + 1;
          end
          if ((t_off2 - t_on2) < (5 * t_tick)) begin
            $display("[FALHA] %0t ns | DEMO_RAM_N2_DUR: esperado >= %0d ns, obtido %0d ns",
              $time, (5 * t_tick), (t_off2 - t_on2));
            errors = errors + 1;
          end
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (DebounceTecla + 3) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
        end
      join

      for (cyc = 0; cyc < (2 * CiclosTick8ms); cyc = cyc + 1) begin
        @(posedge clk);
        #1;
        if (saida_serial !== 1'b1) begin
          $display("[FALHA] %0t ns | DEMO_RAM_SILENCIO_POS_FIM: saida_serial=%b",
            $time, saida_serial);
          errors = errors + 1;
        end
      end
    end
  endtask

  task test_demonstracao_clair_de_lune_rom;
    integer idx;
    begin
      tests_run = tests_run + 1;
      setup();

      for (idx = 0; idx < 4; idx = idx + 1) begin
        press_btn_musica();
      end

      press_btn_modo();
      press_btn_modo();
      press_btn_modo();

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd67, 8'd53}, "CLAIR_DE_LUNE_N0_ON");
          receive_and_verify_midi_packet({8'h80, 8'd67, 8'd0},  "CLAIR_DE_LUNE_N0_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd79, 8'd67}, "CLAIR_DE_LUNE_N1_ON");
          receive_and_verify_midi_packet({8'h80, 8'd79, 8'd0},  "CLAIR_DE_LUNE_N1_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (DebounceTecla + 3) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
        end
      join

      begin
        repeat (20) @(posedge clk);
      end
    end
  endtask

  task receive_dashboard_uart_byte(
    output [7:0] rx_byte
  );
    integer bit_idx;
    begin
      @(negedge saida_serial_dashboard);
      repeat (ClockDivUart / 2) @(posedge clk);
      #1;
      if (saida_serial_dashboard !== 1'b0) begin
        $display("[FAIL] %0t ns | DASH_UART_START: exp 0b0, got 0b%0b",
          $time, saida_serial_dashboard);
        errors = errors + 1;
      end
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        repeat (ClockDivUart) @(posedge clk);
        #1;
        rx_byte[bit_idx] = saida_serial_dashboard;
      end
      repeat (ClockDivUart) @(posedge clk);
      #1;
      if (saida_serial_dashboard !== 1'b1) begin
        $display("[FAIL] %0t ns | DASH_UART_STOP: exp 0b1, got 0b%0b",
          $time, saida_serial_dashboard);
        errors = errors + 1;
      end
    end
  endtask

  task test_modo_aprendizado_acerto_erro;
    integer m_idx;
    integer note_idx;
    reg [2:0] expected_nota;
    reg [6:0] wrong_key;
    reg [6:0] correct_key;
    reg [7:0] d0;
    reg [7:0] d1;
    reg [7:0] d2;
    reg [7:0] d3;
    reg [7:0] d4;
    reg [7:0] d5;
    reg [7:0] d6;
    begin
      tests_run = tests_run + 1;
      setup();

      // Seleciona Musica 6: Do_Re_Mi_Fa (offset 799 na ROM: Do, Re, Mi, Fa, Sol, La, Si)
      for (m_idx = 0; m_idx < 6; m_idx = m_idx + 1) begin
        press_btn_musica();
      end

      // Entra no Modo 1 (Aprendizado)
      press_btn_modo();
      repeat (DebounceControle + 10) @(posedge clk);

      expected_nota = piano_top_inst.fluxo_dados_inst.s_nota_esperada;

      // Na musica 6, a primeira nota e Do (nota_id = 1)
      if (expected_nota == 3'd1) begin
        correct_key = 7'b0000001; // Do
        wrong_key   = 7'b0000010; // Re (erro)
      end else begin
        correct_key = (7'b0000001 << (expected_nota - 3'd1));
        wrong_key   = 7'b0000010;
      end

      // 1. Toca nota errada
      @(negedge clk);
      gpio_keys <= wrong_key;
      repeat (DebounceTecla + 20) @(posedge clk);

      // Deve ter incrementado erros para 1 e mantido acertos em 0
      if (piano_top_inst.fluxo_dados_inst.contador_m_erros.q !== 8'd1) begin
        $display("[FALHA] %0t ns | TESTE_APRENDIZADO_ERRO: esperado erros=1, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.contador_m_erros.q);
        errors = errors + 1;
      end
      if (piano_top_inst.fluxo_dados_inst.contador_m_acertos.q !== 8'd0) begin
        $display("[FALHA] %0t ns | TESTE_APRENDIZADO_ERRO: esperado acertos=0, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.contador_m_acertos.q);
        errors = errors + 1;
      end

      // Solta tecla errada
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      repeat (DebounceTecla + 20) @(posedge clk);

      // 2. Toca primeira nota correta (Do)
      @(negedge clk);
      gpio_keys <= correct_key;
      repeat (DebounceTecla + 20) @(posedge clk);

      // Deve ter incrementado acertos para 1
      if (piano_top_inst.fluxo_dados_inst.contador_m_acertos.q !== 8'd1) begin
        $display("[FALHA] %0t ns | TESTE_APRENDIZADO_ACERTO: esperado acertos=1, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.contador_m_acertos.q);
        errors = errors + 1;
      end

      // Solta tecla correta
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      repeat (DebounceTecla + 20) @(posedge clk);

      // 3. Toca notas restantes da escala (Re..Si) e valida pacote UART do dashboard
      fork
        begin
          receive_dashboard_uart_byte(d0);
          receive_dashboard_uart_byte(d1);
          receive_dashboard_uart_byte(d2);
          receive_dashboard_uart_byte(d3);
          receive_dashboard_uart_byte(d4);
          receive_dashboard_uart_byte(d5);
          receive_dashboard_uart_byte(d6);
        end
        begin
          for (note_idx = 1; note_idx < 7; note_idx = note_idx + 1) begin
            @(negedge clk);
            gpio_keys <= (7'b0000001 << note_idx);
            repeat (DebounceTecla + 20) @(posedge clk);
            @(negedge clk);
            gpio_keys <= 7'b0000000;
            repeat (DebounceTecla + 20) @(posedge clk);
          end
        end
      join

      if ({d0, d1, d2, d3, d4, d5, d6} !==
          {8'hAA, 8'hD1, 8'h06, 8'd7, 8'd1, 8'd46, 8'h0D}) begin
        $display("[FAIL] %0t ns | DASH_RUSH: exp AAD10607012E0D, got %02h%02h%02h%02h%02h%02h%02h",
          $time, d0, d1, d2, d3, d4, d5, d6);
        errors = errors + 1;
      end

      // 4. Verifica reinicio automatico do Modo 1 (endereco=0, acertos=0, erros=0)
      repeat (20) @(posedge clk);
      if (piano_top_inst.fsm_modo_ativo !== 2'd1) begin
        $display("[FALHA] %0t ns | AUTO_RESTART_MODO: esperado 1, obtido %0d",
          $time, piano_top_inst.fsm_modo_ativo);
        errors = errors + 1;
      end
      if (piano_top_inst.fluxo_dados_inst.s_endereco_ram !== 10'd0) begin
        $display("[FALHA] %0t ns | AUTO_RESTART_ADDR: esperado 0, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.s_endereco_ram);
        errors = errors + 1;
      end
      if ((piano_top_inst.fluxo_dados_inst.acertos !== 8'd0) ||
          (piano_top_inst.fluxo_dados_inst.erros !== 8'd0) ||
          (piano_top_inst.fluxo_dados_inst.pontos_apre !== 10'd0)) begin
        $display("[FALHA] %0t ns | AUTO_RESTART_CONTADORES: a=%0d e=%0d p=%0d",
          $time, piano_top_inst.fluxo_dados_inst.acertos,
          piano_top_inst.fluxo_dados_inst.erros,
          piano_top_inst.fluxo_dados_inst.pontos_apre);
        errors = errors + 1;
      end

      // 5. Reexecucao no tempo certo (40 ticks nota, 5 ticks pausa) -> score 100%
      fork
        begin
          receive_dashboard_uart_byte(d0);
          receive_dashboard_uart_byte(d1);
          receive_dashboard_uart_byte(d2);
          receive_dashboard_uart_byte(d3);
          receive_dashboard_uart_byte(d4);
          receive_dashboard_uart_byte(d5);
          receive_dashboard_uart_byte(d6);
        end
        begin
          for (note_idx = 0; note_idx < 7; note_idx = note_idx + 1) begin
            @(negedge clk);
            gpio_keys <= (7'b0000001 << note_idx);
            repeat ((40 * CiclosTick8ms) + DebounceTecla + 10) @(posedge clk);
            @(negedge clk);
            gpio_keys <= 7'b0000000;
            repeat ((5 * CiclosTick8ms) + DebounceTecla + 10) @(posedge clk);
          end
        end
      join

      if ({d0, d1, d2, d3, d4, d5, d6} !==
          {8'hAA, 8'hD1, 8'h06, 8'd7, 8'd0, 8'd100, 8'h42}) begin
        $display("[FAIL] %0t ns | DASH_100: exp AAD10607006442, got %02h%02h%02h%02h%02h%02h%02h",
          $time, d0, d1, d2, d3, d4, d5, d6);
        errors = errors + 1;
      end
    end
  endtask

  task test_cenario_geral_ponta_a_ponta_semana4;
    integer m_idx;
    integer note_idx;
    integer stim_idx;
    time    t_on;
    time    t_off;
    reg [6:0] exp_notes[0:6];
    reg [7:0] d0;
    reg [7:0] d1;
    reg [7:0] d2;
    reg [7:0] d3;
    reg [7:0] d4;
    reg [7:0] d5;
    reg [7:0] d6;
    begin
      tests_run = tests_run + 1;
      setup();

      exp_notes[0] = 7'd60; // Do4
      exp_notes[1] = 7'd62; // Re4
      exp_notes[2] = 7'd64; // Mi4
      exp_notes[3] = 7'd65; // Fa4
      exp_notes[4] = 7'd67; // Sol4
      exp_notes[5] = 7'd69; // La4
      exp_notes[6] = 7'd71; // Si4

      // =======================================================================
      // Etapa 1: Modo 0 Livre + Controle de Oitava por Ultrassom HC-SR04 + MIDI
      // =======================================================================
      // Ativa modo sensor por combo simultaneo (subir + descer oitava)
      @(negedge clk);
      btn_oitava_up_n   <= 1'b0;
      btn_oitava_down_n <= 1'b0;
      repeat (DebounceControle + 4) @(posedge clk);
      @(negedge clk);
      btn_oitava_up_n   <= 1'b1;
      btn_oitava_down_n <= 1'b1;
      repeat (DebounceControle + 4) @(posedge clk);

      // Evita race condition caso hcsr04_trigger ja tenha subido durante o pulso
      if (hcsr04_trigger !== 1'b1) begin
        @(posedge hcsr04_trigger);
      end
      @(negedge hcsr04_trigger);

      repeat (5) @(posedge clk);
      @(negedge clk);
      hcsr04_echo <= 1'b1;
      repeat (15 * 2941) @(posedge clk);
      @(negedge clk);
      hcsr04_echo <= 1'b0;
      repeat (10) @(posedge clk);

      if (hex4_oitava !== 7'b0000010) begin
        $display("[FALHA] %0t ns | HCSR04_HEX4: esperado 7'b0000010, obtido %b",
          $time, hex4_oitava);
        errors = errors + 1;
      end
      if (piano_top_inst.fluxo_dados_inst.oitava_atual !== 3'd6) begin
        $display("[FALHA] %0t ns | HCSR04_OITAVA: esperado 6, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.oitava_atual);
        errors = errors + 1;
      end
      if (piano_top_inst.metronomo_inst.habilita !== 1'b0) begin
        $display("[FALHA] %0t ns | METRONOMO_MODO0: esperado 0, obtido %b",
          $time, piano_top_inst.metronomo_inst.habilita);
        errors = errors + 1;
      end

      // Pressiona Do na oitava 6 (MIDI 84 = 24'h905440)
      @(negedge clk);
      gpio_keys <= 7'b0000001;
      receive_and_verify_midi_packet({8'h90, 8'd84, 8'd64}, "HCSR04_OCT6_DO_NOTE_ON");

      // Verifica que o trigger nao dispara imediatamente apos o fim do echo (cooldown)
      repeat (200) begin
        @(posedge clk);
        if (hcsr04_trigger === 1'b1) begin
          $display("[FALHA] %0t ns | HCSR04_COOLDOWN: trigger disparou sem intervalo minimo",
            $time);
          errors = errors + 1;
        end
      end

      // Aguarda proximo trigger apos cooldown e simula nova distancia (35 cm -> oitava 4)
      // com a tecla ainda pressionada; a oitava deve permanecer travada em 6 ate soltar.
      wait (hcsr04_trigger === 1'b1);
      @(negedge hcsr04_trigger);
      repeat (5) @(posedge clk);
      @(negedge clk);
      hcsr04_echo <= 1'b1;
      repeat (35 * 2941) @(posedge clk);
      @(negedge clk);
      hcsr04_echo <= 1'b0;
      repeat (10) @(posedge clk);

      if (piano_top_inst.fluxo_dados_inst.oitava_atual !== 3'd6) begin
        $display("[FALHA] %0t ns | HCSR04_TRAVA_OITAVA: esperado 6, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.oitava_atual);
        errors = errors + 1;
      end

      // Solta tecla Do (24'h805400) e verifica que a oitava atualiza para 4
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd84, 8'd0}, "HCSR04_OCT6_DO_NOTE_OFF");
      repeat (10) @(posedge clk);

      if (piano_top_inst.fluxo_dados_inst.oitava_atual !== 3'd4) begin
        $display("[FALHA] %0t ns | HCSR04_DESTRAVA_OITAVA: esperado 4, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.oitava_atual);
        errors = errors + 1;
      end

      // Repete o combo de botoes para desativar o modo sensor (retorna oitava 4)
      @(negedge clk);
      btn_oitava_up_n   <= 1'b0;
      btn_oitava_down_n <= 1'b0;
      repeat (DebounceControle + 4) @(posedge clk);
      @(negedge clk);
      btn_oitava_up_n   <= 1'b1;
      btn_oitava_down_n <= 1'b1;
      repeat (DebounceControle + 4) @(posedge clk);

      if (hex4_oitava !== 7'b0011001) begin
        $display("[FALHA] %0t ns | DESATIVA_HCSR04_HEX4: esperado 7'b0011001, obtido %b",
          $time, hex4_oitava);
        errors = errors + 1;
      end
      if (piano_top_inst.fluxo_dados_inst.oitava_atual !== 3'd4) begin
        $display("[FALHA] %0t ns | DESATIVA_HCSR04_OITAVA: esperado 4, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.oitava_atual);
        errors = errors + 1;
      end

      // =======================================================================
      // Etapa 2: Modo 1 Aprendizado + Metronomo Servo + Audio MIDI + Dashboard
      // =======================================================================
      for (m_idx = 0; m_idx < 6; m_idx = m_idx + 1) begin
        press_btn_musica();
      end

      press_btn_modo();
      repeat (DebounceControle + 10) @(posedge clk);

      if (piano_top_inst.fsm_modo_ativo !== 2'd1) begin
        $display("[FALHA] %0t ns | MODO1_ATIVO: esperado 1, obtido %0d",
          $time, piano_top_inst.fsm_modo_ativo);
        errors = errors + 1;
      end
      if (piano_top_inst.metronomo_inst.habilita !== 1'b1) begin
        $display("[FALHA] %0t ns | METRONOMO_HAB: esperado 1, obtido %b",
          $time, piano_top_inst.metronomo_inst.habilita);
        errors = errors + 1;
      end
      if (servo_controle === 1'bx) begin
        $display("[FALHA] %0t ns | SERVO_X: servo_controle e indefinido (X)", $time);
        errors = errors + 1;
      end
      if (piano_top_inst.metronomo_inst.posicao_servo !== 3'd3) begin
        $display("[FALHA] %0t ns | METRONOMO_POS_INI: esperado 3, obtido %0d",
          $time, piano_top_inst.metronomo_inst.posicao_servo);
        errors = errors + 1;
      end
      if (piano_top_inst.metronomo_inst.metronomo_uc_inst.state_reg === 2'd0) begin
        $display("[FALHA] %0t ns | METRONOMO_STATE: esperado != 0, obtido %0d",
          $time, piano_top_inst.metronomo_inst.metronomo_uc_inst.state_reg);
        errors = errors + 1;
      end

      fork
        // Branch 1: Audio MIDI (saida_serial)
        begin
          // Nota errada (Re4 = 62)
          receive_and_verify_midi_packet({8'h90, 8'd62, 8'd64}, "M1_WRONG_NOTE_ON");
          receive_and_verify_midi_packet({8'h80, 8'd62, 8'd0},   "M1_WRONG_NOTE_OFF");

          // 7 notas corretas da escala Do_Re_Mi_Fa (Do4..Si4)
          for (note_idx = 0; note_idx < 7; note_idx = note_idx + 1) begin
            receive_and_verify_midi_packet(
              {8'h90, 1'b0, exp_notes[note_idx], 8'd64}, "M1_SCALE_NOTE_ON");
            receive_and_verify_midi_packet(
              {8'h80, 1'b0, exp_notes[note_idx], 8'd0},   "M1_SCALE_NOTE_OFF");
          end
        end

        // Branch 2: Dashboard UART (saida_serial_dashboard)
        begin
          receive_dashboard_uart_byte(d0);
          receive_dashboard_uart_byte(d1);
          receive_dashboard_uart_byte(d2);
          receive_dashboard_uart_byte(d3);
          receive_dashboard_uart_byte(d4);
          receive_dashboard_uart_byte(d5);
          receive_dashboard_uart_byte(d6);
        end

        // Branch 3: Estimulos de teclado
        begin
          // Toca nota errada: Re (7'b0000010)
          @(negedge clk);
          gpio_keys <= 7'b0000010;
          repeat (160) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat (160) @(posedge clk);

          // Toca as 7 notas corretas da escala
          for (stim_idx = 0; stim_idx < 7; stim_idx = stim_idx + 1) begin
            @(negedge clk);
            gpio_keys <= (7'b0000001 << stim_idx);
            repeat (160) @(posedge clk);
            @(negedge clk);
            gpio_keys <= 7'b0000000;
            repeat (160) @(posedge clk);
          end
        end
      join

      if ({d0, d1, d2, d3, d4, d5, d6} !==
          {8'hAA, 8'hD1, 8'h06, 8'd7, 8'd1, 8'd46, 8'h0D}) begin
        $display("[FAIL] %0t ns | S4_RUSH: exp AAD10607012E0D, got %02h%02h%02h%02h%02h%02h%02h",
          $time, d0, d1, d2, d3, d4, d5, d6);
        errors = errors + 1;
      end

      // Verifica reinicio automatico e nova execucao com ritmo perfeito (100%)
      repeat (20) @(posedge clk);
      if ((piano_top_inst.fsm_modo_ativo !== 2'd1) ||
          (piano_top_inst.fluxo_dados_inst.s_endereco_ram !== 10'd0) ||
          (piano_top_inst.fluxo_dados_inst.acertos !== 8'd0) ||
          (piano_top_inst.fluxo_dados_inst.erros !== 8'd0)) begin
        $display("[FALHA] %0t ns | SEMANA4_AUTO_RESTART: modo=%0d addr=%0d a=%0d e=%0d",
          $time, piano_top_inst.fsm_modo_ativo,
          piano_top_inst.fluxo_dados_inst.s_endereco_ram,
          piano_top_inst.fluxo_dados_inst.acertos,
          piano_top_inst.fluxo_dados_inst.erros);
        errors = errors + 1;
      end

      fork
        begin
          for (note_idx = 0; note_idx < 7; note_idx = note_idx + 1) begin
            receive_and_verify_midi_packet(
              {8'h90, 1'b0, exp_notes[note_idx], 8'd64}, "M1_PERFECT_ON");
            receive_and_verify_midi_packet(
              {8'h80, 1'b0, exp_notes[note_idx], 8'd0},   "M1_PERFECT_OFF");
          end
        end
        begin
          receive_dashboard_uart_byte(d0);
          receive_dashboard_uart_byte(d1);
          receive_dashboard_uart_byte(d2);
          receive_dashboard_uart_byte(d3);
          receive_dashboard_uart_byte(d4);
          receive_dashboard_uart_byte(d5);
          receive_dashboard_uart_byte(d6);
        end
        begin
          for (stim_idx = 0; stim_idx < 7; stim_idx = stim_idx + 1) begin
            @(negedge clk);
            gpio_keys <= (7'b0000001 << stim_idx);
            repeat ((40 * CiclosTick8ms) + DebounceTecla + 10) @(posedge clk);
            @(negedge clk);
            gpio_keys <= 7'b0000000;
            repeat ((5 * CiclosTick8ms) + DebounceTecla + 10) @(posedge clk);
          end
        end
      join

      if ({d0, d1, d2, d3, d4, d5, d6} !==
          {8'hAA, 8'hD1, 8'h06, 8'd7, 8'd0, 8'd100, 8'h42}) begin
        $display("[FAIL] %0t ns | S4_100: exp AAD10607006442, got %02h%02h%02h%02h%02h%02h%02h",
          $time, d0, d1, d2, d3, d4, d5, d6);
        errors = errors + 1;
      end

      // =======================================================================
      // Etapa 3: Modo 2 Gravacao em RAM M10K
      // =======================================================================
      for (m_idx = 0; m_idx < 36; m_idx = m_idx + 1) begin
        press_btn_musica();
      end

      press_btn_modo();
      repeat (DebounceControle + 10) @(posedge clk);

      if (piano_top_inst.fsm_modo_ativo !== 2'd2) begin
        $display("[FALHA] %0t ns | MODO2_ATIVO: esperado 2, obtido %0d",
          $time, piano_top_inst.fsm_modo_ativo);
        errors = errors + 1;
      end
      if (piano_top_inst.metronomo_inst.habilita !== 1'b0) begin
        $display("[FALHA] %0t ns | METRONOMO_MODO2: esperado 0, obtido %b",
          $time, piano_top_inst.metronomo_inst.habilita);
        errors = errors + 1;
      end

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "SEMANA4_GRAV_NOTE_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "SEMANA4_GRAV_NOTE_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 4) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 4) @(posedge clk);
        end
      join

      // =======================================================================
      // Etapa 4: Modo 3 Demonstracao + Retorno Ciclico ao Modo 0
      // =======================================================================
      press_btn_modo();
      repeat (DebounceControle + 10) @(posedge clk);

      if (piano_top_inst.fsm_modo_ativo !== 2'd3) begin
        $display("[FALHA] %0t ns | MODO3_ATIVO: esperado 3, obtido %0d",
          $time, piano_top_inst.fsm_modo_ativo);
        errors = errors + 1;
      end

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "SEMANA4_DEMO_NOTE_ON");
          t_on = $time;
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "SEMANA4_DEMO_NOTE_OFF");
          t_off = $time;
          if ((t_off - t_on) < (2 * CiclosTick8ms * ClkPeriodNs)) begin
            $display("[FALHA] %0t ns | SEMANA4_DEMO_DURATION: exp >= %0d ns, obtido %0d ns",
              $time, (2 * CiclosTick8ms * ClkPeriodNs), (t_off - t_on));
            errors = errors + 1;
          end
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (DebounceTecla + 3) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
        end
      join

      repeat (20) @(posedge clk);
      press_btn_modo();
      repeat (DebounceControle + 10) @(posedge clk);

      if (piano_top_inst.fsm_modo_ativo !== 2'd0) begin
        $display("[FALHA] %0t ns | RETORNO_MODO0: esperado 0, obtido %0d",
          $time, piano_top_inst.fsm_modo_ativo);
        errors = errors + 1;
      end
    end
  endtask

  task test_gravacao_legato_e_persistencia_ram;
    integer idx;
    integer cyc;
    begin
      tests_run = tests_run + 1;
      setup();

      for (idx = 0; idx < 42; idx = idx + 1) begin
        press_btn_musica();
      end

      // Entra no Modo 2 e testa legato C4 -> C4+E4 -> C4 -> soltar (grava 60 -> 64 -> 60)
      press_btn_modo();
      press_btn_modo();

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "LEGATO_M2_N0_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "LEGATO_M2_N0_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd64, 8'd64}, "LEGATO_M2_N1_ON");
          receive_and_verify_midi_packet({8'h80, 8'd64, 8'd0},   "LEGATO_M2_N1_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "LEGATO_M2_N2_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "LEGATO_M2_N2_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000101;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat (DebounceTecla + 20) @(posedge clk);
        end
      join

      if (piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg !== 10'd2) begin
        $display("[FALHA] %0t ns | LEGATO_ULT_END: esperado 2, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg);
        errors = errors + 1;
      end

      // Reproduz no Modo 3 e verifica as 3 notas ligadas
      press_btn_modo();
      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "LEGATO_M3_N0_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "LEGATO_M3_N0_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd64, 8'd64}, "LEGATO_M3_N1_ON");
          receive_and_verify_midi_packet({8'h80, 8'd64, 8'd0},   "LEGATO_M3_N1_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "LEGATO_M3_N2_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "LEGATO_M3_N2_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (DebounceTecla + 3) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
        end
      join
      repeat (CiclosTick8ms) @(posedge clk);

      // Persistencia da RAM entre ciclos de modo (3 -> 0 -> 1 -> 2 -> 3) sem tocar no Modo 2
      press_btn_modo();
      press_btn_modo();
      press_btn_modo();
      repeat (50) @(posedge clk);
      if (piano_top_inst.fluxo_dados_inst.grav_tem_dados_reg !== 1'b1) begin
        $display("[FALHA] %0t ns | RAM_PERSIST_FLAG: esperado 1, obtido %b",
          $time, piano_top_inst.fluxo_dados_inst.grav_tem_dados_reg);
        errors = errors + 1;
      end
      press_btn_modo();

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "PERSIST_M3_N0_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "PERSIST_M3_N0_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd64, 8'd64}, "PERSIST_M3_N1_ON");
          receive_and_verify_midi_packet({8'h80, 8'd64, 8'd0},   "PERSIST_M3_N1_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "PERSIST_M3_N2_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "PERSIST_M3_N2_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (DebounceTecla + 3) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
        end
      join
      repeat (CiclosTick8ms) @(posedge clk);

      // Sobrescrita apenas ao tocar nova sequencia no Modo 2 (C4 -> C4+E4 -> E4 -> soltar = 60, 64)
      press_btn_modo();
      press_btn_modo();
      press_btn_modo();

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "OVERWRITE_M2_N0_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "OVERWRITE_M2_N0_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd64, 8'd64}, "OVERWRITE_M2_N1_ON");
          receive_and_verify_midi_packet({8'h80, 8'd64, 8'd0},   "OVERWRITE_M2_N1_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (CiclosTick8ms + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000101;
          repeat (CiclosTick8ms + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000100;
          repeat (CiclosTick8ms + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat (DebounceTecla + 20) @(posedge clk);
        end
      join

      if (piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg !== 10'd1) begin
        $display("[FALHA] %0t ns | OVERWRITE_ULT_END: esperado 1, obtido %0d",
          $time, piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg);
        errors = errors + 1;
      end

      press_btn_modo();
      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "OVERWRITE_M3_N0_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "OVERWRITE_M3_N0_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd64, 8'd64}, "OVERWRITE_M3_N1_ON");
          receive_and_verify_midi_packet({8'h80, 8'd64, 8'd0},   "OVERWRITE_M3_N1_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (DebounceTecla + 3) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
        end
      join

      for (cyc = 0; cyc < (2 * CiclosTick8ms); cyc = cyc + 1) begin
        @(posedge clk);
        #1;
        if (saida_serial !== 1'b1) begin
          $display("[FALHA] %0t ns | OVERWRITE_SEM_RESTO_ANTIGO: saida_serial=%b",
            $time, saida_serial);
          errors = errors + 1;
        end
      end
    end
  endtask

  task check_vol_hex(
    input [6:0]   exp_hex5,
    input [6:0]   exp_hex4,
    input [6:0]   exp_hex3,
    input [6:0]   exp_hex2,
    input [255:0] tag
  );
    begin
      if (hex5_modo !== exp_hex5 || hex4_oitava !== exp_hex4 ||
          hex3_musica_dezena !== exp_hex3 || hex2_musica_unidade !== exp_hex2) begin
        $display("[FALHA] %0t ns | %0s: HEX esperados (%h,%h,%h,%h), obtidos (%h,%h,%h,%h)",
          $time, tag, exp_hex5, exp_hex4, exp_hex3, exp_hex2,
          hex5_modo, hex4_oitava, hex3_musica_dezena, hex2_musica_unidade);
        errors = errors + 1;
      end
    end
  endtask

  task test_volume_cinco_niveis;
    integer idx;
    integer cyc;
    begin
      tests_run = tests_run + 1;
      setup();

      // 1. Testa 5 niveis no Modo 0 (100%, 75%, 50%, 25%, 0% mudo) e retorno a 100%
      @(negedge clk);
      gpio_keys <= 7'b0000001;
      receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "VOL_100_M0_ON");
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0}, "VOL_100_M0_OFF");
      repeat (10) @(posedge clk);

      press_combo_volume();
      check_vol_hex(7'h7F, 7'h78, 7'h12, 7'h0C, "VOL_HEX_75P");
      @(negedge clk);
      gpio_keys <= 7'b0000001;
      receive_and_verify_midi_packet({8'h90, 8'd60, 8'd48}, "VOL_75_M0_ON");
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0}, "VOL_75_M0_OFF");
      repeat (10) @(posedge clk);

      press_combo_volume();
      check_vol_hex(7'h7F, 7'h12, 7'h40, 7'h0C, "VOL_HEX_50P");
      @(negedge clk);
      gpio_keys <= 7'b0000001;
      receive_and_verify_midi_packet({8'h90, 8'd60, 8'd32}, "VOL_50_M0_ON");
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0}, "VOL_50_M0_OFF");
      repeat (10) @(posedge clk);

      press_combo_volume();
      check_vol_hex(7'h7F, 7'h24, 7'h12, 7'h0C, "VOL_HEX_25P");
      @(negedge clk);
      gpio_keys <= 7'b0000001;
      receive_and_verify_midi_packet({8'h90, 8'd60, 8'd16}, "VOL_25_M0_ON");
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0}, "VOL_25_M0_OFF");
      repeat (10) @(posedge clk);

      press_combo_volume();
      check_vol_hex(7'h7F, 7'h7F, 7'h40, 7'h0C, "VOL_HEX_0P");
      @(negedge clk);
      gpio_keys <= 7'b0000001;
      for (cyc = 0; cyc < 200; cyc = cyc + 1) begin
        @(posedge clk);
        #1;
        if (saida_serial !== 1'b1) begin
          $display("[FALHA] %0t ns | VOL_0_M0_MUDO_ON: saida_serial=%b", $time, saida_serial);
          errors = errors + 1;
        end
      end
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      for (cyc = 0; cyc < 200; cyc = cyc + 1) begin
        @(posedge clk);
        #1;
        if (saida_serial !== 1'b1) begin
          $display("[FALHA] %0t ns | VOL_0_M0_MUDO_OFF: saida_serial=%b", $time, saida_serial);
          errors = errors + 1;
        end
      end

      press_combo_volume();
      check_vol_hex(7'h79, 7'h40, 7'h40, 7'h0C, "VOL_HEX_100P");

      // 2. Testa 25% e 0% (mudo) no Modo Demonstracao (Modo 3)
      for (idx = 0; idx < 42; idx = idx + 1) begin
        press_btn_musica();
      end
      press_btn_modo();
      press_btn_modo();

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "VOL_DEMO_REC_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "VOL_DEMO_REC_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 4) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat (DebounceTecla + 10) @(posedge clk);
        end
      join

      press_btn_modo();
      press_combo_volume();
      press_combo_volume();
      press_combo_volume();

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd16}, "VOL_DEMO_25_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},  "VOL_DEMO_25_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (DebounceTecla + 3) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
        end
      join
      repeat (CiclosTick8ms) @(posedge clk);

      press_combo_volume();
      @(negedge clk);
      gpio_keys <= 7'b0000001;
      repeat (DebounceTecla + 3) @(posedge clk);
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      for (cyc = 0; cyc < (5 * CiclosTick8ms); cyc = cyc + 1) begin
        @(posedge clk);
        #1;
        if (saida_serial !== 1'b1) begin
          $display("[FALHA] %0t ns | VOL_DEMO_0_MUDO: saida_serial=%b", $time, saida_serial);
          errors = errors + 1;
        end
      end
    end
  endtask

  task test_gravacao_limite_ram_1023;
    integer idx;
    integer cyc;
    begin
      tests_run = tests_run + 1;
      setup();

      for (idx = 0; idx < 42; idx = idx + 1) begin
        press_btn_musica();
      end
      press_btn_modo();
      press_btn_modo();

      // 1. Grava Do4 (60) no endereco 0 para validar nao-sobrescrita
      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd64}, "LIM_N0_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "LIM_N0_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat (DebounceTecla + 15) @(posedge clk);
        end
      join

      if ((piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[0][6:0] !== 7'd60) ||
          (piano_top_inst.fluxo_dados_inst.s_endereco_ram !== 10'd1) ||
          (piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg !== 10'd0)) begin
        $display("[FALHA] %0t ns | LIM_ADDR0: ram0=%0d addr=%0d ult=%0d",
          $time,
          piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[0][6:0],
          piano_top_inst.fluxo_dados_inst.s_endereco_ram,
          piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg);
        errors = errors + 1;
      end

      // 2. Avanca para 1022 e grava Sol4 (67), avancando s_endereco_ram para 1023
      @(negedge clk);
      piano_top_inst.fluxo_dados_inst.contador_m_addr.q = 10'd1022;
      @(posedge clk);
      #1;

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd67, 8'd64}, "LIM_1022_ON");
          receive_and_verify_midi_packet({8'h80, 8'd67, 8'd0},   "LIM_1022_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0010000;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat (DebounceTecla + 15) @(posedge clk);
        end
      join

      if ((piano_top_inst.fluxo_dados_inst.s_endereco_ram !== 10'd1023) ||
          (piano_top_inst.fluxo_dados_inst.fim_musica !== 1'b1) ||
          (piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg !== 10'd1022) ||
          (piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[1022][6:0] !== 7'd67)) begin
        $display("[FALHA] %0t ns | LIM_POS_1022: addr=%0d fim=%b ult=%0d ram1022=%0d",
          $time,
          piano_top_inst.fluxo_dados_inst.s_endereco_ram,
          piano_top_inst.fluxo_dados_inst.fim_musica,
          piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg,
          piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[1022][6:0]);
        errors = errors + 1;
      end

      // 3. Tenta pressionar La4 (69) em 1023: nao deve gravar, dar wrap ou corromper RAM
      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd69, 8'd64}, "LIM_FULL_LA4_ON");
          receive_and_verify_midi_packet({8'h80, 8'd69, 8'd0},   "LIM_FULL_LA4_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0100000;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat (DebounceTecla + 15) @(posedge clk);
        end
      join

      if ((piano_top_inst.fluxo_dados_inst.s_endereco_ram !== 10'd1023) ||
          (piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg !== 10'd1022) ||
          (piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[0][6:0] !== 7'd60) ||
          (piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[1022][29:22] !== 8'd0) ||
          (piano_top_inst.unidade_controle_inst.state_reg !== 5'd9)) begin
        $display("[FALHA] %0t ns | LIM_1023_GUARD: addr=%0d ult=%0d r0=%0d p1022=%0d st=%0d",
          $time,
          piano_top_inst.fluxo_dados_inst.s_endereco_ram,
          piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg,
          piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[0][6:0],
          piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[1022][29:22],
          piano_top_inst.unidade_controle_inst.state_reg);
        errors = errors + 1;
      end

      // 4. Testa troca_nota_grav ao cruzar 1022 -> 1023: retorna a kGravEsperaNota sem wrap
      @(negedge clk);
      piano_top_inst.fluxo_dados_inst.contador_m_addr.q = 10'd1022;
      @(posedge clk);
      #1;

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd67, 8'd64}, "LIM_TROCA_SOL4_ON");
          receive_and_verify_midi_packet({8'h80, 8'd67, 8'd0},   "LIM_TROCA_SOL4_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd69, 8'd64}, "LIM_TROCA_LA4_ON");
          receive_and_verify_midi_packet({8'h80, 8'd69, 8'd0},   "LIM_TROCA_LA4_OFF");
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0010000;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0110000;
          repeat ((2 * CiclosTick8ms) + DebounceTecla + 5) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
          repeat (DebounceTecla + 15) @(posedge clk);
        end
      join

      if ((piano_top_inst.fluxo_dados_inst.s_endereco_ram !== 10'd1023) ||
          (piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg !== 10'd1022) ||
          (piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[0][6:0] !== 7'd60) ||
          (piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[1022][6:0] !== 7'd67) ||
          (piano_top_inst.unidade_controle_inst.state_reg !== 5'd9)) begin
        $display("[FALHA] %0t ns | LIM_TROCA_GUARD: addr=%0d ult=%0d r0=%0d r1022=%0d st=%0d",
          $time,
          piano_top_inst.fluxo_dados_inst.s_endereco_ram,
          piano_top_inst.fluxo_dados_inst.ultimo_end_gravado_reg,
          piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[0][6:0],
          piano_top_inst.fluxo_dados_inst.sync_ram_gravacao.ram[1022][6:0],
          piano_top_inst.unidade_controle_inst.state_reg);
        errors = errors + 1;
      end

      // 5. Modo 3 Demo a partir de 1022 toca Sol4 (67) e para em 1023 (fim_musica=1)
      press_btn_modo();
      fork
        begin
          wait (piano_top_inst.unidade_controle_inst.state_reg == 5'd13);
          @(negedge clk);
          piano_top_inst.fluxo_dados_inst.contador_m_addr.q = 10'd1022;
          receive_and_verify_midi_packet({8'h90, 8'd67, 8'd64}, "LIM_DEMO_1022_ON");
          receive_and_verify_midi_packet({8'h80, 8'd67, 8'd0},   "LIM_DEMO_1022_OFF");
        end
        begin
          wait (piano_top_inst.fluxo_dados_inst.s_endereco_ram == 10'd1023);
          #1;
          if (piano_top_inst.fluxo_dados_inst.fim_musica !== 1'b1) begin
            $display("[FALHA] %0t ns | LIM_DEMO_FIM_1023: fim_musica=%b",
              $time, piano_top_inst.fluxo_dados_inst.fim_musica);
            errors = errors + 1;
          end
          wait (piano_top_inst.unidade_controle_inst.state_reg == 5'd15);
        end
        begin
          @(negedge clk);
          gpio_keys <= 7'b0000001;
          repeat (DebounceTecla + 3) @(posedge clk);
          @(negedge clk);
          gpio_keys <= 7'b0000000;
        end
      join

      for (cyc = 0; cyc < (2 * CiclosTick8ms); cyc = cyc + 1) begin
        @(posedge clk);
        #1;
        if (saida_serial !== 1'b1) begin
          $display("[FALHA] %0t ns | LIM_DEMO_SILENCIO: saida_serial=%b",
            $time, saida_serial);
          errors = errors + 1;
        end
      end
    end
  endtask

  initial begin
    $display("INICIANDO SIMULACAO: piano_top_tb");

    test_modo_livre_midi();
    test_todas_notas_e_sustenidos_midi();
    test_modo_aprendizado_acerto_erro();
    test_gravacao_e_demonstracao_ram();
    test_gravacao_legato_e_persistencia_ram();
    test_gravacao_limite_ram_1023();
    test_volume_cinco_niveis();
    test_demonstracao_clair_de_lune_rom();
    test_cenario_geral_ponta_a_ponta_semana4();

    #100;
    $display("RESUMO DOS TESTES");
    $display("Testes executados: %0d", tests_run);
    $display("Erros encontrados: %0d", errors);
    if (errors == 0) begin
      $display("RESULT: ALL TESTS PASSED! (Tests: %0d)", tests_run);
    end else begin
      $display("RESULT: TESTBENCH FAILED! Errors: %0d", errors);
    end

    $finish;
  end

endmodule

`default_nettype wire
