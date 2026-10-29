`timescale 1ns / 1ps
`default_nettype none

/* 
 *  Descricao : Top-Level do Subsistema de Metronomo Mecanico.
 *              Interliga a Unidade de Controle (FSM), o Fluxo de Dados (Datapath)
 *              e o Gerador PWM do Servomotor SG90 (calibrado para 30° de amplitude).
 */

module metronomo #(
    parameter CLOCK_FREQ = 50_000_000
) (
    input  wire        clock,
    input  wire        reset,
    input  wire        habilita,
    input  wire [31:0] t_passo,

    output wire        servo_controle,
    output wire        pulso_beat,
    output wire [2:0]  posicao_servo
);

    wire       w_fim_passo;
    wire       w_fim_curso_min;
    wire       w_fim_curso_max;
    wire       w_zera_tempo;
    wire       w_incrementa_pos;
    wire       w_decrementa_pos;
    wire       w_pos_repouso;
    wire [2:0] w_posicao_servo;

    // Unidade de Controle (FSM)
    metronomo_uc u_uc (
        .clock         (clock),
        .reset         (reset),
        .habilita      (habilita),
        .fim_passo     (w_fim_passo),
        .fim_curso_min (w_fim_curso_min),
        .fim_curso_max (w_fim_curso_max),
        .zera_tempo    (w_zera_tempo),
        .incrementa_pos(w_incrementa_pos),
        .decrementa_pos(w_decrementa_pos),
        .pos_repouso   (w_pos_repouso),
        .pulso_beat    (pulso_beat)
    );

    // Fluxo de Dados (Datapath)
    metronomo_fd u_fd (
        .clock         (clock),
        .reset         (reset),
        .t_passo       (t_passo),
        .zera_tempo    (w_zera_tempo),
        .incrementa_pos(w_incrementa_pos),
        .decrementa_pos(w_decrementa_pos),
        .pos_repouso   (w_pos_repouso),
        .fim_passo     (w_fim_passo),
        .fim_curso_min (w_fim_curso_min),
        .fim_curso_max (w_fim_curso_max),
        .posicao_servo (w_posicao_servo)
    );

    // Controlador PWM do Servomotor (50 Hz, 8 larguras cobrindo 30°)
    controle_servo_8 #(
        .CONF_PERIODO(CLOCK_FREQ / 32'd50) // 1.000.000 ciclos = 20 ms
    ) u_servo (
        .clock      (clock),
        .reset      (reset),
        .posicao    (w_posicao_servo),
        .controle   (servo_controle),
        .db_reset   (),
        .db_posicao (),
        .db_controle()
    );

    assign posicao_servo = w_posicao_servo;

endmodule

`default_nettype wire
