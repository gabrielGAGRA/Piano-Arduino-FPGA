`timescale 1ns / 1ps
`default_nettype none

/*
 * Descricao : Fluxo de dados do transmissor serial assincrono 8N1.
 */
module tx_serial_8N1_fd (
    input  wire       clock,
    input  wire       reset,
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
    assign s_dados[0]   = 1'b1; // repouso inicial
    assign s_dados[1]   = 1'b0; // start bit
    assign s_dados[9:2] = dados_byte[7:0]; // 8 bits de dados (LSB primeiro)
    assign s_dados[10]  = 1'b1; // stop bit

    deslocador_n #(
        .N (11)
    ) u_deslocador_n (
        .clock          (clock),
        .reset          (reset),
        .carrega        (carrega),
        .desloca        (desloca),
        .entrada_serial (1'b1),
        .dados          (s_dados),
        .saida          (s_saida)
    );

    contador_m #(
        .M (12),
        .N (4)
    ) u_contador_m (
        .clock (clock),
        .reset (reset),
        .sclr  (zera),
        .conta (conta),
        .q     (),
        .fim   (fim),
        .meio  ()
    );

    assign saida_serial = s_saida[0];

endmodule

`default_nettype wire
