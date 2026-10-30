// Descricao: Decodificador para exibir simbolo sustenido '#' em display 7 seg.
// Funcionamento: Ativa segmentos especificos (ativo em nivel baixo) para
// desenhar o glifo '#' quando sustenido estiver em nivel alto.

`timescale 1ns / 1ps
`default_nettype none

module display_sustenido (
  input  wire       sustenido,
  output wire [6:0] display
);

  // Padrao do '#' no display: apaga se sustenido for 0
  assign display = sustenido ? 7'b0110110 : 7'b1111111;

endmodule

`default_nettype wire
