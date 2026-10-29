`timescale 1ns / 1ps
`default_nettype none

// Descricao: Caminho de dados unificado para modos.
module fluxo_dados #(
    parameter DEBOUNCE_TECLA    = 100_000, // Medimos quase 1ms, usaremos 2ms.
    parameter DEBOUNCE_CONTROLE = 400_000, // Medimos 4ms de debounce, usaremos 8ms por seguranca
    parameter CLOCK_DIV_UART    = 434,
    parameter CICLOS_TICK_8MS   = 400_000
) (
    input  wire        clock,
    input  wire        reset,

    // Entradas
    input  wire [6:0]  botoes,
    input  wire        btn_modo,
    input  wire        btn_musica,
    input  wire        btn_intensidade,
    input  wire        btn_oitava_up,
    input  wire        btn_oitava_down,
    input  wire        btn_sustenido,

    // Entradas da unidade de controle
    input  wire [1:0]  modo_ativo,
    input  wire        escreve_ram,
    input  wire        conta_endereco,
    input  wire        zera_endereco,

    // Saidas Fisicas
    output wire        saida_serial,
    output wire [6:0]  leds,

    // Status
    output wire        mudou_modo,
    output wire        mudou_musica,
    output wire        tem_nota_ativa,
    output wire        acerto_nota,
    output wire        fim_musica,
    output wire        pulso_bpm,
    output wire [9:0]  s_endereco_ram,
    output wire [2:0]  s_id_para_led,
    output wire [5:0]  out_sel_musica,
    output wire [6:0]  db_botoes,
    output wire        pwm_out,
    output wire [2:0]  oitava_atual,
    output wire        sustenido_atual,
    output wire        led_oitava_up,
    output wire        led_oitava_down,
    output wire [1:0]  out_volume,
    output wire        mostra_vol,
    output wire [31:0] t_passo_metronomo
);

    wire [6:0] s_botoes_db;
    wire s_btn_modo_db, s_btn_musica_db, s_btn_intensidade_db;
    wire s_btn_oitava_up_db, s_btn_oitava_down_db, s_btn_sustenido_db;

    // Debouncers (TECLA)
    debounce #(.WIDTH(7), .TEMPO_FILTRO(DEBOUNCE_TECLA)) u_db_notas (
        .clock(clock), .reset(reset), .in(botoes), .out(s_botoes_db)
    );
    debounce #(.WIDTH(1), .TEMPO_FILTRO(DEBOUNCE_TECLA)) u_db_sustenido (
        .clock(clock), .reset(reset), .in(btn_sustenido), .out(s_btn_sustenido_db)
    );

    // Debouncers (CONTROLE)
    debounce #(.WIDTH(1), .TEMPO_FILTRO(DEBOUNCE_CONTROLE)) u_db_modo (
        .clock(clock), .reset(reset), .in(btn_modo), .out(s_btn_modo_db)
    );
    debounce #(.WIDTH(1), .TEMPO_FILTRO(DEBOUNCE_CONTROLE)) u_db_musica (
        .clock(clock), .reset(reset), .in(btn_musica), .out(s_btn_musica_db)
    );
    debounce #(.WIDTH(1), .TEMPO_FILTRO(DEBOUNCE_CONTROLE)) u_db_intensidade (
        .clock(clock), .reset(reset), .in(btn_intensidade), .out(s_btn_intensidade_db)
    );
    debounce #(.WIDTH(1), .TEMPO_FILTRO(DEBOUNCE_CONTROLE)) u_db_oitava_up (
        .clock(clock), .reset(reset), .in(btn_oitava_up), .out(s_btn_oitava_up_db)
    );
    debounce #(.WIDTH(1), .TEMPO_FILTRO(DEBOUNCE_CONTROLE)) u_db_oitava_down (
        .clock(clock), .reset(reset), .in(btn_oitava_down), .out(s_btn_oitava_down_db)
    );

    wire s_btn_musica_pulse;
    edge_detector u_ed_musica (
        .clock(clock), .reset(reset), .sinal(s_btn_musica_db), .pulso(s_btn_musica_pulse)
    );
    assign mudou_musica = s_btn_musica_pulse;

    wire s_btn_intensidade_pulse;
    edge_detector u_ed_intensidade (
        .clock(clock), .reset(reset), .sinal(s_btn_intensidade_db), .pulso(s_btn_intensidade_pulse)
    );

    wire s_btn_oitava_up_pulse;
    edge_detector u_ed_oit_up (
        .clock(clock), .reset(reset), .sinal(s_btn_oitava_up_db), .pulso(s_btn_oitava_up_pulse)
    );

    wire s_btn_oitava_down_pulse;
    edge_detector u_ed_oit_down (
        .clock(clock), .reset(reset), .sinal(s_btn_oitava_down_db), .pulso(s_btn_oitava_down_pulse)
    );

    // Logica de Combinacao (Modo + Intensidade)
    wire s_modo_pressed = s_btn_modo_db;
    reg r_modo_prev_reg;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            r_modo_prev_reg <= 1'b0;
        end else begin
            r_modo_prev_reg <= s_modo_pressed;
        end
    end
    wire s_modo_released = (~s_modo_pressed && r_modo_prev_reg);

    reg combo_ativo_reg;
    // 0 = 100%, 1 = 75%, 2 = 50%
    reg [1:0]  estado_vol_reg;
    reg [25:0] timer_display_vol_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            combo_ativo_reg       <= 1'b0;
            estado_vol_reg        <= 2'd0;
            timer_display_vol_reg <= 26'd0;
        end else begin
            // Se segurar o modo e clicar na INTENSIDADE
            if (s_modo_pressed && s_btn_intensidade_pulse) begin
                combo_ativo_reg       <= 1'b1; // Regista que o combo foi usado
                timer_display_vol_reg <= 26'd50_000_000; // Display ativo por 1s

                // Cicla o volume entre 0, 1, 2
                if (estado_vol_reg == 2'd2) begin
                    estado_vol_reg <= 2'd0;
                end else begin
                    estado_vol_reg <= estado_vol_reg + 2'd1;
                end
            end else if (~s_modo_pressed) begin
                // Quando solta o botao modo, limpa a flag do combo
                combo_ativo_reg <= 1'b0;
            end

            if (timer_display_vol_reg > 26'd0) begin
                timer_display_vol_reg <= timer_display_vol_reg - 26'd1;
            end
        end
    end

    // O modo so muda quando o botao e solto e nao tiver no modo combo
    assign mudou_modo = s_modo_released && !combo_ativo_reg;
    assign out_volume = estado_vol_reg;
    assign mostra_vol = (timer_display_vol_reg > 26'd0);

    // Seletor de musica
    wire [5:0] s_sel_musica;
    contador_m #(.M(40), .N(6)) u_contador_musica (
        .clock(clock),
        .reset(reset),
        .sclr(1'b0),
        .conta(s_btn_musica_pulse),
        .q(s_sel_musica),
        .fim(),
        .meio()
    );

    wire [5:0] mux_sel = (modo_ativo == 2'd2) ? 6'd39 : s_sel_musica;
    assign out_sel_musica = mux_sel;
    assign db_botoes = s_botoes_db;

    // Gerenciador de oitava livre
    wire [2:0] s_oitava_livre;
    guarda_oitava u_oitava_inst (
        .clock(clock),
        .reset(reset),
        .btn_up_pulse(s_btn_oitava_up_pulse),
        .btn_down_pulse(s_btn_oitava_down_pulse),
        .oitava_atual(s_oitava_livre)
    );

    // 1. Logica de Prioridade de Teclas
    wire [2:0] s_nota_tocada;
    wire       s_tem_nota;
    logica_notas_prioridade u_logic_inst (
        .clock(clock),
        .reset(reset),
        .botoes(s_botoes_db),
        .nota_id(s_nota_tocada),
        .tem_nota(s_tem_nota)
    );

    // 2. Logica de Memoria e Enderecamento
    wire cont_fim;
    contador_m #(.M(1024), .N(10)) u_contador_addr (
        .clock(clock),
        .reset(1'b0),
        .sclr(zera_endereco),
        .conta(conta_endereco),
        .q(s_endereco_ram),
        .fim(cont_fim),
        .meio()
    );

    wire [29:0] d_ram0, d_ram1, d_ram2, d_ram3, d_ram4, d_ram5, d_ram6, d_ram7;
    wire [29:0] d_ram8, d_ram9, d_ram10, d_ram11, d_ram12, d_ram13, d_ram14;
    wire [29:0] d_ram15, d_ram16, d_ram17, d_ram18, d_ram19, d_ram20, d_ram21;
    wire [29:0] d_ram22, d_ram23, d_ram24, d_ram25, d_ram26, d_ram27, d_ram28;
    wire [29:0] d_ram29, d_ram30, d_ram31, d_ram32, d_ram33, d_ram34, d_ram35;
    wire [29:0] d_ram36, d_ram37, d_ram38;

    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Axel_F.txt"))
        u_mem0 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram0));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Bad_Romance.txt"))
        u_mem1 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram1));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Beat_It.txt"))
        u_mem2 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram2));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Careless_Whisper.txt"))
        u_mem3 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram3));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Clair_de_Lune.txt"))
        u_mem4 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram4));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Clocks.txt"))
        u_mem5 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram5));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Do_Re_Mi_Fa.txt"))
        u_mem6 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram6));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Epitafio.txt"))
        u_mem7 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram7));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Fukashigi_No_Carte.txt"))
        u_mem8 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram8));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Fur_Elise.txt"))
        u_mem9 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram9));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Golden.txt"))
        u_mem10 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram10));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Golden_Wind.txt"))
        u_mem11 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram11));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Harry_Potter.txt"))
        u_mem12 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram12));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Head_Over_Heels.txt"))
        u_mem13 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram13));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Hey_Jude.txt"))
        u_mem14 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram14));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Homem_Aranha_1900.txt"))
        u_mem15 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram15));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Imperial_March.txt"))
        u_mem16 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram16));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Interestelar.txt"))
        u_mem17 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram17));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Korobeiniki.txt"))
        u_mem18 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram18));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Lugar_Ao_Sol.txt"))
        u_mem19 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram19));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Magnetic.txt"))
        u_mem20 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram20));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Mario.txt"))
        u_mem21 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram21));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Minecraft_Sweden.txt"))
        u_mem22 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram22));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Moonlight_Sonata_3mvt.txt"))
        u_mem23 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram23));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Morning_Flower.txt"))
        u_mem24 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram24));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Never_Gonna_Give_You_Up.txt"))
        u_mem25 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram25));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Numb.txt"))
        u_mem26 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram26));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Pink_Panther.txt"))
        u_mem27 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram27));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Radio_Ga_Ga.txt"))
        u_mem28 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram28));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Sadness_And_Sorrow.txt"))
        u_mem29 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram29));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Someone_Like_You.txt"))
        u_mem30 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram30));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Star_Wars_Main_Theme.txt"))
        u_mem31 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram31));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Sweet_Child_O_Mine.txt"))
        u_mem32 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram32));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Take_On_Me.txt"))
        u_mem33 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram33));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Trem_Das_Onze.txt"))
        u_mem34 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram34));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Undertale_Megalovania.txt"))
        u_mem35 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram35));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/We_Are_Number_One.txt"))
        u_mem36 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram36));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/When_Love_Takes_Over.txt"))
        u_mem37 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram37));
    sync_rom #(.DATA_WIDTH(30), .ADDR_WIDTH(10), .INIT_FILE("music/Zelda_Lost_Woods.txt"))
        u_mem38 (.clock(clock), .address(s_endereco_ram), .data_out(d_ram38));

    // Temporizador de Gravacao (Modo 2)
    wire [6:0] s_nota_midi_usuario;
    reg  [6:0] s_velocity_final;

    reg [31:0] cont_grav_ciclos_reg;
    reg        r_tem_nota_grav_prev_reg;
    reg [6:0]  nota_grav_reg;
    reg [6:0]  vel_grav_reg;
    reg [7:0]  duracao_grav_reg;
    reg [7:0]  pausa_grav_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            cont_grav_ciclos_reg     <= 32'd0;
            r_tem_nota_grav_prev_reg <= 1'b0;
            nota_grav_reg            <= 7'd0;
            vel_grav_reg             <= 7'd0;
            duracao_grav_reg         <= 8'd1;
            pausa_grav_reg           <= 8'd0;
        end else if (modo_ativo == 2'd2) begin
            r_tem_nota_grav_prev_reg <= s_tem_nota;
            if (zera_endereco || conta_endereco) begin
                cont_grav_ciclos_reg <= 32'd0;
                duracao_grav_reg     <= 8'd1;
                pausa_grav_reg       <= 8'd0;
            end else if (s_tem_nota) begin
                nota_grav_reg <= s_nota_midi_usuario;
                vel_grav_reg  <= s_velocity_final;
                if (!r_tem_nota_grav_prev_reg) begin
                    cont_grav_ciclos_reg <= 32'd0;
                end else if (cont_grav_ciclos_reg >= (CICLOS_TICK_8MS - 1)) begin
                    cont_grav_ciclos_reg <= 32'd0;
                    if (duracao_grav_reg < 8'd255) begin
                        duracao_grav_reg <= duracao_grav_reg + 8'd1;
                    end
                end else begin
                    cont_grav_ciclos_reg <= cont_grav_ciclos_reg + 32'd1;
                end
            end else begin
                if (r_tem_nota_grav_prev_reg) begin
                    cont_grav_ciclos_reg <= 32'd0;
                end else if (!escreve_ram) begin
                    if (cont_grav_ciclos_reg >= (CICLOS_TICK_8MS - 1)) begin
                        cont_grav_ciclos_reg <= 32'd0;
                        if (pausa_grav_reg < 8'd255) begin
                            pausa_grav_reg <= pausa_grav_reg + 8'd1;
                        end
                    end else begin
                        cont_grav_ciclos_reg <= cont_grav_ciclos_reg + 32'd1;
                    end
                end
            end
        end else begin
            cont_grav_ciclos_reg     <= 32'd0;
            r_tem_nota_grav_prev_reg <= 1'b0;
            duracao_grav_reg         <= 8'd1;
            pausa_grav_reg           <= 8'd0;
        end
    end

    wire [29:0] d_ram39;
    wire [29:0] nota_paragravar = {pausa_grav_reg, duracao_grav_reg, vel_grav_reg, nota_grav_reg};

    sync_ram #(.DATA_WIDTH(30), .ADDR_WIDTH(10)) u_mem_gravacao (
        .clock(clock),
        .we(escreve_ram),
        .address(s_endereco_ram),
        .data_in(nota_paragravar),
        .data_out(d_ram39)
    );

    wire [29:0] s_dado_ram;
    mux_musicas u_seletor_musicas_inst (
        .sel(mux_sel),
        .d0(d_ram0), .d1(d_ram1), .d2(d_ram2), .d3(d_ram3),
        .d4(d_ram4), .d5(d_ram5), .d6(d_ram6), .d7(d_ram7),
        .d8(d_ram8), .d9(d_ram9), .d10(d_ram10), .d11(d_ram11),
        .d12(d_ram12), .d13(d_ram13), .d14(d_ram14), .d15(d_ram15),
        .d16(d_ram16), .d17(d_ram17), .d18(d_ram18), .d19(d_ram19),
        .d20(d_ram20), .d21(d_ram21), .d22(d_ram22), .d23(d_ram23),
        .d24(d_ram24), .d25(d_ram25), .d26(d_ram26), .d27(d_ram27),
        .d28(d_ram28), .d29(d_ram29), .d30(d_ram30), .d31(d_ram31),
        .d32(d_ram32), .d33(d_ram33), .d34(d_ram34), .d35(d_ram35),
        .d36(d_ram36), .d37(d_ram37), .d38(d_ram38), .d39(d_ram39),
        .out(s_dado_ram)
    );

    // Controle de fim da gravacao na RAM (mux_sel == 6'd39)
    reg       grav_tem_dados_reg;
    reg [9:0] ultimo_end_gravado_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            grav_tem_dados_reg     <= 1'b0;
            ultimo_end_gravado_reg <= 10'd0;
        end else if ((modo_ativo == 2'd2) && zera_endereco) begin
            grav_tem_dados_reg     <= 1'b0;
            ultimo_end_gravado_reg <= 10'd0;
        end else if (escreve_ram) begin
            grav_tem_dados_reg     <= 1'b1;
            ultimo_end_gravado_reg <= s_endereco_ram;
        end
    end

    wire [29:0] s_dado_ram_final = ((mux_sel == 6'd39) && (!grav_tem_dados_reg || (s_endereco_ram > ultimo_end_gravado_reg))) ? 30'd0 : s_dado_ram;

    wire [6:0] s_nota_midi_rom = s_dado_ram_final[6:0];
    wire [6:0] s_velocity_rom  = s_dado_ram_final[13:7];
    wire [7:0] s_duracao_rom   = s_dado_ram_final[21:14];
    wire [7:0] s_pausa_rom     = s_dado_ram_final[29:22];

    wire [2:0] s_oitava_esperada;
    wire       s_sustenido_esperado;
    wire [2:0] s_nota_esperada;

    decodificador_midi u_dec_midi (
        .nota_midi(s_nota_midi_rom),
        .oitava(s_oitava_esperada),
        .sustenido(s_sustenido_esperado),
        .nota_id(s_nota_esperada)
    );

    wire s_ativo_apre_demo = (modo_ativo == 2'd1 || modo_ativo == 2'd3);
    wire [2:0] s_oitava_atual_uso = (s_ativo_apre_demo && s_nota_esperada != 3'd0) ?
                                    s_oitava_esperada : s_oitava_livre;
    wire s_sustenido_atual_uso = (s_ativo_apre_demo && s_nota_esperada != 3'd0) ?
                                 s_sustenido_esperado : s_btn_sustenido_db;

    wire s_led_up, s_led_down;
    led_oitava u_indicador_erro_oitava (
        .oitava_certa(s_oitava_esperada),
        .oitava_atual(s_oitava_livre),
        .led_up(s_led_up),
        .led_down(s_led_down)
    );

    assign oitava_atual    = s_oitava_atual_uso;
    assign sustenido_atual = s_sustenido_atual_uso;
    assign led_oitava_up   = (s_ativo_apre_demo && s_nota_esperada != 3'd0) ? s_led_up : 1'b0;
    assign led_oitava_down = (s_ativo_apre_demo && s_nota_esperada != 3'd0) ? s_led_down : 1'b0;

    codificador_midi u_cod_midi (
        .oitava(s_oitava_atual_uso),
        .sustenido(s_sustenido_atual_uso),
        .nota_id(s_nota_tocada),
        .nota_midi(s_nota_midi_usuario)
    );

    wire s_is_demo = (modo_ativo == 2'd3);
    reg  r_nota_ativa_bpm_reg;
    wire s_tem_nota_final = s_is_demo ? (s_nota_esperada != 3'd0 && r_nota_ativa_bpm_reg) : s_tem_nota;

    wire [6:0] s_vel_base = s_is_demo ? ((s_velocity_rom == 7'd0) ? 7'd100 : s_velocity_rom) : 7'd127;
    always @(*) begin
        case (estado_vol_reg)
            2'd0:    s_velocity_final = s_vel_base;
            2'd1:    s_velocity_final = (s_vel_base >> 1'b1) + (s_vel_base >> 2'd2);
            2'd2:    s_velocity_final = (s_vel_base >> 1'b1);
            default: s_velocity_final = s_vel_base;
        endcase
    end

    wire [6:0] s_nota_midi_desejada = s_is_demo ? (r_nota_ativa_bpm_reg ? s_nota_midi_rom : 7'd0) : (s_tem_nota ? s_nota_midi_usuario : 7'd0);

    gerenciador_midi_tx #(
        .CLOCK_DIV(CLOCK_DIV_UART)
    ) u_midi_tx (
        .clock(clock),
        .reset(reset),
        .nota_desejada(s_nota_midi_desejada),
        .velocity_desejado(s_velocity_final),
        .saida_serial(saida_serial),
        .ocupado()
    );

    assign s_id_para_led = (modo_ativo == 2'd1 || modo_ativo == 2'd3) ? s_nota_esperada : s_nota_tocada;

    // 3. Logica Visual e Comparacao
    decodificador_cifra u_decoder_cifra_inst (
        .nota_id(s_id_para_led),
        .display(leds)
    );

    wire s_match_cru = (s_nota_tocada == s_nota_esperada) && s_tem_nota && (modo_ativo == 2'd1);

    assign tem_nota_ativa = s_tem_nota_final;
    assign acerto_nota    = s_match_cru;
    assign fim_musica     = (modo_ativo == 2'd2) ? cont_fim : (s_nota_esperada == 3'd0);

    // 4. Modulacao de LED (PWM)
    reg [2:0] estado_intensidade_reg;
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            estado_intensidade_reg <= 3'd0;
        // O LED so muda se o botao Modo nao estiver pressionado
        end else if (s_btn_intensidade_pulse && !s_modo_pressed) begin
            if (estado_intensidade_reg == 3'd4) begin
                estado_intensidade_reg <= 3'd0;
            end else begin
                estado_intensidade_reg <= estado_intensidade_reg + 3'd1;
            end
        end
    end

    reg [3:0] s_duty_cycle;
    always @(*) begin
        case (estado_intensidade_reg)
            3'd0:    s_duty_cycle = 4'hF;
            3'd1:    s_duty_cycle = 4'hC;
            3'd2:    s_duty_cycle = 4'h8;
            3'd3:    s_duty_cycle = 4'h4;
            3'd4:    s_duty_cycle = 4'h0;
            default: s_duty_cycle = 4'hF;
        endcase
    end

    gerador_pwm u_pwm_inst (
        .clock(clock), .reset(reset), .duty_cycle(s_duty_cycle), .pwm_out(pwm_out)
    );

    // Metronomo (BPM por musica)
    reg [31:0] ciclos_por_beat;
    always @(*) begin
        ciclos_por_beat = 32'd30_000_000;
        case (s_sel_musica)
            6'd0:    ciclos_por_beat = 32'd21739130; // 138 bpm (Axel_F.txt)
            6'd1:    ciclos_por_beat = 32'd25210084; // 119 bpm (Bad_Romance.txt)
            6'd2:    ciclos_por_beat = 32'd25641026; // 117 bpm (Beat_It.txt)
            6'd3:    ciclos_por_beat = 32'd19607843; // 153 bpm (Careless_Whisper.txt)
            6'd4:    ciclos_por_beat = 32'd39473684; // 76 bpm  (Clair_de_Lune.txt)
            6'd5:    ciclos_por_beat = 32'd17341040; // 173 bpm (Clocks.txt)
            6'd6:    ciclos_por_beat = 32'd30000000; // 100 bpm (Do_Re_Mi_Fa.txt)
            6'd7:    ciclos_por_beat = 32'd26785714; // 112 bpm (Epitafio.txt)
            6'd8:    ciclos_por_beat = 32'd31250000; // 96 bpm  (Fukashigi_No_Carte.txt)
            6'd9:    ciclos_por_beat = 32'd20833333; // 144 bpm (Fur_Elise.txt)
            6'd10:   ciclos_por_beat = 32'd24390243; // 123 bpm (Golden.txt)
            6'd11:   ciclos_por_beat = 32'd22222222; // 135 bpm (Golden_Wind.txt)
            6'd12:   ciclos_por_beat = 32'd41095890; // 73 bpm  (Harry_Potter.txt)
            6'd13:   ciclos_por_beat = 32'd31578947; // 95 bpm  (Head_Over_Heels.txt)
            6'd14:   ciclos_por_beat = 32'd40540540; // 74 bpm  (Hey_Jude.txt)
            6'd15:   ciclos_por_beat = 32'd25423728; // 118 bpm (Homem_Aranha_1900.txt)
            6'd16:   ciclos_por_beat = 32'd29126214; // 103 bpm (Imperial_March.txt)
            6'd17:   ciclos_por_beat = 32'd30000000; // 100 bpm (Interestelar.txt)
            6'd18:   ciclos_por_beat = 32'd30612245; // 98 bpm  (Korobeiniki.txt)
            6'd19:   ciclos_por_beat = 32'd21276596; // 141 bpm (Lugar_Ao_Sol.txt)
            6'd20:   ciclos_por_beat = 32'd11450380; // 524 bpm (Magnetic.txt)
            6'd21:   ciclos_por_beat = 32'd30000000; // 100 bpm (Mario.txt)
            6'd22:   ciclos_por_beat = 32'd40540540; // 74 bpm  (Minecraft_Sweden.txt)
            6'd23:   ciclos_por_beat = 32'd13636363; // 220 bpm (Moonlight_Sonata_3mvt.txt)
            6'd24:   ciclos_por_beat = 32'd21428571; // 140 bpm (Morning_Flower.txt)
            6'd25:   ciclos_por_beat = 32'd26548673; // 113 bpm (Never_Gonna_Give_You_Up.txt)
            6'd26:   ciclos_por_beat = 32'd27272727; // 110 bpm (Numb.txt)
            6'd27:   ciclos_por_beat = 32'd25862069; // 116 bpm (Pink_Panther.txt)
            6'd28:   ciclos_por_beat = 32'd26086956; // 115 bpm (Radio_Ga_Ga.txt)
            6'd29:   ciclos_por_beat = 32'd21428571; // 140 bpm (Sadness_And_Sorrow.txt)
            6'd30:   ciclos_por_beat = 32'd22222222; // 135 bpm (Someone_Like_You.txt)
            6'd31:   ciclos_por_beat = 32'd36144578; // 83 bpm  (Star_Wars_Main_Theme.txt)
            6'd32:   ciclos_por_beat = 32'd24000000; // 125 bpm (Sweet_Child_O_Mine.txt)
            6'd33:   ciclos_por_beat = 32'd35714285; // 84 bpm  (Take_On_Me.txt)
            6'd34:   ciclos_por_beat = 32'd32608695; // 92 bpm  (Trem_Das_Onze.txt)
            6'd35:   ciclos_por_beat = 32'd25000000; // 120 bpm (Undertale_Megalovania.txt)
            6'd36:   ciclos_por_beat = 32'd18518519; // 162 bpm (We_Are_Number_One.txt)
            6'd37:   ciclos_por_beat = 32'd23076923; // 130 bpm (When_Love_Takes_Over.txt)
            6'd38:   ciclos_por_beat = 32'd21428571; // 140 bpm (Zelda_Lost_Woods.txt)
            default: ciclos_por_beat = 32'd30_000_000; // 100 bpm default
        endcase
    end

    assign t_passo_metronomo = ciclos_por_beat / 32'd7;

    // Temporizador do Modo Demonstracao (Modo 3)
    wire [7:0] s_dur_efetiva      = (s_duracao_rom == 8'd0) ? 8'd1 : s_duracao_rom;
    wire [7:0] s_pausa_efetiva    = (s_pausa_rom == 8'd0) ? 8'd1 : s_pausa_rom;
    wire [8:0] s_total_ticks_demo = {1'b0, s_dur_efetiva} + {1'b0, s_pausa_efetiva};

    reg [31:0] cont_demo_ciclos_reg;
    reg [8:0]  tick_demo_reg;
    reg        r_pulso_bpm_reg;
    reg        r_aguarda_rom_demo_reg;
    assign pulso_bpm = r_pulso_bpm_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            cont_demo_ciclos_reg   <= 32'd0;
            tick_demo_reg          <= 9'd0;
            r_pulso_bpm_reg        <= 1'b0;
            r_nota_ativa_bpm_reg   <= 1'b0;
            r_aguarda_rom_demo_reg <= 1'b0;
        end else if (modo_ativo == 2'd3) begin
            r_aguarda_rom_demo_reg <= (zera_endereco || conta_endereco);
            if (zera_endereco || conta_endereco || r_aguarda_rom_demo_reg || r_pulso_bpm_reg) begin
                cont_demo_ciclos_reg <= 32'd0;
                tick_demo_reg        <= 9'd0;
                r_pulso_bpm_reg      <= 1'b0;
                r_nota_ativa_bpm_reg <= 1'b0;
            end else if (s_nota_midi_rom == 7'd0) begin
                cont_demo_ciclos_reg <= 32'd0;
                tick_demo_reg        <= 9'd0;
                r_pulso_bpm_reg      <= 1'b1;
                r_nota_ativa_bpm_reg <= 1'b0;
            end else begin
                if (cont_demo_ciclos_reg >= (CICLOS_TICK_8MS - 1)) begin
                    cont_demo_ciclos_reg <= 32'd0;
                    if (tick_demo_reg >= (s_total_ticks_demo - 9'd1)) begin
                        tick_demo_reg        <= 9'd0;
                        r_pulso_bpm_reg      <= 1'b1;
                        r_nota_ativa_bpm_reg <= 1'b0;
                    end else begin
                        tick_demo_reg        <= tick_demo_reg + 9'd1;
                        r_pulso_bpm_reg      <= 1'b0;
                        r_nota_ativa_bpm_reg <= ((tick_demo_reg + 9'd1) < {1'b0, s_dur_efetiva});
                    end
                end else begin
                    cont_demo_ciclos_reg <= cont_demo_ciclos_reg + 32'd1;
                    r_pulso_bpm_reg      <= 1'b0;
                    r_nota_ativa_bpm_reg <= (tick_demo_reg < {1'b0, s_dur_efetiva});
                end
            end
        end else begin
            cont_demo_ciclos_reg   <= 32'd0;
            tick_demo_reg          <= 9'd0;
            r_pulso_bpm_reg        <= 1'b0;
            r_nota_ativa_bpm_reg   <= 1'b0;
            r_aguarda_rom_demo_reg <= 1'b0;
        end
    end

endmodule

`default_nettype wire
