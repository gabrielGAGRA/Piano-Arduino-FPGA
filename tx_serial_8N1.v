// Descricao: Transmissor serial assincrono UART 8N1 a 115200 bauds.
// Funcionamento: Integra gerador de baud rate por contador_m com FSM
// e datapath de serializacao de 10/11 bits.

`timescale 1ns / 1ps
`default_nettype none

module tx_serial_8N1 #(
  parameter ClockDiv = 434
)(
  input  wire       clk,
  input  wire       arst,
  input  wire       partida,
  input  wire [7:0] dados_byte,
  output wire       saida_serial,
  output wire       pronto,
  output wire       db_partida,
  output wire       db_saida_serial,
  output wire [3:0] db_estado
);

  wire       s_zera;
  wire       s_conta;
  wire       s_carrega;
  wire       s_desloca;
  wire       s_tick;
  wire       s_fim;
  wire       s_saida_serial;
  wire [3:0] s_estado;

  tx_serial_8N1_fd tx_serial_8N1_fd_inst (
    .clk         (clk),
    .arst        (arst),
    .zera        (s_zera),
    .conta       (s_conta),
    .carrega     (s_carrega),
    .desloca     (s_desloca),
    .dados_byte  (dados_byte),
    .saida_serial(s_saida_serial),
    .fim         (s_fim)
  );

  tx_serial_8N1_uc tx_serial_8N1_uc_inst (
    .clk      (clk),
    .arst     (arst),
    .partida  (partida),
    .tick     (s_tick),
    .fim      (s_fim),
    .zera     (s_zera),
    .conta    (s_conta),
    .carrega  (s_carrega),
    .desloca  (s_desloca),
    .pronto   (pronto),
    .db_estado(s_estado)
  );

  contador_m #(
    .Modulo(ClockDiv),
    .Width (9)
  ) contador_m_tick (
    .clk  (clk),
    .arst (arst),
    .sclr (s_zera),
    .conta(1'b1),
    .fim  (s_tick),
    .meio (),
    .q    ()
  );

  assign saida_serial    = s_saida_serial;
  assign db_partida      = partida;
  assign db_saida_serial = s_saida_serial;
  assign db_estado       = s_estado;

endmodule

`default_nettype wire
