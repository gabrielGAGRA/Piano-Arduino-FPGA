// Descrição: Multiplexador 40 para 1 para selecao de dados das musicas (ROM/RAM).
// Funcionamento: Roteia o barramento de dados de 30 bits correspondente
// ao indice da musica selecionada (0 a 38 na ROM, 39 na RAM).

`timescale 1ns / 1ps
`default_nettype none

module mux_musicas (
  input  wire [5:0]  sel,
  input  wire [29:0] d0,
  input  wire [29:0] d1,
  input  wire [29:0] d2,
  input  wire [29:0] d3,
  input  wire [29:0] d4,
  input  wire [29:0] d5,
  input  wire [29:0] d6,
  input  wire [29:0] d7,
  input  wire [29:0] d8,
  input  wire [29:0] d9,
  input  wire [29:0] d10,
  input  wire [29:0] d11,
  input  wire [29:0] d12,
  input  wire [29:0] d13,
  input  wire [29:0] d14,
  input  wire [29:0] d15,
  input  wire [29:0] d16,
  input  wire [29:0] d17,
  input  wire [29:0] d18,
  input  wire [29:0] d19,
  input  wire [29:0] d20,
  input  wire [29:0] d21,
  input  wire [29:0] d22,
  input  wire [29:0] d23,
  input  wire [29:0] d24,
  input  wire [29:0] d25,
  input  wire [29:0] d26,
  input  wire [29:0] d27,
  input  wire [29:0] d28,
  input  wire [29:0] d29,
  input  wire [29:0] d30,
  input  wire [29:0] d31,
  input  wire [29:0] d32,
  input  wire [29:0] d33,
  input  wire [29:0] d34,
  input  wire [29:0] d35,
  input  wire [29:0] d36,
  input  wire [29:0] d37,
  input  wire [29:0] d38,
  input  wire [29:0] d39,
  output reg  [29:0] out
);

  always @* begin
    out = 30'd0;
    case (sel)
      6'd0:    out = d0;
      6'd1:    out = d1;
      6'd2:    out = d2;
      6'd3:    out = d3;
      6'd4:    out = d4;
      6'd5:    out = d5;
      6'd6:    out = d6;
      6'd7:    out = d7;
      6'd8:    out = d8;
      6'd9:    out = d9;
      6'd10:   out = d10;
      6'd11:   out = d11;
      6'd12:   out = d12;
      6'd13:   out = d13;
      6'd14:   out = d14;
      6'd15:   out = d15;
      6'd16:   out = d16;
      6'd17:   out = d17;
      6'd18:   out = d18;
      6'd19:   out = d19;
      6'd20:   out = d20;
      6'd21:   out = d21;
      6'd22:   out = d22;
      6'd23:   out = d23;
      6'd24:   out = d24;
      6'd25:   out = d25;
      6'd26:   out = d26;
      6'd27:   out = d27;
      6'd28:   out = d28;
      6'd29:   out = d29;
      6'd30:   out = d30;
      6'd31:   out = d31;
      6'd32:   out = d32;
      6'd33:   out = d33;
      6'd34:   out = d34;
      6'd35:   out = d35;
      6'd36:   out = d36;
      6'd37:   out = d37;
      6'd38:   out = d38;
      6'd39:   out = d39;
      default: out = 30'd0;
    endcase
  end

endmodule

`default_nettype wire
