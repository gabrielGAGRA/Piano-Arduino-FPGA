`timescale 1ns / 1ps
`default_nettype none

/*
 * Descricao : Transmissor serial assincrono 8N1 (8 bits de dados,
 *             sem paridade, 1 stop bit) a 115200 bauds (por padrao).
 */
module tx_serial_8N1 #(
    parameter CLOCK_DIV = 434
) (
    input  wire       clock,
    input  wire       reset,
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

    tx_serial_8N1_fd u_fd (
        .clock        (clock),
        .reset        (reset),
        .zera         (s_zera),
        .conta        (s_conta),
        .carrega      (s_carrega),
        .desloca      (s_desloca),
        .dados_byte   (dados_byte),
        .saida_serial (s_saida_serial),
        .fim          (s_fim)
    );

    tx_serial_8N1_uc u_uc (
        .clock     (clock),
        .reset     (reset),
        .partida   (partida),
        .tick      (s_tick),
        .fim       (s_fim),
        .zera      (s_zera),
        .conta     (s_conta),
        .carrega   (s_carrega),
        .desloca   (s_desloca),
        .pronto    (pronto),
        .db_estado (s_estado)
    );

    contador_m #(
        .M (CLOCK_DIV),
        .N (9)
    ) u_contador_tick (
        .clock (clock),
        .reset (reset),
        .sclr  (s_zera),
        .conta (1'b1),
        .q     (),
        .fim   (s_tick),
        .meio  ()
    );

    assign saida_serial    = s_saida_serial;
    assign db_partida      = partida;
    assign db_saida_serial = s_saida_serial;
    assign db_estado       = s_estado;

endmodule

`default_nettype wire
