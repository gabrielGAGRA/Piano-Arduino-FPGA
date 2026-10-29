`timescale 1ns / 1ps
`default_nettype none

/* 
 *  Descricao : Unidade de Controle (FSM) do Metronomo Mecanico.
 *              Controla o movimento oscilatorio suave do servomotor e
 *              o retorno a posicao central em repouso.
 */

module metronomo_uc (
    input  wire clock,
    input  wire reset,
    input  wire habilita,
    input  wire fim_passo,
    input  wire fim_curso_min, // posicao == 3'd0
    input  wire fim_curso_max, // posicao == 3'd7

    output reg  zera_tempo,
    output reg  incrementa_pos,
    output reg  decrementa_pos,
    output reg  pos_repouso,   // forca posicao 3 (centro)
    output reg  pulso_beat
);

    localparam [1:0] IDLE     = 2'd0,
                     MOVE_DIR = 2'd1,
                     MOVE_ESQ = 2'd2;

    reg [1:0] state_reg;
    reg [1:0] state_next;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state_reg <= IDLE;
        end else begin
            state_reg <= state_next;
        end
    end

    always @* begin
        // Valores padrao para evitar latches
        state_next     = state_reg;
        zera_tempo     = 1'b0;
        incrementa_pos = 1'b0;
        decrementa_pos = 1'b0;
        pos_repouso    = 1'b0;
        pulso_beat     = 1'b0;

        case (state_reg)
            IDLE: begin
                zera_tempo  = 1'b1;
                pos_repouso = 1'b1;
                if (habilita) begin
                    state_next = MOVE_DIR;
                end
            end

            MOVE_DIR: begin
                if (!habilita) begin
                    state_next = IDLE;
                end else if (fim_passo) begin
                    zera_tempo = 1'b1;
                    if (fim_curso_max) begin
                        pulso_beat     = 1'b1; // Beat no extremo direito
                        decrementa_pos = 1'b1;
                        state_next     = MOVE_ESQ;
                    end else begin
                        incrementa_pos = 1'b1;
                    end
                end
            end

            MOVE_ESQ: begin
                if (!habilita) begin
                    state_next = IDLE;
                end else if (fim_passo) begin
                    zera_tempo = 1'b1;
                    if (fim_curso_min) begin
                        pulso_beat     = 1'b1; // Beat no extremo esquerdo
                        incrementa_pos = 1'b1;
                        state_next     = MOVE_DIR;
                    end else begin
                        decrementa_pos = 1'b1;
                    end
                end
            end

            default: state_next = IDLE;
        endcase
    end

endmodule

`default_nettype wire
