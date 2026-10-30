// Descricao: Testbench auto-verificavel para o subsistema metronomo.
// Funcionamento: Verifica repouso inicial, varredura angular suave com
// beats nos extremos e retorno ao centro apos desabilitacao.

`timescale 1ns / 1ps
`default_nettype none

module metronomo_tb;

  localparam ClkPeriodNs   = 20;      // 50 MHz (20 ns)
  localparam SimTPasso     = 20;      // 20 ciclos de clock por passo angular
  localparam WatchdogMaxNs = 100_000; // 100 us de limite de seguranca

  reg         clk;
  reg         arst;
  reg         habilita;
  reg  [31:0] t_passo;

  wire        servo_controle;
  wire        pulso_beat;
  wire [2:0]  posicao_servo;

  integer errors     = 0;
  integer tests_run  = 0;
  integer beat_count = 0;
  reg     beat_err   = 1'b0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  metronomo #(
    .ClockFreq(50_000)
  ) metronomo_inst (
    .clk           (clk),
    .arst          (arst),
    .habilita      (habilita),
    .t_passo       (t_passo),
    .servo_controle(servo_controle),
    .pulso_beat    (pulso_beat),
    .posicao_servo (posicao_servo)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Watchdog da simulacao estourou em metronomo_tb!", $time);
    $finish;
  end

  always @(posedge clk) begin
    if (arst) begin
      beat_count <= 0;
      beat_err   <= 1'b0;
    end else if (pulso_beat) begin
      beat_count <= beat_count + 1;
      if (posicao_servo !== 3'd0 && posicao_servo !== 3'd7) begin
        $display("[FALHA] %0t ns | BEAT_EXTREMO: pulso fora de extremo! Posicao: %0d",
          $time, posicao_servo);
        beat_err <= 1'b1;
      end
    end
  end

  task setup;
    begin
      habilita <= 1'b0;
      t_passo  <= SimTPasso;
      arst     <= 1'b1;
      repeat (3) @(posedge clk);
      @(negedge clk);
      arst     <= 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  task expect_eq3(
    input [2:0]   actual,
    input [2:0]   expected,
    input [127:0] test_tag
  );
    begin
      if (actual !== expected) begin
        $display("[FALHA] %0t ns | %0s: esperado 3'd%0d, obtido 3'd%0d",
          $time, test_tag, expected, actual);
        errors = errors + 1;
      end
    end
  endtask

  task expect_true(
    input         cond,
    input [127:0] test_tag
  );
    begin
      if (!cond) begin
        $display("[FALHA] %0t ns | %0s: condicao esperada VERDADEIRA, obtida FALSA",
          $time, test_tag);
        errors = errors + 1;
      end
    end
  endtask

  task assert_true(
    input         cond,
    input [127:0] fatal_tag
  );
    begin
      if (!cond) begin
        $display("[ASSERT FATAL] %0t ns | %0s falhou. Abortando simulacao.", $time, fatal_tag);
        $finish;
      end
    end
  endtask

  task test_repouso;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      expect_eq3(posicao_servo, 3'd3, "TESTE_REPOUSO_CENTRO");
    end
  endtask

  task test_varredura_e_beats;
    integer timeout_cnt;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      habilita <= 1'b1;

      timeout_cnt = 0;
      while (beat_count < 1 && timeout_cnt < 200) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
      end
      assert_true(beat_count >= 1, "TESTE_BEAT1_DIR");

      timeout_cnt = 0;
      while (beat_count < 2 && timeout_cnt < 300) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
      end
      assert_true(beat_count >= 2, "TESTE_BEAT2_ESQ");

      timeout_cnt = 0;
      while (beat_count < 3 && timeout_cnt < 300) begin
        @(posedge clk);
        timeout_cnt = timeout_cnt + 1;
      end
      assert_true(beat_count >= 3, "TESTE_BEAT3_DIR");
      expect_true(!beat_err, "TESTE_BEAT_POSICAO_EXTREMO");
    end
  endtask

  task test_desabilitacao;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      habilita <= 1'b1;
      repeat (50) @(posedge clk);

      @(negedge clk);
      habilita <= 1'b0;
      repeat (3) @(posedge clk);

      @(negedge clk);
      expect_eq3(posicao_servo, 3'd3, "TESTE_DESAB_RETORNO_CENTRO");
    end
  endtask

  initial begin
    $display("INICIANDO SIMULACAO: metronomo_tb");

    test_repouso();
    test_varredura_e_beats();
    test_desabilitacao();

    #100;
    $display("RESUMO DOS TESTES");
    $display("Testes executados: %0d", tests_run);
    $display("Erros encontrados: %0d", errors);
    if (errors == 0) begin
      $display("RESULTADO: TODOS OS TESTES PASSARAM!");
    end else begin
      $display("RESULTADO: TESTBENCH FALHOU com %0d erro(s)!", errors);
    end

    $finish;
  end

endmodule

`default_nettype wire
