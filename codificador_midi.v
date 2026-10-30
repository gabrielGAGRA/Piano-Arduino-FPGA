// Descricao: Codificador de nota musical (oitava, sustenido e ID) para MIDI.
// Funcionamento: Realiza tabela combinacional para calcular a nota MIDI (0-127)
// com base na oitava (1 a 7), ID da nota (1 a 7) e presenca de sustenido.

`timescale 1ns / 1ps
`default_nettype none

module codificador_midi (
  input  wire [2:0] oitava,
  input  wire       sustenido,
  input  wire [2:0] nota_id,
  output reg  [6:0] nota_midi
);

  reg [6:0] base_oitava;
  reg [6:0] offset_nota;

  always @* begin
    base_oitava = 7'd0;
    offset_nota = 7'd0;
    nota_midi   = 7'd0;

    case (oitava)
      3'd1:    base_oitava = 7'd24;
      3'd2:    base_oitava = 7'd36;
      3'd3:    base_oitava = 7'd48;
      3'd4:    base_oitava = 7'd60;
      3'd5:    base_oitava = 7'd72;
      3'd6:    base_oitava = 7'd84;
      3'd7:    base_oitava = 7'd96;
      default: base_oitava = 7'd0;
    endcase

    case (nota_id)
      3'd1:    offset_nota = sustenido ? 7'd1 : 7'd0;   // Do / Do#
      3'd2:    offset_nota = sustenido ? 7'd3 : 7'd2;   // Re / Re#
      3'd3:    offset_nota = sustenido ? 7'd5 : 7'd4;   // Mi / Mi#
      3'd4:    offset_nota = sustenido ? 7'd6 : 7'd5;   // Fa / Fa#
      3'd5:    offset_nota = sustenido ? 7'd8 : 7'd7;   // Sol / Sol#
      3'd6:    offset_nota = sustenido ? 7'd10 : 7'd9;  // La / La#
      3'd7:    offset_nota = sustenido ? ((oitava < 3'd7) ? 7'd12 : 7'd11) : 7'd11;
      default: offset_nota = 7'd0;
    endcase

    if ((oitava == 3'd0) || (nota_id == 3'd0)) begin
      nota_midi = 7'd0;
    end else begin
      nota_midi = base_oitava + offset_nota;
    end
  end

endmodule

`default_nettype wire
