// Descrição: Testbench auto-verificavel para a Unidade de Controle (unidade_controle).
// Funcionamento: Valida inicializacao e transicoes entre os 4 modos:
// 0: Livre, 1: Aprendizado, 2: Gravacao, 3: Demo e pulsos de escrita/zera/conta.

`timescale 1ns / 1ps
`default_nettype none

module unidade_controle_tb;

  localparam ClkPeriodNs   = 20;     // 50 MHz (20 ns)
  localparam WatchdogMaxNs = 50_000; // 50 us

  reg        clk;
  reg        arst;
  reg        mudou_modo;
  reg        mudou_musica;
  reg        tem_nota_ativa;
  reg        tecla_pressionada;
  reg        acerto_nota;
  reg        fim_musica;
  reg        pulso_bpm;

  wire [1:0] modo_ativo;
  wire       escreve_ram;
  wire       zera_endereco;
  wire       conta_endereco;
  wire [4:0] estado_hex;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  unidade_controle unidade_controle_inst (
    .clk               (clk),
    .arst              (arst),
    .mudou_modo        (mudou_modo),
    .mudou_musica      (mudou_musica),
    .tem_nota_ativa    (tem_nota_ativa),
    .tecla_pressionada (tecla_pressionada),
    .acerto_nota       (acerto_nota),
    .fim_musica        (fim_musica),
    .pulso_bpm         (pulso_bpm),
    .modo_ativo        (modo_ativo),
    .escreve_ram       (escreve_ram),
    .zera_endereco     (zera_endereco),
    .conta_endereco    (conta_endereco),
    .estado_hex        (estado_hex)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Simulation watchdog timed out in unidade_controle_tb!", $time);
    $finish;
  end

  task setup;
    begin
      mudou_modo        <= 1'b0;
      mudou_musica      <= 1'b0;
      tem_nota_ativa    <= 1'b0;
      tecla_pressionada <= 1'b0;
      acerto_nota       <= 1'b0;
      fim_musica        <= 1'b0;
      pulso_bpm         <= 1'b0;
      arst              <= 1'b1;
      repeat (2) @(posedge clk);
      @(negedge clk);
      arst              <= 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  task expect_modo_estado(
    input [1:0]   exp_modo,
    input [4:0]   exp_hex,
    input [255:0] tag
  );
    begin
      if (modo_ativo !== exp_modo || estado_hex !== exp_hex) begin
        $display("[FAIL] %0t ns | %0s: exp (m=%0d, hex=%0h), got (m=%0d, hex=%0h)",
          $time, tag, exp_modo, exp_hex, modo_ativo, estado_hex);
        errors = errors + 1;
      end
    end
  endtask

  task expect_flags(
    input         exp_escreve,
    input         exp_zera,
    input         exp_conta,
    input [255:0] tag
  );
    begin
      if (escreve_ram !== exp_escreve || zera_endereco !== exp_zera ||
          conta_endereco !== exp_conta) begin
        $display("[FAIL] %0t ns | %0s: exp flags (w=%b, z=%b, c=%b), got (%b,%b,%b)",
          $time, tag, exp_escreve, exp_zera, exp_conta,
          escreve_ram, zera_endereco, conta_endereco);
        errors = errors + 1;
      end
    end
  endtask

  task test_reset_e_modo_livre;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      expect_modo_estado(2'd0, 5'h0, "TESTE_LIVRE_MODO_ESTADO");
      expect_flags(1'b0, 1'b1, 1'b0, "TESTE_LIVRE_ZERA_ENDERECO");
    end
  endtask

  task test_modo_aprendizado;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      mudou_modo <= 1'b1;

      @(negedge clk);
      mudou_modo <= 1'b0;
      expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_INICIA_MUSICA");
      expect_flags(1'b0, 1'b1, 1'b0, "TESTE_APRENDIZADO_ZERA_END");

      @(negedge clk);
      expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_ESPERA_NOTA");

      tem_nota_ativa <= 1'b1;
      @(negedge clk);
      expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_COMPARA_NOTA");

      acerto_nota <= 1'b1;
      @(negedge clk);
      acerto_nota <= 1'b0;
      expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_ESPERA_SOLTAR");

      tem_nota_ativa <= 1'b0;
      @(negedge clk);
      expect_flags(1'b0, 1'b0, 1'b1, "TESTE_APRENDIZADO_CONTA_ENDERECO");

      @(negedge clk);
      @(negedge clk);
      expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_RETORNA_ESPERA_NOTA");
    end
  endtask

  task test_modo_gravacao;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      mudou_modo <= 1'b1;
      repeat (2) @(negedge clk);
      mudou_modo <= 1'b0;

      @(negedge clk);
      mudou_modo <= 1'b1;
      @(negedge clk);
      mudou_modo <= 1'b0;
      expect_modo_estado(2'd2, 5'h2, "TESTE_GRAVACAO_INICIA");
      expect_flags(1'b0, 1'b1, 1'b0, "TESTE_GRAVACAO_ZERA_END");

      @(negedge clk);
      expect_modo_estado(2'd2, 5'h2, "TESTE_GRAVACAO_ESPERA_NOTA");

      tem_nota_ativa <= 1'b1;
      @(negedge clk);
      expect_flags(1'b0, 1'b0, 1'b0, "TESTE_GRAVACAO_SOLTAR_AGUARDA");

      tem_nota_ativa <= 1'b0;
      @(negedge clk);
      expect_flags(1'b1, 1'b0, 1'b0, "TESTE_GRAVACAO_ESCREVE_RAM");

      @(negedge clk);
      expect_flags(1'b0, 1'b0, 1'b1, "TESTE_GRAVACAO_CONTA_END");

      @(negedge clk);
      expect_modo_estado(2'd2, 5'h2, "TESTE_GRAVACAO_RETORNA_ESPERA");
      expect_flags(1'b0, 1'b0, 1'b0, "TESTE_GRAVACAO_RETORNA_ESPERA_FLAGS");
    end
  endtask

  task test_modo_demo_e_retorno_livre;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      mudou_modo <= 1'b1;
      repeat (3) @(negedge clk);
      mudou_modo <= 1'b0;

      @(negedge clk);
      mudou_modo <= 1'b1;
      @(negedge clk);
      mudou_modo <= 1'b0;
      expect_modo_estado(2'd3, 5'h3, "TESTE_DEMO_INICIA");
      expect_flags(1'b0, 1'b1, 1'b0, "TESTE_DEMO_ZERA_END");

      tecla_pressionada <= 1'b1;
      @(negedge clk);
      tecla_pressionada <= 1'b0;
      expect_modo_estado(2'd3, 5'h3, "TESTE_DEMO_TOCA_NOTA");

      pulso_bpm <= 1'b1;
      @(negedge clk);
      pulso_bpm <= 1'b0;
      expect_flags(1'b0, 1'b0, 1'b1, "TESTE_DEMO_CONTA_ENDERECO");

      @(negedge clk);
      mudou_modo <= 1'b1;
      @(negedge clk);
      mudou_modo <= 1'b0;
      expect_modo_estado(2'd0, 5'h0, "TESTE_DEMO_RETORNA_LIVRE");
    end
  endtask

  initial begin
    $display("========================================");
    $display("STARTING SIMULATION: unidade_controle_tb");
    $display("========================================");

    test_reset_e_modo_livre();
    test_modo_aprendizado();
    test_modo_gravacao();
    test_modo_demo_e_retorno_livre();

    #100;
    $display("\n========================================");
    $display("TEST SUMMARY");
    $display("Tests Executed: %0d", tests_run);
    $display("Errors Found:   %0d", errors);
    if (errors == 0) begin
      $display("RESULT: ALL TESTS PASSED!");
      $display("========================================");
    end else begin
      $display("RESULT: TESTBENCH FAILED with %0d error(s)!", errors);
      $display("========================================");
    end

    $finish;
  end

endmodule

`default_nettype wire
