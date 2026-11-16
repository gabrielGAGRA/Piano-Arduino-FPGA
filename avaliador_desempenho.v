// Descricao: Avaliador de desempenho do Modo Assistido.
// Funcionamento: Conecta estruturalmente a unidade de controle (UC) e o fluxo
// de dados (FD) para calculo de score e envio do pacote serial UART.

`timescale 1ns / 1ps
`default_nettype none

module avaliador_desempenho #(
  parameter ClockDivUart = 434
)(
  input  wire        clk,
  input  wire        arst,
  input  wire [1:0]  modo_ativo,
  input  wire [5:0]  sel_musica,
  input  wire        fim_musica,
  input  wire [7:0]  acertos,
  input  wire [7:0]  erros,
  output wire [7:0]  score,
  output wire        saida_serial
);

  wire envio_necessario;
  wire tx_pronto;
  wire fim_bytes;
  wire carrega_pacote;
  wire zera_idx;
  wire conta_idx;
  wire tx_partida;

  avaliador_desempenho_uc avaliador_desempenho_uc_inst (
    .clk             (clk),
    .arst            (arst),
    .envio_necessario(envio_necessario),
    .tx_pronto       (tx_pronto),
    .fim_bytes       (fim_bytes),
    .carrega_pacote  (carrega_pacote),
    .zera_idx        (zera_idx),
    .conta_idx       (conta_idx),
    .tx_partida      (tx_partida)
  );

  avaliador_desempenho_fd #(
    .ClockDivUart(ClockDivUart)
  ) avaliador_desempenho_fd_inst (
    .clk             (clk),
    .arst            (arst),
    .carrega_pacote  (carrega_pacote),
    .zera_idx        (zera_idx),
    .conta_idx       (conta_idx),
    .tx_partida      (tx_partida),
    .modo_ativo      (modo_ativo),
    .sel_musica      (sel_musica),
    .fim_musica      (fim_musica),
    .acertos         (acertos),
    .erros           (erros),
    .envio_necessario(envio_necessario),
    .tx_pronto       (tx_pronto),
    .fim_bytes       (fim_bytes),
    .score           (score),
    .saida_serial    (saida_serial)
  );

endmodule

`default_nettype wire
