// Descricao: Converte ID da nota musical (1 a 7) para caractere de cifra (C, d, E, F, G, A, b).
// Funcionamento: Decodifica nota_id [2:0] diretamente nos segmentos a-g
// ativos em nivel baixo para exibicao no display HEX1.

`timescale 1ns / 1ps
`default_nettype none

module decodificador_cifra (
  input  wire [2:0] nota_id,
  output reg  [6:0] display
);

  always @* begin
    case (nota_id)
      3'd1:    display = 7'b1000110; // Do = C
      3'd2:    display = 7'b0100001; // Re = d
      3'd3:    display = 7'b0000110; // Mi = E
      3'd4:    display = 7'b0001110; // Fa = F
      3'd5:    display = 7'b0010000; // Sol = G
      3'd6:    display = 7'b0001000; // La = A
      3'd7:    display = 7'b0000011; // Si = b
      default: display = 7'b1111111; // Apagado
    endcase
  end

endmodule

`default_nettype wire
