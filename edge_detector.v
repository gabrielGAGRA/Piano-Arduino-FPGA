// Descricao: Detector de borda de subida com saida de 1 periodo de clock.
// Funcionamento: Pipeline de 2 registradores em cascata que detecta transicao 0->1
// no sinal de entrada e gera pulso de 1 ciclo sincronizado com o clock local.

`timescale 1ns / 1ps
`default_nettype none

module edge_detector (
  input  wire clk,
  input  wire arst,
  input  wire sinal,
  output wire pulso
);

  reg sinal_d1_reg;
  reg sinal_d2_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      sinal_d1_reg <= 1'b0;
      sinal_d2_reg <= 1'b0;
    end else begin
      sinal_d1_reg <= sinal;
      sinal_d2_reg <= sinal_d1_reg;
    end
  end

  assign pulso = sinal_d1_reg && !sinal_d2_reg;

endmodule

`default_nettype wire
