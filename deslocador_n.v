// Descricao: Registrador de deslocamento parametrizavel de N bits.
// Funcionamento: Suporta carga paralela sincrona e deslocamento a direita
// com insercao serial no bit mais significativo.

`timescale 1ns / 1ps
`default_nettype none

module deslocador_n #(
  parameter Width = 11
)(
  input  wire             clk,
  input  wire             arst,
  input  wire             carrega,
  input  wire             desloca,
  input  wire             entrada_serial,
  input  wire [Width-1:0] dados,
  output wire [Width-1:0] saida
);

  reg [Width-1:0] registrador_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      registrador_reg <= {Width{1'b1}};
    end else if (carrega) begin
      registrador_reg <= dados;
    end else if (desloca) begin
      registrador_reg <= {entrada_serial, registrador_reg[Width-1:1]};
    end
  end

  assign saida = registrador_reg;

endmodule

`default_nettype wire
