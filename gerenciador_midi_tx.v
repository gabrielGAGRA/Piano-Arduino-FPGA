// Descricao: Gerenciador de transmissao de pacotes MIDI de 3 bytes via UART.
// Funcionamento: Modulo estrutural que integra unidade de controle e fluxo de dados
// para transmissao serial de mensagens Note On e Note Off.

`timescale 1ns / 1ps
`default_nettype none

module gerenciador_midi_tx #(
  parameter ClockDiv = 434
)(
  input  wire       clk,
  input  wire       arst,
  input  wire [6:0] nota_desejada,
  input  wire [6:0] velocity_desejado,
  output wire       saida_serial,
  output wire       ocupado
);

  wire s_tem_mudanca_nota;
  wire s_tx_pronto;
  wire s_fim_bytes;
  wire s_carrega_pacote;
  wire s_zera_idx;
  wire s_conta_idx;
  wire s_tx_partida;
  wire s_ocupado_uc;

  gerenciador_midi_tx_uc gerenciador_midi_tx_uc_inst (
    .clk             (clk),
    .arst            (arst),
    .tem_mudanca_nota(s_tem_mudanca_nota),
    .tx_pronto       (s_tx_pronto),
    .fim_bytes       (s_fim_bytes),
    .carrega_pacote  (s_carrega_pacote),
    .zera_idx        (s_zera_idx),
    .conta_idx       (s_conta_idx),
    .tx_partida      (s_tx_partida),
    .ocupado_uc      (s_ocupado_uc)
  );

  gerenciador_midi_tx_fd #(
    .ClockDiv(ClockDiv)
  ) gerenciador_midi_tx_fd_inst (
    .clk              (clk),
    .arst             (arst),
    .carrega_pacote   (s_carrega_pacote),
    .zera_idx         (s_zera_idx),
    .conta_idx        (s_conta_idx),
    .tx_partida       (s_tx_partida),
    .nota_desejada    (nota_desejada),
    .velocity_desejado(velocity_desejado),
    .tem_mudanca_nota (s_tem_mudanca_nota),
    .tx_pronto        (s_tx_pronto),
    .fim_bytes        (s_fim_bytes),
    .saida_serial     (saida_serial)
  );

  assign ocupado = s_ocupado_uc || s_tem_mudanca_nota;

endmodule

`default_nettype wire
