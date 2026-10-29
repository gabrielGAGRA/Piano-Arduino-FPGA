`timescale 1ns / 1ps
`default_nettype none

// Modulo: decodificador_midi
// Descricao: Converte nota_midi (24..107) em (oitava, sustenido, nota_id) via LUT combinacional.
module decodificador_midi (
    input  wire [6:0] nota_midi,
    output reg  [2:0] oitava,
    output reg        sustenido,
    output reg  [2:0] nota_id
);

    always @* begin
        oitava    = 3'd0;
        sustenido = 1'b0;
        nota_id   = 3'd0;

        case (nota_midi)
            // Oitava 1 (24..35)
            7'd24:   begin oitava = 3'd1; sustenido = 1'b0; nota_id = 3'd1; end
            7'd25:   begin oitava = 3'd1; sustenido = 1'b1; nota_id = 3'd1; end
            7'd26:   begin oitava = 3'd1; sustenido = 1'b0; nota_id = 3'd2; end
            7'd27:   begin oitava = 3'd1; sustenido = 1'b1; nota_id = 3'd2; end
            7'd28:   begin oitava = 3'd1; sustenido = 1'b0; nota_id = 3'd3; end
            7'd29:   begin oitava = 3'd1; sustenido = 1'b0; nota_id = 3'd4; end
            7'd30:   begin oitava = 3'd1; sustenido = 1'b1; nota_id = 3'd4; end
            7'd31:   begin oitava = 3'd1; sustenido = 1'b0; nota_id = 3'd5; end
            7'd32:   begin oitava = 3'd1; sustenido = 1'b1; nota_id = 3'd5; end
            7'd33:   begin oitava = 3'd1; sustenido = 1'b0; nota_id = 3'd6; end
            7'd34:   begin oitava = 3'd1; sustenido = 1'b1; nota_id = 3'd6; end
            7'd35:   begin oitava = 3'd1; sustenido = 1'b0; nota_id = 3'd7; end

            // Oitava 2 (36..47)
            7'd36:   begin oitava = 3'd2; sustenido = 1'b0; nota_id = 3'd1; end
            7'd37:   begin oitava = 3'd2; sustenido = 1'b1; nota_id = 3'd1; end
            7'd38:   begin oitava = 3'd2; sustenido = 1'b0; nota_id = 3'd2; end
            7'd39:   begin oitava = 3'd2; sustenido = 1'b1; nota_id = 3'd2; end
            7'd40:   begin oitava = 3'd2; sustenido = 1'b0; nota_id = 3'd3; end
            7'd41:   begin oitava = 3'd2; sustenido = 1'b0; nota_id = 3'd4; end
            7'd42:   begin oitava = 3'd2; sustenido = 1'b1; nota_id = 3'd4; end
            7'd43:   begin oitava = 3'd2; sustenido = 1'b0; nota_id = 3'd5; end
            7'd44:   begin oitava = 3'd2; sustenido = 1'b1; nota_id = 3'd5; end
            7'd45:   begin oitava = 3'd2; sustenido = 1'b0; nota_id = 3'd6; end
            7'd46:   begin oitava = 3'd2; sustenido = 1'b1; nota_id = 3'd6; end
            7'd47:   begin oitava = 3'd2; sustenido = 1'b0; nota_id = 3'd7; end

            // Oitava 3 (48..59)
            7'd48:   begin oitava = 3'd3; sustenido = 1'b0; nota_id = 3'd1; end
            7'd49:   begin oitava = 3'd3; sustenido = 1'b1; nota_id = 3'd1; end
            7'd50:   begin oitava = 3'd3; sustenido = 1'b0; nota_id = 3'd2; end
            7'd51:   begin oitava = 3'd3; sustenido = 1'b1; nota_id = 3'd2; end
            7'd52:   begin oitava = 3'd3; sustenido = 1'b0; nota_id = 3'd3; end
            7'd53:   begin oitava = 3'd3; sustenido = 1'b0; nota_id = 3'd4; end
            7'd54:   begin oitava = 3'd3; sustenido = 1'b1; nota_id = 3'd4; end
            7'd55:   begin oitava = 3'd3; sustenido = 1'b0; nota_id = 3'd5; end
            7'd56:   begin oitava = 3'd3; sustenido = 1'b1; nota_id = 3'd5; end
            7'd57:   begin oitava = 3'd3; sustenido = 1'b0; nota_id = 3'd6; end
            7'd58:   begin oitava = 3'd3; sustenido = 1'b1; nota_id = 3'd6; end
            7'd59:   begin oitava = 3'd3; sustenido = 1'b0; nota_id = 3'd7; end

            // Oitava 4 (60..71)
            7'd60:   begin oitava = 3'd4; sustenido = 1'b0; nota_id = 3'd1; end
            7'd61:   begin oitava = 3'd4; sustenido = 1'b1; nota_id = 3'd1; end
            7'd62:   begin oitava = 3'd4; sustenido = 1'b0; nota_id = 3'd2; end
            7'd63:   begin oitava = 3'd4; sustenido = 1'b1; nota_id = 3'd2; end
            7'd64:   begin oitava = 3'd4; sustenido = 1'b0; nota_id = 3'd3; end
            7'd65:   begin oitava = 3'd4; sustenido = 1'b0; nota_id = 3'd4; end
            7'd66:   begin oitava = 3'd4; sustenido = 1'b1; nota_id = 3'd4; end
            7'd67:   begin oitava = 3'd4; sustenido = 1'b0; nota_id = 3'd5; end
            7'd68:   begin oitava = 3'd4; sustenido = 1'b1; nota_id = 3'd5; end
            7'd69:   begin oitava = 3'd4; sustenido = 1'b0; nota_id = 3'd6; end
            7'd70:   begin oitava = 3'd4; sustenido = 1'b1; nota_id = 3'd6; end
            7'd71:   begin oitava = 3'd4; sustenido = 1'b0; nota_id = 3'd7; end

            // Oitava 5 (72..83)
            7'd72:   begin oitava = 3'd5; sustenido = 1'b0; nota_id = 3'd1; end
            7'd73:   begin oitava = 3'd5; sustenido = 1'b1; nota_id = 3'd1; end
            7'd74:   begin oitava = 3'd5; sustenido = 1'b0; nota_id = 3'd2; end
            7'd75:   begin oitava = 3'd5; sustenido = 1'b1; nota_id = 3'd2; end
            7'd76:   begin oitava = 3'd5; sustenido = 1'b0; nota_id = 3'd3; end
            7'd77:   begin oitava = 3'd5; sustenido = 1'b0; nota_id = 3'd4; end
            7'd78:   begin oitava = 3'd5; sustenido = 1'b1; nota_id = 3'd4; end
            7'd79:   begin oitava = 3'd5; sustenido = 1'b0; nota_id = 3'd5; end
            7'd80:   begin oitava = 3'd5; sustenido = 1'b1; nota_id = 3'd5; end
            7'd81:   begin oitava = 3'd5; sustenido = 1'b0; nota_id = 3'd6; end
            7'd82:   begin oitava = 3'd5; sustenido = 1'b1; nota_id = 3'd6; end
            7'd83:   begin oitava = 3'd5; sustenido = 1'b0; nota_id = 3'd7; end

            // Oitava 6 (84..95)
            7'd84:   begin oitava = 3'd6; sustenido = 1'b0; nota_id = 3'd1; end
            7'd85:   begin oitava = 3'd6; sustenido = 1'b1; nota_id = 3'd1; end
            7'd86:   begin oitava = 3'd6; sustenido = 1'b0; nota_id = 3'd2; end
            7'd87:   begin oitava = 3'd6; sustenido = 1'b1; nota_id = 3'd2; end
            7'd88:   begin oitava = 3'd6; sustenido = 1'b0; nota_id = 3'd3; end
            7'd89:   begin oitava = 3'd6; sustenido = 1'b0; nota_id = 3'd4; end
            7'd90:   begin oitava = 3'd6; sustenido = 1'b1; nota_id = 3'd4; end
            7'd91:   begin oitava = 3'd6; sustenido = 1'b0; nota_id = 3'd5; end
            7'd92:   begin oitava = 3'd6; sustenido = 1'b1; nota_id = 3'd5; end
            7'd93:   begin oitava = 3'd6; sustenido = 1'b0; nota_id = 3'd6; end
            7'd94:   begin oitava = 3'd6; sustenido = 1'b1; nota_id = 3'd6; end
            7'd95:   begin oitava = 3'd6; sustenido = 1'b0; nota_id = 3'd7; end

            // Oitava 7 (96..107)
            7'd96:   begin oitava = 3'd7; sustenido = 1'b0; nota_id = 3'd1; end
            7'd97:   begin oitava = 3'd7; sustenido = 1'b1; nota_id = 3'd1; end
            7'd98:   begin oitava = 3'd7; sustenido = 1'b0; nota_id = 3'd2; end
            7'd99:   begin oitava = 3'd7; sustenido = 1'b1; nota_id = 3'd2; end
            7'd100:  begin oitava = 3'd7; sustenido = 1'b0; nota_id = 3'd3; end
            7'd101:  begin oitava = 3'd7; sustenido = 1'b0; nota_id = 3'd4; end
            7'd102:  begin oitava = 3'd7; sustenido = 1'b1; nota_id = 3'd4; end
            7'd103:  begin oitava = 3'd7; sustenido = 1'b0; nota_id = 3'd5; end
            7'd104:  begin oitava = 3'd7; sustenido = 1'b1; nota_id = 3'd5; end
            7'd105:  begin oitava = 3'd7; sustenido = 1'b0; nota_id = 3'd6; end
            7'd106:  begin oitava = 3'd7; sustenido = 1'b1; nota_id = 3'd6; end
            7'd107:  begin oitava = 3'd7; sustenido = 1'b0; nota_id = 3'd7; end

            default: begin oitava = 3'd0; sustenido = 1'b0; nota_id = 3'd0; end
        endcase
    end

endmodule

`default_nettype wire
