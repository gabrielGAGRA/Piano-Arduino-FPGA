// Descrição: Fluxo de dados (datapath) da transmissao serial assincrona 8N1.
// Funcionamento: Monta a trama serial de 11 bits (1 repouso + 1 start + 8 dados + 1 stop)
// e realiza o deslocamento sequencial a cada pulso de controle.

`timescale 1ns / 1ps
`default_nettype none

module tx_serial_8N1_fd (
  input  wire       clk,
  input  wire       arst,
  input  wire       zera,
  input  wire       conta,
  input  wire       carrega,
  input  wire       desloca,
  input  wire [7:0] dados_byte,
  output wire       saida_serial,
  output wire       fim
);

  wire [10:0] s_dados;
  wire [10:0] s_saida;

  // Composicao da trama serial 8N1:
  assign s_dados[0]   = 1'b1;              // Repouso inicial
  assign s_dados[1]   = 1'b0;              // Start bit
  assign s_dados[9:2] = dados_byte[7:0];   // 8 bits de dados (LSB primeiro)
  assign s_dados[10]  = 1'b1;              // Stop bit

  deslocador_n #(
    .Width(11)
  ) deslocador_n_inst (
    .clk           (clk),
    .arst          (arst),
    .carrega       (carrega),
    .desloca       (desloca),
    .entrada_serial(1'b1),
    .dados         (s_dados),
    .saida         (s_saida)
  );

  contador_m #(
    .Modulo(12),
    .Width (4)
  ) contador_m_inst (
    .clk  (clk),
    .arst (arst),
    .sclr (zera),
    .conta(conta),
    .fim  (fim),
    .meio (),
    .q    ()
  );

  assign saida_serial = s_saida[0];

endmodule

`default_nettype wire
