`timescale 1ns / 1ps
`default_nettype none

/* 
 *  Descricao : Sincronizador de 2 estagios de flip-flops para prevencao
 *              de metaestabilidade em sinais assincronos.
 */

module sincronizador #(
    parameter WIDTH = 1,
    parameter [WIDTH-1:0] INIT_VALUE = {WIDTH{1'b0}}
)(
    input  wire                  clock,
    input  wire                  reset,
    input  wire [WIDTH-1:0]      async_in,
    output wire [WIDTH-1:0]      sync_out
);

    reg [WIDTH-1:0] sync0_reg;
    reg [WIDTH-1:0] sync1_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            sync0_reg <= INIT_VALUE;
            sync1_reg <= INIT_VALUE;
        end else begin
            sync0_reg <= async_in;
            sync1_reg <= sync0_reg;
        end
    end

    assign sync_out = sync1_reg;

endmodule

`default_nettype wire
