`timescale 1ns / 1ps
`default_nettype none

// Descricao: Filtro generico e parametrizavel para debouncing de botoes mecanicos.
module debounce #(
    parameter WIDTH = 1, 
    parameter TEMPO_FILTRO = 100_000
) (
    input  wire                  clock,
    input  wire                  reset,
    input  wire [WIDTH-1:0]      in,
    output reg  [WIDTH-1:0]      out
);

    localparam [19:0] TEMPO_FILTRO_VAL = TEMPO_FILTRO[19:0];

    reg [19:0] contadores_reg [WIDTH-1:0];
    reg [WIDTH-1:0] sync0_reg;
    reg [WIDTH-1:0] sync1_reg;
    integer i;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            out <= {WIDTH{1'b0}};
            sync0_reg <= {WIDTH{1'b0}};
            sync1_reg <= {WIDTH{1'b0}};
            for (i = 0; i < WIDTH; i = i + 1) begin
                contadores_reg[i] <= 20'd0;
            end
        end else begin
            sync0_reg <= in;
            sync1_reg <= sync0_reg;

            for (i = 0; i < WIDTH; i = i + 1) begin
                if (sync1_reg[i] == out[i]) begin
                    contadores_reg[i] <= 20'd0;
                end else begin
                    contadores_reg[i] <= contadores_reg[i] + 20'd1;
                    if (contadores_reg[i] >= TEMPO_FILTRO_VAL) begin
                        out[i] <= sync1_reg[i];
                        contadores_reg[i] <= 20'd0;
                    end
                end
            end
        end
    end

endmodule

`default_nettype wire