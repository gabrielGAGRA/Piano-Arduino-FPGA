// Descricao: Painel de decodificacao de displays de 7 segmentos e LEDs do piano.
// Funcionamento: Decodifica status de operacao (modo, oitava, musica e volume)
// para os displays HEX0-HEX5 e mascara os LEDs vermelhos com o sinal modulado por PWM.

`timescale 1ns / 1ps
`default_nettype none

module painel_display_leds (
  input  wire [1:0] modo_ativo,
  input  wire [2:0] oitava_atual,
  input  wire       sustenido_atual,
  input  wire [5:0] sel_musica,
  input  wire [2:0] id_nota,
  input  wire       pwm_out,
  input  wire [1:0] volume,
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

  // HEX5: Modo atual ou centena do volume
  wire [6:0] hex5_normal;
  hexa7seg hexa7seg_disp5 (
    .hexa({3'b000, modo_ativo}),
    .display(hex5_normal)
  );

  assign hex5_modo = mostra_vol ?
    ((volume == 2'd0) ? 7'h79 : 7'h7F) :
    hex5_normal;

  // HEX4: Oitava atual ou dezena do volume (0, 7, 5)
  wire [6:0] hex4_normal;
  hexa7seg hexa7seg_disp4 (
    .hexa({2'b00, oitava_atual}),
    .display(hex4_normal)
  );

  assign hex4_oitava = mostra_vol ?
    ((volume == 2'd0) ? 7'h40 :
      (volume == 2'd1) ? 7'h78 : 7'h12) :
    hex4_normal;

  // HEX3 e HEX2: Decodificacao BCD da musica (00 a 49)
  wire [5:0] actual_idx = sel_musica;
  wire [5:0] diff40 = actual_idx - 6'd40;
  wire [5:0] diff30 = actual_idx - 6'd30;
  wire [5:0] diff20 = actual_idx - 6'd20;
  wire [5:0] diff10 = actual_idx - 6'd10;
  reg  [3:0] musica_dez_val;
  reg  [3:0] musica_uni_val;

  always @* begin
    if (actual_idx >= 6'd40) begin
      musica_dez_val = 4'd4;
      musica_uni_val = diff40[3:0];
    end else if (actual_idx >= 6'd30) begin
      musica_dez_val = 4'd3;
      musica_uni_val = diff30[3:0];
    end else if (actual_idx >= 6'd20) begin
      musica_dez_val = 4'd2;
      musica_uni_val = diff20[3:0];
    end else if (actual_idx >= 6'd10) begin
      musica_dez_val = 4'd1;
      musica_uni_val = diff10[3:0];
    end else begin
      musica_dez_val = 4'd0;
      musica_uni_val = actual_idx[3:0];
    end
  end

  // Se modo livre (0) ou dezena zero, apaga dezena (5'h1F e apagado)
  wire [4:0] dez_idx = ((modo_ativo == 2'd0) || (musica_dez_val == 4'd0)) ?
    5'h1F : {1'b0, musica_dez_val};
  wire [6:0] hex3_normal;
  hexa7seg hexa7seg_disp3 (
    .hexa(dez_idx),
    .display(hex3_normal)
  );

  assign hex3_musica_dezena = mostra_vol ?
    ((volume == 2'd0) ? 7'h40 :
      (volume == 2'd1) ? 7'h12 : 7'h40) :
    hex3_normal;

  // HEX2: Unidade da musica ou letra 'P' de percentual
  wire [4:0] uni_idx = (modo_ativo == 2'd0) ? 5'h1F : {1'b0, musica_uni_val};
  wire [6:0] hex2_normal;
  hexa7seg hexa7seg_disp2 (
    .hexa(uni_idx),
    .display(hex2_normal)
  );

  assign hex2_musica_unidade = mostra_vol ? 7'h0C : hex2_normal;

  // HEX1: Nota do fluxo de dados
  assign hex1_nota = nota_display;

  // HEX0: Sustenido
  display_sustenido display_sustenido_inst (
    .sustenido(sustenido_atual),
    .display(hex0_sustenido)
  );

  // Mapeamento de LEDs fisicos
  assign led_sustenido = (modo_ativo == 2'd1) ? sustenido_atual : 1'b0;

  wire nota_led_valida = ((modo_ativo == 2'd1) || (modo_ativo == 2'd3)) &&
    (id_nota != 3'd0);
  wire [6:0] raw_led = nota_led_valida ?
    (7'b0000001 << (id_nota - 3'd1)) :
    7'b0000000;

  assign led_vermelho = raw_led & {7{pwm_out}};

endmodule

`default_nettype wire
