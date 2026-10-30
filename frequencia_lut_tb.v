// Descricao: Testbench auto-verificavel para a tabela LUT de frequencias (frequencia_lut).
// Funcionamento: Valida mapeamento de notas (Do a Si) nas oitavas 4, 5, 6 e 7,
// com e sem sustenido, e saida default (0) para entradas invalidas.

`timescale 1ns / 1ps
`default_nettype none

module frequencia_lut_tb;

  localparam WatchdogMaxNs = 50_000;

  reg  [2:0]  nota_id;
  reg         sustenido;
  reg  [2:0]  oitava;
  wire [17:0] n_ticks;

  integer errors    = 0;
  integer tests_run = 0;

  frequencia_lut frequencia_lut_inst (
    .nota_id   (nota_id),
    .sustenido (sustenido),
    .oitava    (oitava),
    .n_ticks   (n_ticks)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Watchdog da simulacao estourou em frequencia_lut_tb!", $time);
    $finish;
  end

  task expect_ticks(
    input [17:0]  expected,
    input [255:0] test_tag
  );
    begin
      #1;
      if (n_ticks !== expected) begin
        $display("[FALHA] %0t ns | %0s: esperado %0d (18'h%h), obtido %0d (18'h%h)",
          $time, test_tag, expected, expected, n_ticks, n_ticks);
        errors = errors + 1;
      end
    end
  endtask

  task test_oitava_4;
    begin
      tests_run = tests_run + 1;
      oitava    = 3'b100;

      nota_id   = 3'd1;
      sustenido = 1'b0;
      expect_ticks(18'd191113, "TESTE_DO4_NATURAL");

      sustenido = 1'b1;
      expect_ticks(18'd180386, "TESTE_DO4_SUSTENIDO");

      nota_id   = 3'd6;
      sustenido = 1'b0;
      expect_ticks(18'd113636, "TESTE_LA4_NATURAL");

      sustenido = 1'b1;
      expect_ticks(18'd107258, "TESTE_LA4_SUSTENIDO");

      nota_id   = 3'd7;
      sustenido = 1'b0;
      expect_ticks(18'd101238, "TESTE_SI4_NATURAL");

      sustenido = 1'b1;
      expect_ticks(18'd95556,  "TESTE_SI4_SUSTENIDO");
    end
  endtask

  task test_oitavas_subsequentes;
    begin
      tests_run = tests_run + 1;

      // Oitava 5: Do5
      oitava    = 3'b101;
      nota_id   = 3'd1;
      sustenido = 1'b0;
      expect_ticks(18'd95557, "TESTE_DO5_NATURAL");
      sustenido = 1'b1;
      expect_ticks(18'd90193, "TESTE_DO5_SUSTENIDO");

      // Oitava 6: Fa6
      oitava    = 3'b110;
      nota_id   = 3'd4;
      sustenido = 1'b0;
      expect_ticks(18'd35793, "TESTE_FA6_NATURAL");
      sustenido = 1'b1;
      expect_ticks(18'd33784, "TESTE_FA6_SUSTENIDO");

      // Oitava 7: Si7
      oitava    = 3'b111;
      nota_id   = 3'd7;
      sustenido = 1'b0;
      expect_ticks(18'd12655, "TESTE_SI7_NATURAL");
      sustenido = 1'b1;
      expect_ticks(18'd11945, "TESTE_SI7_SUSTENIDO");
    end
  endtask

  task test_valores_invalidos;
    begin
      tests_run = tests_run + 1;

      oitava    = 3'b010;
      nota_id   = 3'd1;
      sustenido = 1'b0;
      expect_ticks(18'd0, "TESTE_OITAVA_INVALIDA_RETORNA_ZERO");

      oitava    = 3'b100;
      nota_id   = 3'd0;
      sustenido = 1'b0;
      expect_ticks(18'd0, "TESTE_NOTA_ZERO_RETORNA_ZERO");

      oitava    = 3'b000;
      nota_id   = 3'd5;
      sustenido = 1'b1;
      expect_ticks(18'd0, "TESTE_OITAVA_ZERO_RETORNA_ZERO");
    end
  endtask

  initial begin
    $display("INICIANDO SIMULACAO: frequencia_lut_tb");

    test_oitava_4();
    test_oitavas_subsequentes();
    test_valores_invalidos();

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
