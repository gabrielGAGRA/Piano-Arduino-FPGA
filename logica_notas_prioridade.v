`timescale 1ns / 1ps
`default_nettype none

// Descricao: Implementa a prioridade da ultima tecla pressionada.
module logica_notas_prioridade (
    input  wire       clock,
    input  wire       reset,
    input  wire [6:0] botoes,       
    output reg  [2:0] nota_id,
    output wire       tem_nota
);

    reg [6:0] botoes_ant_reg;
    assign tem_nota = |botoes;

    wire nota_valida = (nota_id != 3'd0);
    wire [2:0] nota_idx = nota_valida ? (nota_id - 3'd1) : 3'd0;
    wire tecla_ativa = nota_valida & botoes[nota_idx];

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            nota_id        <= 3'd0;
            botoes_ant_reg <= 7'd0;
        end else begin
            botoes_ant_reg <= botoes;

            // Detecta borda de subida em cada botao (override da ultima nota tocada)
            if      (botoes[0] && !botoes_ant_reg[0]) nota_id <= 3'd1;
            else if (botoes[1] && !botoes_ant_reg[1]) nota_id <= 3'd2;
            else if (botoes[2] && !botoes_ant_reg[2]) nota_id <= 3'd3;
            else if (botoes[3] && !botoes_ant_reg[3]) nota_id <= 3'd4;
            else if (botoes[4] && !botoes_ant_reg[4]) nota_id <= 3'd5;
            else if (botoes[5] && !botoes_ant_reg[5]) nota_id <= 3'd6;
            else if (botoes[6] && !botoes_ant_reg[6]) nota_id <= 3'd7;
            
            // Fallback seguro em duas notas: Se a ultima nota ativa foi solta,
            // mas outras estao pressionadas, volta para a de maior indice
            if (tem_nota && !tecla_ativa) begin
                if      (botoes[6]) nota_id <= 3'd7;
                else if (botoes[5]) nota_id <= 3'd6;
                else if (botoes[4]) nota_id <= 3'd5;
                else if (botoes[3]) nota_id <= 3'd4;
                else if (botoes[2]) nota_id <= 3'd3;
                else if (botoes[1]) nota_id <= 3'd2;
                else if (botoes[0]) nota_id <= 3'd1;
            end
        end
    end

endmodule

`default_nettype wire