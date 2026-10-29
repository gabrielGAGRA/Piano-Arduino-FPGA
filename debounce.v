// Descrição: Filtro antirruido (debounce) sincrono parametrizavel para botoes.
// Funcionamento: Sincroniza entradas em dois estagios de flip-flop e
// acumula amostras consistentes ate atingir TempoFiltro antes de chavear a saida.

`timescale 1ns / 1ps
`default_nettype none

module debounce #(
  parameter Width       = 1,
  parameter TempoFiltro = 100_000
)(
  input  wire             clk,
  input  wire             arst,
  input  wire [Width-1:0] in,
  output reg  [Width-1:0] out
);

  localparam [19:0] TempoFiltroVal = TempoFiltro[19:0];

  reg [19:0]      contadores_reg [0:Width-1];
  reg [Width-1:0] sync0_reg;
  reg [Width-1:0] sync1_reg;
  integer i;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      out       <= {Width{1'b0}};
      sync0_reg <= {Width{1'b0}};
      sync1_reg <= {Width{1'b0}};
      for (i = 0; i < Width; i = i + 1) begin
        contadores_reg[i] <= 20'd0;
      end
    end else begin
      sync0_reg <= in;
      sync1_reg <= sync0_reg;

      for (i = 0; i < Width; i = i + 1) begin
        if (sync1_reg[i] == out[i]) begin
          contadores_reg[i] <= 20'd0;
        end else begin
          contadores_reg[i] <= contadores_reg[i] + 20'd1;
          if (contadores_reg[i] >= TempoFiltroVal) begin
            out[i]            <= sync1_reg[i];
            contadores_reg[i] <= 20'd0;
          end
        end
      end
    end
  end

endmodule

`default_nettype wire
