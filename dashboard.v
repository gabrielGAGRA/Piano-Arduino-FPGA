// Descricao: Dashboard central do piano digital.
// Funcionamento: Encapsula o painel de 7 segmentos e LEDs para apresentar o
// estado operacional do instrumento (modo, oitava, musica, nota e volume).

`timescale 1ns / 1ps
`default_nettype none
module dashboard (
  input  wire [1:0] modo_ativo,
  input  wire [2:0] oitava_atual,
  input  wire       sustenido_atual,
  input  wire [5:0] sel_musica,
  input  wire [2:0] id_nota,
  input  wire       pwm_out,
  input  wire [2:0] volume,
  input  wire       mostra_vol,
  input  wire [6:0] nota_display,
  output wire [6:0] hex5_modo,
  output wire [6:0] hex4_oitava,
  output wire [6:0] hex3_musica_dezena,
  output wire [6:0] hex2_musica_unidade,
  output wire [6:0] hex1_nota,
  output wire [6:0] hex0_sustenido,
  output wire       led_sustenido,
  output wire [6:0] led_vermelho
);

  painel_display_leds painel_display_leds_inst (
    .modo_ativo        (modo_ativo),
    .oitava_atual      (oitava_atual),
    .sustenido_atual   (sustenido_atual),
    .sel_musica        (sel_musica),
    .id_nota           (id_nota),
    .pwm_out           (pwm_out),
    .volume            (volume),
    .mostra_vol        (mostra_vol),
    .nota_display      (nota_display),
    .hex5_modo         (hex5_modo),
    .hex4_oitava       (hex4_oitava),
    .hex3_musica_dezena(hex3_musica_dezena),
    .hex2_musica_unidade(hex2_musica_unidade),
    .hex1_nota         (hex1_nota),
    .hex0_sustenido    (hex0_sustenido),
    .led_sustenido     (led_sustenido),
    .led_vermelho      (led_vermelho)
  );

endmodule

`default_nettype wire
