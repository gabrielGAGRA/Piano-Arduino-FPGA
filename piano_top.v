`timescale 1ns / 1ps
`default_nettype none

// Descricao: Top-Level do Piano. Interliga Fluxo de Dados e Controle.
module piano_top #(
    parameter DEBOUNCE_TECLA    = 100_000, // 2ms 
    parameter DEBOUNCE_CONTROLE = 200_000, // 4ms
    parameter CLOCK_DIV_UART    = 434,
    parameter CICLOS_TICK_8MS   = 400_000
) (
    input  wire       CLOCK_50,
    input  wire       reset_n,            // Ativo em baixo
    input  wire [6:0] gpio_keys,     
    input  wire       btn_modo_n,         // Ativo em baixo
    input  wire       btn_musica_n,       // Ativo em baixo
    input  wire       btn_intensidade_n,  // Ativo em baixo
    input  wire       btn_oitava_up_n,    // Ativo em baixo
    input  wire       btn_oitava_down_n,  // Ativo em baixo
    input  wire       btn_sustenido,
    
    // Saídas Físicas
    output wire       saida_serial,
    output wire       servo_controle,
    output wire [6:0] led_vermelho,
    output wire       led_sustenido,
    output wire       led_oitava_up,
    output wire       led_oitava_down,
    
    // RF_STATUS_HEX
    output wire [6:0] hex5_modo,
    output wire [6:0] hex4_oitava,
    output wire [6:0] hex3_musica_dezena,
    output wire [6:0] hex2_musica_unidade,
    output wire [6:0] hex1_nota,
    output wire [6:0] hex0_sustenido
);

    // Sincronizador de Reset Assíncrono com 2 Flip-Flops via módulo sincronizador
    wire reset;
    sincronizador #(
        .WIDTH(1),
        .INIT_VALUE(1'b1)
    ) u_sync_reset (
        .clock   (CLOCK_50),
        .reset   (!reset_n),
        .async_in(1'b0),
        .sync_out(reset)
    );

    // Inversão de botões físicos da placa (ativos em nível baixo)
    wire btn_modo        = ~btn_modo_n;
    wire btn_musica      = ~btn_musica_n;
    wire btn_intensidade = ~btn_intensidade_n;
    wire btn_oitava_up   = ~btn_oitava_up_n;
    wire btn_oitava_down = ~btn_oitava_down_n;

    // Sinais UC <-> Fluxo de Dados
    wire [1:0] fsm_modo_ativo;
    wire fsm_zera_end, fsm_conta_end, fsm_escreve_ram;
    wire fd_tem_nota_ativa, fd_acerto_nota, fd_fim_musica;
    wire [2:0] fd_id_nota;
    wire [5:0] s_sel_musica;
    wire [6:0] s_db_botoes;
    wire fd_mudou_modo;
    wire fd_mudou_musica;
    wire s_pwm_out;
    wire fd_pulso_bpm;
    wire [1:0] fd_volume;
    wire fd_mostra_vol;
    wire [31:0] fd_t_passo_metronomo;
    
    wire fsm_tecla_pressionada_nivel = |s_db_botoes;
    wire fsm_tecla_pressionada;
    edge_detector u_ed_tecla_demo (
        .clock(CLOCK_50),
        .reset(reset),
        .sinal(fsm_tecla_pressionada_nivel),
        .pulso(fsm_tecla_pressionada)
    );

    // UC (RF_MODOS)
    unidade_controle u_fsm_inst (
        .clock(CLOCK_50),
        .reset(reset),
        .mudou_modo(fd_mudou_modo),
        .mudou_musica(fd_mudou_musica),
        .tem_nota_ativa(fd_tem_nota_ativa),
        .tecla_pressionada(fsm_tecla_pressionada),
        .acerto_nota(fd_acerto_nota),
        .fim_musica(fd_fim_musica),
        .pulso_bpm(fd_pulso_bpm),
        .modo_ativo(fsm_modo_ativo),
        .escreve_ram(fsm_escreve_ram),
        .zera_endereco(fsm_zera_end),
        .conta_endereco(fsm_conta_end),
        .estado_hex()
    );

    wire [2:0] s_oitava_atual;
    wire       s_sustenido_atual;
    
    fluxo_dados #(
        .DEBOUNCE_TECLA(DEBOUNCE_TECLA),
        .DEBOUNCE_CONTROLE(DEBOUNCE_CONTROLE),
        .CLOCK_DIV_UART(CLOCK_DIV_UART),
        .CICLOS_TICK_8MS(CICLOS_TICK_8MS)
    ) u_fluxo_inst (
        .clock(CLOCK_50),
        .reset(reset),
        .botoes(gpio_keys),
        .btn_modo(btn_modo),
        .btn_musica(btn_musica),
        .btn_intensidade(btn_intensidade),
        .btn_oitava_up(btn_oitava_up),
        .btn_oitava_down(btn_oitava_down),
        .btn_sustenido(btn_sustenido),
        .modo_ativo(fsm_modo_ativo),
        .escreve_ram(fsm_escreve_ram),
        .conta_endereco(fsm_conta_end),
        .zera_endereco(fsm_zera_end),
        .saida_serial(saida_serial),
        .leds(hex1_nota),
        .mudou_modo(fd_mudou_modo),
        .mudou_musica(fd_mudou_musica),
        .tem_nota_ativa(fd_tem_nota_ativa),
        .acerto_nota(fd_acerto_nota),
        .fim_musica(fd_fim_musica),
        .pulso_bpm(fd_pulso_bpm),
        .s_endereco_ram(),
        .s_id_para_led(fd_id_nota),
        .out_sel_musica(s_sel_musica),
        .db_botoes(s_db_botoes),
        .pwm_out(s_pwm_out),
        .oitava_atual(s_oitava_atual),
        .sustenido_atual(s_sustenido_atual),
        .led_oitava_up(led_oitava_up),
        .led_oitava_down(led_oitava_down),
        .out_volume(fd_volume),
        .mostra_vol(fd_mostra_vol),
        .t_passo_metronomo(fd_t_passo_metronomo)
    );

    // Subsistema de Metrônomo Mecânico (Servomotor SG90 com amplitude de 30°)
    metronomo #(
        .CLOCK_FREQ(50_000_000)
    ) u_metronomo (
        .clock         (CLOCK_50),
        .reset         (reset),
        .habilita      (fsm_modo_ativo == 2'd1), // Ativo exclusivamente no Modo Aprendizado
        .t_passo       (fd_t_passo_metronomo),
        .servo_controle(servo_controle),
        .pulso_beat    (),
        .posicao_servo ()
    );

    // Mapeamento extra de LEDs físicos
    assign led_sustenido = (fsm_modo_ativo == 2'd1) ? s_sustenido_atual : 1'b0;

    // DECODIFICADORES PARA DISPLAYS (RF_STATUS_HEX)

    // HEX5: Modo atual ou Centena do Volume
    wire [6:0] hex5_normal;
    hexa7seg u_disp5_inst (.hexa({3'b000, fsm_modo_ativo}), .display(hex5_normal));

    assign hex5_modo = fd_mostra_vol ?
                       ((fd_volume == 2'd0) ? 7'h79 : 7'h7F) : // Mostra '1' ou apaga
                       hex5_normal;

    // HEX4: Oitava atual ou Dezena do Volume (0, 7, 5)
    wire [6:0] hex4_normal;
    hexa7seg u_disp4_inst (.hexa({2'b00, s_oitava_atual}), .display(hex4_normal));

    assign hex4_oitava = fd_mostra_vol ?
                         ((fd_volume == 2'd0) ? 7'h40 :  // '0'
                          (fd_volume == 2'd1) ? 7'h78 :  // '7'
                                                7'h12) : // '5'
                         hex4_normal;

    // HEX3 & HEX2: Decodificação BCD de Música (00 a 39) sem uso de LPM_DIVIDE
    wire [5:0] actual_idx = s_sel_musica;
    wire [5:0] diff30 = actual_idx - 6'd30;
    wire [5:0] diff20 = actual_idx - 6'd20;
    wire [5:0] diff10 = actual_idx - 6'd10;
    reg [3:0] musica_dez_val;
    reg [3:0] musica_uni_val;

    always @(*) begin
        if (actual_idx >= 6'd30) begin
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

    // Se modo livre (0), apaga display (5'h1F é default apagado). Se dezena for zero, apaga dezena.
    wire [4:0] dez_idx = (fsm_modo_ativo == 2'd0 || musica_dez_val == 4'd0) ? 
                         5'h1F : {1'b0, musica_dez_val};
    wire [6:0] hex3_normal;
    hexa7seg u_disp3_inst (.hexa(dez_idx), .display(hex3_normal));

    assign hex3_musica_dezena = fd_mostra_vol ?
                         ((fd_volume == 2'd0) ? 7'h40 :  // '0'
                          (fd_volume == 2'd1) ? 7'h12 :  // '5'
                                                7'h40) : // '0'
                         hex3_normal;

    // HEX2: Unidade da Música ou Letra 'P' (Percentual)
    wire [4:0] uni_idx = (fsm_modo_ativo == 2'd0) ? 5'h1F : {1'b0, musica_uni_val};
    wire [6:0] hex2_normal;
    hexa7seg u_disp2_inst (.hexa(uni_idx), .display(hex2_normal));

    assign hex2_musica_unidade = fd_mostra_vol ?
                                 7'h0C : // Letra 'P' ativa em baixo
                                 hex2_normal;

    // HEX1: A nota conectada diretamente no 'leds' da instancia do fluxo_dados

    // HEX0: Sustenido
    display_sustenido u_disp0_inst (
        .sustenido(s_sustenido_atual),
        .display(hex0_sustenido)
    );

    // Multiplexador para acender LED vermelho (indicador da base selecionada/nota base do Cifra)
    wire nota_led_valida = ((fsm_modo_ativo == 2'd1 || fsm_modo_ativo == 2'd3) && (fd_id_nota != 3'd0));
    wire [6:0] raw_led = nota_led_valida ? (7'b0000001 << (fd_id_nota - 3'd1)) : 7'b0000000;
    
    // Mascara com PWM para alterar intensidade
    assign led_vermelho = raw_led & {7{s_pwm_out}};

endmodule

`default_nettype wire