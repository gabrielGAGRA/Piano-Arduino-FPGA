// Descricao: Testbench auto-verificavel para o avaliador de desempenho (avaliador_desempenho).
// Funcionamento: Valida supressao de envio sem tentativas ou fora do Modo 1,
// calculo de score (incluindo soma > 255) e recepcao completa do pacote UART de 7 bytes.

`timescale 1ns / 1ps
`default_nettype none

module avaliador_desempenho_tb;

  localparam ClkPeriodNs  = 20;
  localparam ClockDivUart = 4;
  localparam WatchdogNs   = 500_000;

  reg        clk;
  reg        arst;
  reg [1:0]  modo_ativo;
  reg [5:0]  sel_musica;
  reg        fim_musica;
  reg [7:0]  acertos;
  reg [7:0]  erros;
  reg [9:0]  pontos_apre;

  wire [7:0] score;
  wire       saida_serial;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  avaliador_desempenho #(
    .ClockDivUart(ClockDivUart)
  ) dut (
    .clk         (clk),
    .arst        (arst),
    .modo_ativo  (modo_ativo),
    .sel_musica  (sel_musica),
    .fim_musica  (fim_musica),
    .acertos     (acertos),
    .erros       (erros),
    .pontos_apre (pontos_apre),
    .score       (score),
    .saida_serial(saida_serial)
  );

  // Watchdog obrigatorio
  initial begin
    #WatchdogNs;
    $display("[FATAL] %0t ns: Watchdog timeout - simulation deadlocked.", $time);
    $finish;
  end

  task setup;
    begin
      arst       <= 1'b1;
      modo_ativo <= 2'd0;
      sel_musica <= 6'd4;
      fim_musica <= 1'b0;
      acertos     <= 8'd0;
      erros       <= 8'd0;
      pontos_apre <= 10'd0;
      repeat (2) @(posedge clk);
      @(negedge clk) arst <= 1'b0;
      @(posedge clk);
      #1;
      if (score === 8'hxx || saida_serial === 1'bx) begin
        $display("[FATAL] %0t ns: Output X post-reset.", $time);
        $finish;
      end
    end
  endtask

  task expect_score(
    input [7:0]   exp,
    input [255:0] tag
  );
    begin
      if (score !== exp) begin
        $display("[FAIL] %0t ns | %0s: exp %0d, got %0d", $time, tag, exp, score);
        errors = errors + 1;
      end
    end
  endtask

  task expect_byte(
    input [7:0]   exp,
    input [7:0]   actual,
    input [255:0] tag
  );
    begin
      if (actual !== exp) begin
        $display("[FAIL] %0t ns | %0s: exp 0x%02h, got 0x%02h", $time, tag, exp, actual);
        errors = errors + 1;
      end
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
        $display("[FAIL] %0t ns | UART_START: exp 0b0, got 0b%0b", $time, saida_serial);
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
        $display("[FAIL] %0t ns | UART_STOP: exp 0b1, got 0b%0b", $time, saida_serial);
        errors = errors + 1;
      end
    end
  endtask

  task test_sem_tentativas_nao_envia;
    integer cyc;
    begin
      tests_run = tests_run + 1;
      setup();

      // 1. Modo 1 com acertos=0 e erros=0 nao deve iniciar envio serial
      @(negedge clk);
      modo_ativo <= 2'd1;
      acertos     <= 8'd0;
      erros       <= 8'd0;
      pontos_apre <= 10'd0;
      repeat (2) @(posedge clk);

      @(negedge clk);
      fim_musica <= 1'b1;
      for (cyc = 0; cyc < 20; cyc = cyc + 1) begin
        @(posedge clk);
        #1;
        if (saida_serial !== 1'b1) begin
          $display("[FAIL] %0t ns | NO_SEND_ZERO_ATTEMPTS: saida_serial=0b%0b",
            $time, saida_serial);
          errors = errors + 1;
        end
      end

      @(negedge clk);
      fim_musica <= 1'b0;
      repeat (2) @(posedge clk);

      // 2. Fora do Modo 1 (modo_ativo=0), nao deve enviar mesmo com tentativas
      @(negedge clk);
      modo_ativo  <= 2'd0;
      acertos     <= 8'd2;
      erros       <= 8'd1;
      pontos_apre <= 10'd8;
      repeat (2) @(posedge clk);
      #1;
      expect_score(8'd66, "SCORE_MODO0_CALC");

      @(negedge clk);
      fim_musica <= 1'b1;
      for (cyc = 0; cyc < 20; cyc = cyc + 1) begin
        @(posedge clk);
        #1;
        if (saida_serial !== 1'b1) begin
          $display("[FAIL] %0t ns | NO_SEND_WRONG_MODE: saida_serial=0b%0b",
            $time, saida_serial);
          errors = errors + 1;
        end
      end

      @(negedge clk);
      fim_musica <= 1'b0;
    end
  endtask

  task test_envio_pacote_uart_modo_assistido;
    reg [7:0] b0;
    reg [7:0] b1;
    reg [7:0] b2;
    reg [7:0] b3;
    reg [7:0] b4;
    reg [7:0] b5;
    reg [7:0] b6;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      modo_ativo  <= 2'd1;
      sel_musica  <= 6'd4;
      acertos     <= 8'd1;
      erros       <= 8'd1;
      pontos_apre <= 10'd4;
      repeat (2) @(posedge clk);
      #1;
      expect_score(8'd50, "SCORE_50_PERCENT");

      fork
        begin
          receive_uart_byte(b0);
          receive_uart_byte(b1);
          receive_uart_byte(b2);
          receive_uart_byte(b3);
          receive_uart_byte(b4);
          receive_uart_byte(b5);
          receive_uart_byte(b6);
        end
        begin
          @(negedge clk);
          fim_musica <= 1'b1;
          repeat (4) @(posedge clk);
          @(negedge clk);
          fim_musica <= 1'b0;
        end
      join

      expect_byte(8'hAA, b0, "UART_PKT_B0_SYNC");
      expect_byte(8'hD1, b1, "UART_PKT_B1_CMD");
      expect_byte(8'h04, b2, "UART_PKT_B2_MUSICA");
      expect_byte(8'd1,  b3, "UART_PKT_B3_ACERTOS");
      expect_byte(8'd1,  b4, "UART_PKT_B4_ERROS");
      expect_byte(8'd50, b5, "UART_PKT_B5_SCORE");
      // Checksum = (0xD1 + 0x04 + 1 + 1 + 50) & 0xFF = 0x09
      expect_byte(8'h09, b6, "UART_PKT_B6_CHECKSUM");
      repeat (10) @(posedge clk);
    end
  endtask

  task test_overflow_soma_16bits;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      modo_ativo  <= 2'd1;
      acertos     <= 8'd200;
      erros       <= 8'd100;
      pontos_apre <= 10'd800;
      repeat (2) @(posedge clk);
      #1;
      // 800 * 100 / (300 * 4) = 66%
      expect_score(8'd66, "OVERFLOW_SUM_GT_255");

      @(negedge clk);
      acertos     <= 8'd255;
      erros       <= 8'd0;
      pontos_apre <= 10'd1020;
      repeat (2) @(posedge clk);
      #1;
      expect_score(8'd100, "SCORE_100_PERCENT");
    end
  endtask

  task test_pontuacao_proporcional_ritmo;
    begin
      tests_run = tests_run + 1;
      setup();

      // 1. Pontuacao maxima de ritmo (acertos * 4) -> 100%
      @(negedge clk);
      modo_ativo  <= 2'd1;
      acertos     <= 8'd7;
      erros       <= 8'd0;
      pontos_apre <= 10'd28;
      repeat (2) @(posedge clk);
      #1;
      expect_score(8'd100, "RITMO_COMPLETO_100");

      // 2. Pontuacao reduzida de ritmo (acertos * 2) -> 50%
      @(negedge clk);
      acertos     <= 8'd7;
      erros       <= 8'd0;
      pontos_apre <= 10'd14;
      repeat (2) @(posedge clk);
      #1;
      expect_score(8'd50, "RITMO_REDUZIDO_50");

      // 3. Rushed com 1 erro (7 acertos, 1 erro, 15 pontos) -> 46%
      @(negedge clk);
      acertos     <= 8'd7;
      erros       <= 8'd1;
      pontos_apre <= 10'd15;
      repeat (2) @(posedge clk);
      #1;
      expect_score(8'd46, "RITMO_RUSHED_46");

      // 4. Saturacao em 100% se pontos_apre exceder max_pontos
      @(negedge clk);
      acertos     <= 8'd2;
      erros       <= 8'd0;
      pontos_apre <= 10'd15;
      repeat (2) @(posedge clk);
      #1;
      expect_score(8'd100, "RITMO_CLAMP_100");
    end
  endtask

  initial begin
    test_sem_tentativas_nao_envia();
    test_envio_pacote_uart_modo_assistido();
    test_overflow_soma_16bits();
    test_pontuacao_proporcional_ritmo();

    if (errors == 0) begin
      $display("RESULT: ALL TESTS PASSED! (Tests: %0d)", tests_run);
    end else begin
      $display("RESULT: TESTBENCH FAILED! Errors: %0d", errors);
    end
    $finish;
  end

endmodule

`default_nettype wire
