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
  localparam WatchdogMaxNs    = 20_000_000;

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

  task test_modo_livre_midi;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      gpio_keys <= 7'b0000001;

      receive_and_verify_midi_packet({8'h90, 8'd60, 8'd127}, "LIVRE_NOTE_ON_C4");

      @(negedge clk);
      gpio_keys <= 7'b0000000;

      receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0}, "LIVRE_NOTE_OFF_C4");
      repeat (10) @(posedge clk);

      // Teste de alternancia rapida entre notas distintas: C4 -> D4
      // Deve enviar estritamente Note On(D4) sem disparar Note On fantasma de C4
      @(negedge clk);
      gpio_keys <= 7'b0000010; // Tecla D4

      receive_and_verify_midi_packet({8'h90, 8'd62, 8'd127}, "LIVRE_NOTE_ON_D4_SEM_FANTASMA");

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
        receive_and_verify_midi_packet({8'h90, 1'b0, exp_nat[k], 8'd127}, "NAT_NOTE_ON");

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
        receive_and_verify_midi_packet({8'h90, 1'b0, exp_sharp[k], 8'd127}, "SHARP_NOTE_ON");

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
      receive_and_verify_midi_packet({8'h90, 8'd72, 8'd127}, "OCT5_DO_NOTE_ON");
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd72, 8'd0}, "OCT5_DO_NOTE_OFF");
      repeat (10) @(posedge clk);

      // 4. Testa mudanca de oitava abaixo duas vezes (Oitava 3)
      press_btn_oitava_down(); // Volta para 4
      press_btn_oitava_down(); // Vai para 3
      @(negedge clk);
      gpio_keys <= 7'b0000001; // Do3 = 48
      receive_and_verify_midi_packet({8'h90, 8'd48, 8'd127}, "OCT3_DO_NOTE_ON");
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd48, 8'd0}, "OCT3_DO_NOTE_OFF");
      repeat (10) @(posedge clk);
    end
  endtask

  task test_gravacao_e_demonstracao_ram;
    integer idx;
    time    t_on;
    time    t_off;
    begin
      tests_run = tests_run + 1;
      setup();

      for (idx = 0; idx < 42; idx = idx + 1) begin
        press_btn_musica();
      end

      press_btn_modo();
      press_btn_modo();

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd127}, "GRAV_MONITOR_NOTE_ON");
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "GRAV_MONITOR_NOTE_OFF");
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

      begin
        press_btn_modo();
      end

      fork
        begin
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd127}, "DEMO_RAM_PLAYBACK_NOTE_ON");
          t_on = $time;
          receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "DEMO_RAM_PLAYBACK_NOTE_OFF");
          t_off = $time;
          if ((t_off - t_on) < (2 * CiclosTick8ms * ClkPeriodNs)) begin
            $display("[FALHA] %0t ns | DEMO_RAM_DURATION: esperado >= %0d ns, obtido %0d ns",
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

      begin
        repeat (20) @(posedge clk);
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
          receive_and_verify_midi_packet({8'h90, 8'd67, 8'd48}, "CLAIR_DE_LUNE_N0_ON");
          receive_and_verify_midi_packet({8'h80, 8'd67, 8'd0},  "CLAIR_DE_LUNE_N0_OFF");
          receive_and_verify_midi_packet({8'h90, 8'd79, 8'd61}, "CLAIR_DE_LUNE_N1_ON");
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
          {8'hAA, 8'hD1, 8'h06, 8'd7, 8'd1, 8'd87, 8'h36}) begin
        $display("[FAIL] %0t ns | DASH_PKT: exp AAD10607015736, got %02h%02h%02h%02h%02h%02h%02h",
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

      // Pressiona Do na oitava 6 (MIDI 84 = 24'h90547F)
      @(negedge clk);
      gpio_keys <= 7'b0000001;
      receive_and_verify_midi_packet({8'h90, 8'd84, 8'd127}, "HCSR04_OCT6_DO_NOTE_ON");

      // Solta tecla Do (24'h805400)
      @(negedge clk);
      gpio_keys <= 7'b0000000;
      receive_and_verify_midi_packet({8'h80, 8'd84, 8'd0}, "HCSR04_OCT6_DO_NOTE_OFF");
      repeat (10) @(posedge clk);

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
          receive_and_verify_midi_packet({8'h90, 8'd62, 8'd127}, "M1_WRONG_NOTE_ON");
          receive_and_verify_midi_packet({8'h80, 8'd62, 8'd0},   "M1_WRONG_NOTE_OFF");

          // 7 notas corretas da escala Do_Re_Mi_Fa (Do4..Si4)
          for (note_idx = 0; note_idx < 7; note_idx = note_idx + 1) begin
            receive_and_verify_midi_packet(
              {8'h90, 1'b0, exp_notes[note_idx], 8'd127}, "M1_SCALE_NOTE_ON");
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
          {8'hAA, 8'hD1, 8'h06, 8'd7, 8'd1, 8'd87, 8'h36}) begin
        $display("[FALHA] %0t ns | DASH_PKT: exp AAD10607015736, got %02h%02h%02h%02h%02h%02h%02h",
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
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd127}, "SEMANA4_GRAV_NOTE_ON");
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
          receive_and_verify_midi_packet({8'h90, 8'd60, 8'd127}, "SEMANA4_DEMO_NOTE_ON");
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

  initial begin
    $display("INICIANDO SIMULACAO: piano_top_tb");

    test_modo_livre_midi();
    test_todas_notas_e_sustenidos_midi();
    test_modo_aprendizado_acerto_erro();
    test_gravacao_e_demonstracao_ram();
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
