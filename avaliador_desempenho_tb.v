// Descricao: Testbench do avaliador de desempenho do Modo Assistido.
// Funcionamento: Valida contagem de acertos/erros e o calculo de score antes
// do envio serial final para o dashboard no computador.

`timescale 1ns / 1ps
`default_nettype none

module avaliador_desempenho_tb;

  reg        clk;
  reg        arst;
  reg [1:0]  modo_ativo;
  reg [5:0]  sel_musica;
  reg        fim_musica;
  reg [7:0]  acertos;
  reg [7:0]  erros;

  wire [7:0] score;
  wire       saida_serial;

  integer errors;

  avaliador_desempenho uut (
    .clk          (clk),
    .arst         (arst),
    .modo_ativo   (modo_ativo),
    .sel_musica   (sel_musica),
    .fim_musica   (fim_musica),
    .acertos      (acertos),
    .erros        (erros),
    .score        (score),
    .saida_serial (saida_serial)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    errors     = 0;
    arst       = 1'b1;
    modo_ativo = 2'd0;
    sel_musica = 6'd4;
    fim_musica = 1'b0;
    acertos    = 8'd0;
    erros      = 8'd0;
    #20;

    arst       = 1'b0;
    modo_ativo = 2'd1;
    #10;

    // Fim da musica sem acertos/erros nao deve disparar envio serial
    fim_musica = 1'b1;
    #30;
    fim_musica = 1'b0;
    #10;
    if (uut.estado_reg !== 2'd0) begin
      $display("[FALHA] envio serial disparado sem tentativas (estado_reg=%0d)", uut.estado_reg);
      errors = errors + 1;
    end else begin
      $display("[OK] Sem envio serial quando acertos=0 e erros=0");
    end

    // Simula 1 erro e 1 acerto computados pelo fluxo de dados
    erros   = 8'd1;
    #20;
    acertos = 8'd1;
    #20;

    // Fim da musica: deve disparar envio serial.
    fim_musica = 1'b1;
    #100;
    fim_musica = 1'b0;

    if ((acertos !== 8'd1) || (erros !== 8'd1) || (score !== 8'd50)) begin
      $display("[FALHA] acertos=%0d erros=%0d score=%0d (esperado: 1/1/50)",
        acertos, erros, score);
      errors = errors + 1;
    end else begin
      $display("[OK] Contador de acertos/erros funcionando: acertos=%0d erros=%0d score=%0d",
        acertos, erros, score);
    end

    // Teste de overflow de 8 bits (acertos + erros >= 256)
    #500;
    acertos = 8'd200;
    erros   = 8'd100;
    #20;
    // Score esperado: 200 * 100 / 300 = 66%
    if (score !== 8'd66) begin
      $display("[FALHA] Overflow test: acertos=200 erros=100 esperado score=66, obtido %0d",
        score);
      errors = errors + 1;
    end else begin
      $display("[OK] Calculo de score com soma > 255 funcionando: score=%0d", score);
    end

    if (errors == 0) begin
      $display("RESULTADO: TODOS OS TESTES PASSARAM!");
    end else begin
      $display("RESULTADO: %0d TESTE(S) FALHARAM.", errors);
    end

    $finish;
  end

endmodule

`default_nettype wire
