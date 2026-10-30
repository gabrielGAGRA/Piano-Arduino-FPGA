// Descricao: Testbench auto-verificavel para logica_notas_prioridade.
// Funcionamento: Valida reset, prioridade da ultima tecla pressionada
// (borda de subida), fallback para a nota ativa de maior indice e desativacao.

`timescale 1ns / 1ps
`default_nettype none

module logica_notas_prioridade_tb;

  localparam ClkPeriodNs   = 20;     // 50 MHz (20 ns)
  localparam WatchdogMaxNs = 50_000; // 50 us

  reg        clk;
  reg        arst;
  reg  [6:0] botoes;

  wire [2:0] nota_id;
  wire       tem_nota;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  logica_notas_prioridade logica_notas_prioridade_inst (
    .clk      (clk),
    .arst     (arst),
    .botoes   (botoes),
    .nota_id  (nota_id),
    .tem_nota (tem_nota)
  );

  initial begin
    #WatchdogMaxNs;
    $display(
      "\n[FATAL] %0t ns: Watchdog da simulacao estourou em logica_notas_prioridade_tb!",
      $time
    );
    $finish;
  end

  task setup;
    begin
      botoes <= 7'd0;
      arst   <= 1'b1;
      repeat (2) @(posedge clk);
      @(negedge clk);
      arst   <= 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  task expect_nota(
    input [2:0]   exp_id,
    input         exp_tem,
    input [255:0] tag
  );
    begin
      if (nota_id !== exp_id || tem_nota !== exp_tem) begin
        $display("[FALHA] %0t ns | %0s: esperado (id=%0d, tem=%b), obtido (id=%0d, tem=%b)",
          $time, tag, exp_id, exp_tem, nota_id, tem_nota);
        errors = errors + 1;
      end
    end
  endtask

  task test_reset;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      expect_nota(3'd0, 1'b0, "TESTE_RESET_ESTADO_LIMPO");
    end
  endtask

  task test_teclas_individuais;
    begin
      tests_run = tests_run + 1;
      setup();

      // Pressiona Do (botao 0)
      @(negedge clk);
      botoes <= 7'b0000001;
      @(negedge clk);
      expect_nota(3'd1, 1'b1, "TESTE_PRESSIONA_DO");

      // Solta botao 0
      @(negedge clk);
      botoes <= 7'b0000000;
      #1;
      expect_nota(3'd1, 1'b0, "TESTE_SOLTA_DO_TEM_NOTA_ZERO");

      // Pressiona Si (botao 6)
      @(negedge clk);
      botoes <= 7'b1000000;
      @(negedge clk);
      expect_nota(3'd7, 1'b1, "TESTE_PRESSIONA_SI");

      // Solta botao 6
      @(negedge clk);
      botoes <= 7'b0000000;
      #1;
      expect_nota(3'd7, 1'b0, "TESTE_SOLTA_SI_TEM_NOTA_ZERO");
    end
  endtask

  task test_prioridade_ultima_tecla;
    begin
      tests_run = tests_run + 1;
      setup();

      // Pressiona Do (botao 0) -> nota 1
      @(negedge clk);
      botoes <= 7'b0000001;
      @(negedge clk);
      expect_nota(3'd1, 1'b1, "TESTE_PRIORIDADE_PRIMEIRA_NOTA");

      // Mantem Do pressionado e pressiona Fa (botao 3) -> comuta para nota 4
      @(negedge clk);
      botoes <= 7'b0001001;
      @(negedge clk);
      expect_nota(3'd4, 1'b1, "TESTE_PRIORIDADE_SOBREPOSICAO_FA");

      // Mantem ambos e pressiona Re (botao 1) -> comuta para nota 2
      @(negedge clk);
      botoes <= 7'b0001011;
      @(negedge clk);
      expect_nota(3'd2, 1'b1, "TESTE_PRIORIDADE_SOBREPOSICAO_RE");
    end
  endtask

  task test_fallback_maior_indice;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      botoes <= 7'b0000001;
      @(negedge clk);
      botoes <= 7'b0001001;
      @(negedge clk);
      botoes <= 7'b0001011;
      @(negedge clk);
      expect_nota(3'd2, 1'b1, "TESTE_FALLBACK_PRECOND_RE_ATIVO");

      @(negedge clk);
      botoes <= 7'b0001001;
      @(negedge clk);
      expect_nota(3'd4, 1'b1, "TESTE_FALLBACK_PARA_FA");

      @(negedge clk);
      botoes <= 7'b0000001;
      @(negedge clk);
      expect_nota(3'd1, 1'b1, "TESTE_FALLBACK_PARA_DO");

      @(negedge clk);
      botoes <= 7'b0000000;
      #1;
      expect_nota(3'd1, 1'b0, "TESTE_FALLBACK_SOLTA_TUDO");
    end
  endtask

  initial begin
    $display("INICIANDO SIMULACAO: logica_notas_prioridade_tb");

    test_reset();
    test_teclas_individuais();
    test_prioridade_ultima_tecla();
    test_fallback_maior_indice();

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
