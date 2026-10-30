// Descricao: Decodificador hexadecimal para display de 7 segmentos (catodo/anodo).
// Funcionamento: Converte nibble de entrada [4:0] em segmentos a-g ativos
// em nivel baixo com suporte a caracteres e display apagado (5'h1F).

`timescale 1ns / 1ps
`default_nettype none

module hexa7seg (
  input  wire [4:0] hexa,
  output reg  [6:0] display
);

  always @* begin
    case (hexa)
      5'h00:   display = 7'b1000000;
      5'h01:   display = 7'b1111001;
      5'h02:   display = 7'b0100100;
      5'h03:   display = 7'b0110000;
      5'h04:   display = 7'b0011001;
      5'h05:   display = 7'b0010010;
      5'h06:   display = 7'b0000010;
      5'h07:   display = 7'b1111000;
      5'h08:   display = 7'b0000000;
      5'h09:   display = 7'b0010000;
      5'h0A:   display = 7'b0001000;
      5'h0B:   display = 7'b0000011;
      5'h0C:   display = 7'b1000110;
      5'h0D:   display = 7'b0100001;
      5'h0E:   display = 7'b0000110;
      5'h0F:   display = 7'b0001110;
      default: display = 7'b1111111;
    endcase
  end

endmodule

`default_nettype wire
