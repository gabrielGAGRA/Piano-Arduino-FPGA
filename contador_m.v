`timescale 1ns / 1ps
`default_nettype none

/*
 * Descricao : contador parametrizavel, modulo m, com parametros 
 *             M (modulo do contador) e N (numero de bits),
 *             sinais para clear assincrono (zera_as) e sincrono (zera_s)
 *             e saidas de fim e meio de contagem
 */
module contador_m #(
    parameter M = 2048, 
    parameter N = 11
) (
    input  wire         clock,
    input  wire         reset,
    input  wire         sclr,
    input  wire         conta,
    output reg  [N-1:0] q,
    output wire         fim,
    output wire         meio
);

    localparam [N-1:0] M_VAL  = M[N-1:0];
    localparam [N-1:0] M_FIM  = M_VAL - {{(N-1){1'b0}}, 1'b1};
    localparam [N-1:0] M_MEIO = (M[N-1:0] >> 1'b1) - {{(N-1){1'b0}}, 1'b1};

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            q <= {N{1'b0}};
        end else if (sclr) begin
            q <= {N{1'b0}};
        end else if (conta) begin
            if (q == M_FIM) begin
                q <= {N{1'b0}};
            end else begin
                q <= q + {{(N-1){1'b0}}, 1'b1};
            end
        end
    end

    assign fim = (q == M_FIM);
    assign meio = (q == M_MEIO);

endmodule

`default_nettype wire