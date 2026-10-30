// Descricao: Testbench auto-verificavel para o contador parametrizavel (contador_m).
// Funcionamento: Valida reset assincrono (arst), contagem progressiva,
// deteccao de meio e fim, wrap-around, clear sincrono (sclr) e inibicao.

`timescale 1ns / 1ps
`default_nettype none

module contador_m_tb;

  localparam ClkPeriodNs   = 20;     // 50 MHz (20 ns)
  localparam WatchdogMaxNs = 50_000; // 50 us
  localparam TestM         = 8;      // Modulo 8 para simulacao rapida
  localparam TestN         = 4;      // 4 bits suficientes para contar ate 8

  reg               clk;
  reg               arst;
  reg               sclr;
  reg               conta;

  wire [TestN-1:0]  q;
  wire              fim;
  wire              meio;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  contador_m #(
    .Modulo (TestM),
    .Width  (TestN)
  ) contador_m_inst (
    .clk   (clk),
    .arst  (arst),
    .sclr  (sclr),
    .conta (conta),
    .q     (q),
    .fim   (fim),
    .meio  (meio)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Watchdog da simulacao estourou em contador_m_tb!", $time);
    $finish;
  end

  task setup;
    begin
      sclr  <= 1'b0;
      conta <= 1'b0;
      arst  <= 1'b1;
      repeat (2) @(posedge clk);
      @(negedge clk);
      arst  <= 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  task expect_eq4(
    input [TestN-1:0] actual,
    input [TestN-1:0] expected,
    input [255:0]     test_tag
  );
    begin
      if (actual !== expected) begin
        $display("[FALHA] %0t ns | %0s: esperado %0d, obtido %0d",
          $time, test_tag, expected, actual);
        errors = errors + 1;
      end
    end
  endtask

  task expect_flag(
    input         actual,
    input         expected,
    input [255:0] test_tag
  );
    begin
      if (actual !== expected) begin
        $display("[FALHA] %0t ns | %0s: esperado %b, obtido %b",
          $time, test_tag, expected, actual);
        errors = errors + 1;
      end
    end
  endtask

  task assert_true(
    input         cond,
    input [255:0] fatal_tag
  );
    begin
      if (!cond) begin
        $display("[ASSERT FATAL] %0t ns | %0s falhou. Abortando simulacao.",
          $time, fatal_tag);
        $finish;
      end
    end
  endtask

  task test_reset;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      expect_eq4(q, 4'd0, "TESTE_RESET_Q");
      expect_flag(fim, 1'b0, "TESTE_RESET_FIM");
      expect_flag(meio, 1'b0, "TESTE_RESET_MEIO");
    end
  endtask

  task test_contagem_e_flags;
    integer i;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      expect_eq4(q, 4'd0, "TESTE_CONTA_INICIAL");
      conta <= 1'b1;

      for (i = 1; i < TestM; i = i + 1) begin
        @(negedge clk);
        expect_eq4(q, i[TestN-1:0], "TESTE_CONTA_PASSO");

        if (i == 3) begin
          expect_flag(meio, 1'b1, "TESTE_FLAG_MEIO_ATIVO");
        end else begin
          expect_flag(meio, 1'b0, "TESTE_FLAG_MEIO_INATIVO");
        end

        if (i == 7) begin
          expect_flag(fim, 1'b1, "TESTE_FLAG_FIM_ATIVO");
        end else begin
          expect_flag(fim, 1'b0, "TESTE_FLAG_FIM_INATIVO");
        end
      end

      @(negedge clk);
      expect_eq4(q, 4'd0, "TESTE_WRAPAROUND_Q");
      expect_flag(fim, 1'b0, "TESTE_WRAPAROUND_FIM");

      conta <= 1'b0;
    end
  endtask

  task test_sclr;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      conta <= 1'b1;
      repeat (3) @(negedge clk);

      expect_eq4(q, 4'd3, "TESTE_SCLR_PRECOND");
      sclr <= 1'b1;

      @(negedge clk);
      expect_eq4(q, 4'd0, "TESTE_SCLR_PRIORIDADE_SOBRE_CONTA");

      sclr  <= 1'b0;
      conta <= 1'b0;
    end
  endtask

  task test_inibe_conta;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      conta <= 1'b1;
      repeat (2) @(negedge clk);

      expect_eq4(q, 4'd2, "TESTE_INIBE_PRECOND");
      conta <= 1'b0;

      repeat (3) @(negedge clk);
      expect_eq4(q, 4'd2, "TESTE_INIBE_VALOR_ESTATICO");
    end
  endtask

  initial begin
    $display("INICIANDO SIMULACAO: contador_m_tb");

    test_reset();
    test_contagem_e_flags();
    test_sclr();
    test_inibe_conta();

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
