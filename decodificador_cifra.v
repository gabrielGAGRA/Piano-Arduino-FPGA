`timescale 1ns / 1ps
`default_nettype none

// Descricao: Converte o ID da nota (1 a 7) para o respectivo caractere (A-G) no 7-seg.
module decodificador_cifra (
    input  wire [2:0] nota_id,
    output reg  [6:0] display
);

    always @(*) begin
        case (nota_id)
            3'd1: display = 7'b1000110; // Dó = C
            3'd2: display = 7'b0100001; // Ré = d
            3'd3: display = 7'b0000110; // Mi = E
            3'd4: display = 7'b0001110; // Fá = F
            3'd5: display = 7'b0010000; // Sol = G
            3'd6: display = 7'b0001000; // Lá = A
            3'd7: display = 7'b0000011; // Si = b
            default: display = 7'b1111111; // Desligado se nao houver nota
        endcase
    end

endmodule

`default_nettype wire
