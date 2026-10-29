`timescale 1ns / 1ps
`default_nettype none

// Modulo: codificador_midi
// Descricao: Converte (oitava, sustenido, nota_id) para numero de nota MIDI (24..107, 0=silencio).
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
            3'd1:    offset_nota = sustenido ? 7'd1  : 7'd0;
            3'd2:    offset_nota = sustenido ? 7'd3  : 7'd2;
            3'd3:    offset_nota = sustenido ? 7'd5  : 7'd4;
            3'd4:    offset_nota = sustenido ? 7'd6  : 7'd5;
            3'd5:    offset_nota = sustenido ? 7'd8  : 7'd7;
            3'd6:    offset_nota = sustenido ? 7'd10 : 7'd9;
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
