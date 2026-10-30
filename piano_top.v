// Descricao: Top-level puramente estrutural do piano digital para FPGA Cyclone V.
// Funcionamento: Interliga sincronizador de reset, detectores de borda, FSM de controle,
// fluxo de dados, metronomo e o painel decodificador de displays/LEDs sem logica interna.

`timescale 1ns / 1ps
`default_nettype none

module piano_top #(
  parameter DebounceTecla    = 100_000,
  parameter DebounceControle = 200_000,
  parameter ClockDivUart     = 434,
  parameter CiclosTick8ms    = 400_000
)(
  input  wire       clk,
  input  wire       reset_n,
  input  wire [6:0] gpio_keys,
  input  wire       btn_modo_n,
  input  wire       btn_musica_n,
  input  wire       btn_intensidade_n,
  input  wire       btn_oitava_up_n,
  input  wire       btn_oitava_down_n,
  input  wire       btn_sustenido,
  output wire       saida_serial,
  output wire       servo_controle,
  output wire [6:0] led_vermelho,
  output wire       led_sustenido,
  output wire       led_oitava_up,
  output wire       led_oitava_down,
  output wire [6:0] hex5_modo,
  output wire [6:0] hex4_oitava,
  output wire [6:0] hex3_musica_dezena,
  output wire [6:0] hex2_musica_unidade,
  output wire [6:0] hex1_nota,
  output wire [6:0] hex0_sustenido
);

  // Sincronizador de reset com 2 flip-flops
  wire arst;
  sincronizador #(
    .Width    (1),
    .InitValue(1'b1)
  ) sincronizador_reset (
    .clk     (clk),
    .arst    (!reset_n),
    .async_in(1'b0),
    .sync_out(arst)
  );

  // Inversao de botoes fisicos ativos em nivel baixo
  wire btn_modo        = ~btn_modo_n;
  wire btn_musica      = ~btn_musica_n;
  wire btn_intensidade = ~btn_intensidade_n;
  wire btn_oitava_up   = ~btn_oitava_up_n;
  wire btn_oitava_down = ~btn_oitava_down_n;

  // Interconexao UC <-> Fluxo de Dados
  wire [1:0]  fsm_modo_ativo;
  wire        fsm_zera_end;
  wire        fsm_conta_end;
  wire        fsm_escreve_ram;
  wire        fd_tem_nota_ativa;
  wire        fd_acerto_nota;
  wire        fd_fim_musica;
  wire [2:0]  fd_id_nota;
  wire [5:0]  s_sel_musica;
  wire [6:0]  s_db_botoes;
  wire        fd_mudou_modo;
  wire        fd_mudou_musica;
  wire        s_pwm_out;
  wire        fd_pulso_bpm;
  wire [1:0]  fd_volume;
  wire        fd_mostra_vol;
  wire [31:0] fd_t_passo_metronomo;
  wire [6:0]  fd_leds_cifra;

  wire fsm_tecla_pressionada_nivel = (|s_db_botoes);
  wire fsm_tecla_pressionada;
  edge_detector edge_detector_tecla_demo (
    .clk  (clk),
    .arst (arst),
    .sinal(fsm_tecla_pressionada_nivel),
    .pulso(fsm_tecla_pressionada)
  );

  // Unidade de Controle Principal (FSM)
  unidade_controle unidade_controle_inst (
    .clk              (clk),
    .arst             (arst),
    .mudou_modo       (fd_mudou_modo),
    .mudou_musica     (fd_mudou_musica),
    .tem_nota_ativa   (fd_tem_nota_ativa),
    .tecla_pressionada(fsm_tecla_pressionada),
    .acerto_nota      (fd_acerto_nota),
    .fim_musica       (fd_fim_musica),
    .pulso_bpm        (fd_pulso_bpm),
    .modo_ativo       (fsm_modo_ativo),
    .escreve_ram      (fsm_escreve_ram),
    .zera_endereco    (fsm_zera_end),
    .conta_endereco   (fsm_conta_end),
    .estado_hex       ()
  );

  wire [2:0] s_oitava_atual;
  wire       s_sustenido_atual;

  // Fluxo de Dados
  fluxo_dados #(
    .DebounceTecla   (DebounceTecla),
    .DebounceControle(DebounceControle),
    .ClockDivUart    (ClockDivUart),
    .CiclosTick8ms   (CiclosTick8ms)
  ) fluxo_dados_inst (
    .clk              (clk),
    .arst             (arst),
    .botoes           (gpio_keys),
    .btn_modo         (btn_modo),
    .btn_musica       (btn_musica),
    .btn_intensidade  (btn_intensidade),
    .btn_oitava_up    (btn_oitava_up),
    .btn_oitava_down  (btn_oitava_down),
    .btn_sustenido    (btn_sustenido),
    .modo_ativo       (fsm_modo_ativo),
    .escreve_ram      (fsm_escreve_ram),
    .conta_endereco   (fsm_conta_end),
    .zera_endereco    (fsm_zera_end),
    .saida_serial     (saida_serial),
    .leds             (fd_leds_cifra),
    .mudou_modo       (fd_mudou_modo),
    .mudou_musica     (fd_mudou_musica),
    .tem_nota_ativa   (fd_tem_nota_ativa),
    .acerto_nota      (fd_acerto_nota),
    .fim_musica       (fd_fim_musica),
    .pulso_bpm        (fd_pulso_bpm),
    .s_endereco_ram   (),
    .s_id_para_led    (fd_id_nota),
    .out_sel_musica   (s_sel_musica),
    .db_botoes        (s_db_botoes),
    .pwm_out          (s_pwm_out),
    .oitava_atual     (s_oitava_atual),
    .sustenido_atual  (s_sustenido_atual),
    .led_oitava_up    (led_oitava_up),
    .led_oitava_down  (led_oitava_down),
    .out_volume       (fd_volume),
    .mostra_vol       (fd_mostra_vol),
    .t_passo_metronomo(fd_t_passo_metronomo)
  );

  // Metronomo Mecanico com Servomotor SG90
  metronomo #(
    .ClockFreq(50_000_000)
  ) metronomo_inst (
    .clk           (clk),
    .arst          (arst),
    .habilita      (fsm_modo_ativo == 2'd1),
    .t_passo       (fd_t_passo_metronomo),
    .servo_controle(servo_controle),
    .pulso_beat    (),
    .posicao_servo ()
  );

  // Painel Decodificador de Displays e LEDs
  painel_display_leds painel_display_leds_inst (
    .modo_ativo        (fsm_modo_ativo),
    .oitava_atual      (s_oitava_atual),
    .sustenido_atual   (s_sustenido_atual),
    .sel_musica        (s_sel_musica),
    .id_nota           (fd_id_nota),
    .pwm_out           (s_pwm_out),
    .volume            (fd_volume),
    .mostra_vol        (fd_mostra_vol),
    .nota_display      (fd_leds_cifra),
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
