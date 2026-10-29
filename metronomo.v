// Descrição: Top-level do subsistema de metronomo mecanico com servomotor.
// Funcionamento: Interliga FSM de oscilacao, datapath de temporizacao angular
// e gerador de pulso PWM de 20 ms para controle do servomotor SG90.

`timescale 1ns / 1ps
`default_nettype none

module metronomo #(
  parameter ClockFreq = 50_000_000
)(
  input  wire        clk,
  input  wire        arst,
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

  metronomo_uc metronomo_uc_inst (
    .clk           (clk),
    .arst          (arst),
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

  metronomo_fd metronomo_fd_inst (
    .clk           (clk),
    .arst          (arst),
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

  controle_servo_8 #(
    .ConfPeriodo(ClockFreq / 32'd50)
  ) controle_servo_8_inst (
    .clk     (clk),
    .arst    (arst),
    .posicao (w_posicao_servo),
    .controle(servo_controle)
  );

  assign posicao_servo = w_posicao_servo;

endmodule

`default_nettype wire
