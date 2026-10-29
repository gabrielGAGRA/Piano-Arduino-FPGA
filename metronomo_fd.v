`timescale 1ns / 1ps
`default_nettype none

/* 
 *  Descricao : Fluxo de Dados (Datapath) do Metronomo Mecanico.
 *              Contem o contador de tempo de cada passo angular e
 *              o registrador de posicao angular do servomotor (0 a 7).
 */

module metronomo_fd (
    input  wire        clock,
    input  wire        reset,
    input  wire [31:0] t_passo,
    input  wire        zera_tempo,
    input  wire        incrementa_pos,
    input  wire        decrementa_pos,
    input  wire        pos_repouso,

    output wire        fim_passo,
    output wire        fim_curso_min,
    output wire        fim_curso_max,
    output wire [2:0]  posicao_servo
);

    reg [31:0] contador_tempo_reg;
    reg [2:0]  posicao_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            contador_tempo_reg <= 32'd0;
        end else if (zera_tempo) begin
            contador_tempo_reg <= 32'd0;
        end else begin
            contador_tempo_reg <= contador_tempo_reg + 32'd1;
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            posicao_reg <= 3'd3; // Posicao central de repouso (~88°-90°)
        end else if (pos_repouso) begin
            posicao_reg <= 3'd3;
        end else if (incrementa_pos) begin
            posicao_reg <= posicao_reg + 3'd1;
        end else if (decrementa_pos) begin
            posicao_reg <= posicao_reg - 3'd1;
        end
    end

    assign fim_passo      = (contador_tempo_reg >= t_passo - 32'd1);
    assign fim_curso_min  = (posicao_reg == 3'd0);
    assign fim_curso_max  = (posicao_reg == 3'd7);
    assign posicao_servo  = posicao_reg;

endmodule

`default_nettype wire
