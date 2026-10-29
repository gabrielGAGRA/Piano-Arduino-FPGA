`timescale 1ns / 1ps
`default_nettype none

/*
 *  Descricao : detector de borda
 *              gera um pulso na saida de 1 periodo de clock
 *              a partir da detecao da borda de subida da entrada
 *              sinal de reset ativo em alto
 */
 
module edge_detector (
    input  wire clock,
    input  wire reset,
    input  wire sinal,
    output wire pulso
);

    reg sinal_d1_q;
    reg sinal_d2_q;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            sinal_d1_q <= 1'b0;
            sinal_d2_q <= 1'b0;
        end else begin
            sinal_d1_q <= sinal;
            sinal_d2_q <= sinal_d1_q;
        end
    end

    assign pulso = ~sinal_d2_q & sinal_d1_q;

endmodule

`default_nettype wire