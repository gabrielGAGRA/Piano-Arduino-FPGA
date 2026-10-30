// Descricao: Caminho de dados (datapath) unificado do piano digital.
// Funcionamento: Interliga debouncers, registradores de oitava e volume,
// banco de memorias ROM de partituras e RAM de gravacao, decodificador MIDI,
// detector de notas por prioridade e transmissor serial UART.

`timescale 1ns / 1ps
`default_nettype none

module fluxo_dados #(
  parameter DebounceTecla    = 100_000,
  parameter DebounceControle = 400_000,
  parameter ClockDivUart     = 434,
  parameter CiclosTick8ms    = 400_000
)(
  input  wire        clk,
  input  wire        arst,
  input  wire [6:0]  botoes,
  input  wire        btn_modo,
  input  wire        btn_musica,
  input  wire        btn_intensidade,
  input  wire        btn_oitava_up,
  input  wire        btn_oitava_down,
  input  wire        btn_sustenido,
  input  wire [1:0]  modo_ativo,
  input  wire        escreve_ram,
  input  wire        conta_endereco,
  input  wire        zera_endereco,
  output wire        saida_serial,
  output wire [6:0]  leds,
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
  wire s_btn_modo_db;
  wire s_btn_musica_db;
  wire s_btn_intensidade_db;
  wire s_btn_oitava_up_db;
  wire s_btn_oitava_down_db;
  wire s_btn_sustenido_db;

  // Debouncers (TECLA)
  debounce #(
    .Width(7),
    .TempoFiltro(DebounceTecla)
  ) debounce_notas (
    .clk(clk),
    .arst(arst),
    .in (botoes),
    .out(s_botoes_db)
  );

  debounce #(
    .Width(1),
    .TempoFiltro(DebounceTecla)
  ) debounce_sustenido (
    .clk(clk),
    .arst(arst),
    .in (btn_sustenido),
    .out(s_btn_sustenido_db)
  );

  // Debouncers (CONTROLE)
  debounce #(
    .Width(1),
    .TempoFiltro(DebounceControle)
  ) debounce_modo (
    .clk(clk),
    .arst(arst),
    .in (btn_modo),
    .out(s_btn_modo_db)
  );

  debounce #(
    .Width(1),
    .TempoFiltro(DebounceControle)
  ) debounce_musica (
    .clk(clk),
    .arst(arst),
    .in (btn_musica),
    .out(s_btn_musica_db)
  );

  debounce #(
    .Width(1),
    .TempoFiltro(DebounceControle)
  ) debounce_intensidade (
    .clk(clk),
    .arst(arst),
    .in (btn_intensidade),
    .out(s_btn_intensidade_db)
  );

  debounce #(
    .Width(1),
    .TempoFiltro(DebounceControle)
  ) debounce_oitava_up (
    .clk(clk),
    .arst(arst),
    .in (btn_oitava_up),
    .out(s_btn_oitava_up_db)
  );

  debounce #(
    .Width(1),
    .TempoFiltro(DebounceControle)
  ) debounce_oitava_down (
    .clk(clk),
    .arst(arst),
    .in (btn_oitava_down),
    .out(s_btn_oitava_down_db)
  );

  wire s_btn_musica_pulse;
  edge_detector edge_detector_musica (
    .clk  (clk),
    .arst(arst),
    .sinal(s_btn_musica_db),
    .pulso(s_btn_musica_pulse)
  );
  assign mudou_musica = s_btn_musica_pulse;

  wire s_btn_intensidade_pulse;
  edge_detector edge_detector_intensidade (
    .clk  (clk),
    .arst(arst),
    .sinal(s_btn_intensidade_db),
    .pulso(s_btn_intensidade_pulse)
  );

  wire s_btn_oitava_up_pulse;
  edge_detector edge_detector_oit_up (
    .clk  (clk),
    .arst(arst),
    .sinal(s_btn_oitava_up_db),
    .pulso(s_btn_oitava_up_pulse)
  );

  wire s_btn_oitava_down_pulse;
  edge_detector edge_detector_oit_down (
    .clk  (clk),
    .arst(arst),
    .sinal(s_btn_oitava_down_db),
    .pulso(s_btn_oitava_down_pulse)
  );

  // Logica de Combinacao (Modo + Intensidade)
  wire s_modo_pressed = s_btn_modo_db;
  reg  r_modo_prev_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      r_modo_prev_reg <= 1'b0;
    end else begin
      r_modo_prev_reg <= s_modo_pressed;
    end
  end

  wire s_modo_released = (!s_modo_pressed && r_modo_prev_reg);

  reg        combo_ativo_reg;
  reg [1:0]  estado_vol_reg;
  reg [25:0] timer_display_vol_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      combo_ativo_reg       <= 1'b0;
      estado_vol_reg        <= 2'd0;
      timer_display_vol_reg <= 26'd0;
    end else begin
      if (s_modo_pressed && s_btn_intensidade_pulse) begin
        combo_ativo_reg       <= 1'b1;
        timer_display_vol_reg <= 26'd50_000_000;

        if (estado_vol_reg == 2'd2) begin
          estado_vol_reg <= 2'd0;
        end else begin
          estado_vol_reg <= estado_vol_reg + 2'd1;
        end
      end else if (!s_modo_pressed) begin
        combo_ativo_reg <= 1'b0;
      end

      if (timer_display_vol_reg > 26'd0) begin
        timer_display_vol_reg <= timer_display_vol_reg - 26'd1;
      end
    end
  end

  assign mudou_modo = s_modo_released && !combo_ativo_reg;
  assign out_volume = estado_vol_reg;
  assign mostra_vol = (timer_display_vol_reg > 26'd0);

  // Seletor de musica
  wire [5:0] s_sel_musica;
  contador_m #(
    .Modulo(40),
    .Width (6)
  ) contador_m_musica (
    .clk  (clk),
    .arst(arst),
    .sclr (1'b0),
    .conta(s_btn_musica_pulse),
    .fim  (),
    .meio (),
    .q    (s_sel_musica)
  );

  wire [5:0] mux_sel = (modo_ativo == 2'd2) ? 6'd39 : s_sel_musica;
  assign out_sel_musica = mux_sel;
  assign db_botoes      = s_botoes_db;

  // Gerenciador de oitava livre
  wire [2:0] s_oitava_livre;
  guarda_oitava guarda_oitava_inst (
    .clk           (clk),
    .arst(arst),
    .btn_up_pulse  (s_btn_oitava_up_pulse),
    .btn_down_pulse(s_btn_oitava_down_pulse),
    .oitava_atual  (s_oitava_livre)
  );

  // 1. Logica de Prioridade de Teclas
  wire [2:0] s_nota_tocada;
  wire       s_tem_nota;
  logica_notas_prioridade logica_notas_prioridade_inst (
    .clk     (clk),
    .arst(arst),
    .botoes  (s_botoes_db),
    .nota_id (s_nota_tocada),
    .tem_nota(s_tem_nota)
  );

  // 2. Logica de Memoria e Enderecamento
  wire cont_fim;
  contador_m #(
    .Modulo(1024),
    .Width (10)
  ) contador_m_addr (
    .clk  (clk),
    .arst(1'b0),
    .sclr (zera_endereco),
    .conta(conta_endereco),
    .fim  (cont_fim),
    .meio (),
    .q    (s_endereco_ram)
  );

  localparam RomAddrWidth = 14;
  wire [RomAddrWidth-1:0] s_offset_base_rom;
  wire [RomAddrWidth-1:0] s_rom_address = s_offset_base_rom + {4'd0, s_endereco_ram};
  wire [29:0]             d_rom_partituras;

  tabela_offsets_partituras #(
    .AddrWidth(RomAddrWidth)
  ) tabela_offsets_partituras_inst (
    .musica_id(mux_sel),
    .base_addr(s_offset_base_rom)
  );

  sync_rom #(
    .DataWidth(30),
    .AddrWidth(RomAddrWidth),
    .InitFile ("music/partituras.hex"),
    .HexMode  (1)
  ) sync_rom_partituras (
    .clk     (clk),
    .address (s_rom_address),
    .data_out(d_rom_partituras)
  );

  // Temporizador de Gravacao (Modo 2)
  wire [6:0] s_nota_midi_usuario;
  reg  [6:0] s_velocity_final;

  reg [31:0] cont_grav_ciclos_reg;
  reg        r_tem_nota_grav_prev_reg;
  reg [6:0]  nota_grav_reg;
  reg [6:0]  vel_grav_reg;
  reg [7:0]  duracao_grav_reg;
  reg [7:0]  pausa_grav_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
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
        end else if (cont_grav_ciclos_reg >= (CiclosTick8ms - 1)) begin
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
          if (cont_grav_ciclos_reg >= (CiclosTick8ms - 1)) begin
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

  sync_ram #(
    .DataWidth(30),
    .AddrWidth(10)
  ) sync_ram_gravacao (
    .clk     (clk),
    .we      (escreve_ram),
    .address (s_endereco_ram),
    .data_in (nota_paragravar),
    .data_out(d_ram39)
  );

  wire [29:0] s_dado_ram = (mux_sel == 6'd39) ? d_ram39 : d_rom_partituras;

  // Controle de fim da gravacao na RAM
  reg       grav_tem_dados_reg;
  reg [9:0] ultimo_end_gravado_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
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

  wire [29:0] s_dado_ram_final =
    ((mux_sel == 6'd39) && (!grav_tem_dados_reg || (s_endereco_ram > ultimo_end_gravado_reg))) ?
    30'd0 : s_dado_ram;

  wire [6:0] s_nota_midi_rom = s_dado_ram_final[6:0];
  wire [6:0] s_velocity_rom  = s_dado_ram_final[13:7];
  wire [7:0] s_duracao_rom   = s_dado_ram_final[21:14];
  wire [7:0] s_pausa_rom     = s_dado_ram_final[29:22];

  wire [2:0] s_oitava_esperada;
  wire       s_sustenido_esperado;
  wire [2:0] s_nota_esperada;

  decodificador_midi decodificador_midi_inst (
    .nota_midi(s_nota_midi_rom),
    .oitava   (s_oitava_esperada),
    .sustenido(s_sustenido_esperado),
    .nota_id  (s_nota_esperada)
  );

  wire s_ativo_apre_demo = (modo_ativo == 2'd1) || (modo_ativo == 2'd3);
  wire [2:0] s_oitava_atual_uso = (s_ativo_apre_demo && (s_nota_esperada != 3'd0)) ?
    s_oitava_esperada : s_oitava_livre;
  wire s_sustenido_atual_uso = (s_ativo_apre_demo && (s_nota_esperada != 3'd0)) ?
    s_sustenido_esperado : s_btn_sustenido_db;

  wire s_led_up;
  wire s_led_down;
  led_oitava led_oitava_inst (
    .oitava_certa(s_oitava_esperada),
    .oitava_atual(s_oitava_livre),
    .led_up      (s_led_up),
    .led_down    (s_led_down)
  );

  assign oitava_atual    = s_oitava_atual_uso;
  assign sustenido_atual = s_sustenido_atual_uso;
  assign led_oitava_up   = (s_ativo_apre_demo && (s_nota_esperada != 3'd0)) ? s_led_up : 1'b0;
  assign led_oitava_down = (s_ativo_apre_demo && (s_nota_esperada != 3'd0)) ? s_led_down : 1'b0;

  codificador_midi codificador_midi_inst (
    .oitava   (s_oitava_atual_uso),
    .sustenido(s_sustenido_atual_uso),
    .nota_id  (s_nota_tocada),
    .nota_midi(s_nota_midi_usuario)
  );

  wire s_is_demo = (modo_ativo == 2'd3);
  reg  r_nota_ativa_bpm_reg;
  wire s_tem_nota_final = s_is_demo ?
    ((s_nota_esperada != 3'd0) && r_nota_ativa_bpm_reg) : s_tem_nota;

  wire [6:0] s_vel_base = s_is_demo ?
    ((s_velocity_rom == 7'd0) ? 7'd100 : s_velocity_rom) : 7'd127;

  always @* begin
    case (estado_vol_reg)
      2'd0:    s_velocity_final = s_vel_base;
      2'd1:    s_velocity_final = (s_vel_base >> 1'b1) + (s_vel_base >> 2'd2);
      2'd2:    s_velocity_final = (s_vel_base >> 1'b1);
      default: s_velocity_final = s_vel_base;
    endcase
  end

  wire [6:0] s_nota_midi_desejada = s_is_demo ?
    (r_nota_ativa_bpm_reg ? s_nota_midi_rom : 7'd0) :
    (s_tem_nota ? s_nota_midi_usuario : 7'd0);

  gerenciador_midi_tx #(
    .ClockDiv(ClockDivUart)
  ) gerenciador_midi_tx_inst (
    .clk             (clk),
    .arst(arst),
    .nota_desejada   (s_nota_midi_desejada),
    .velocity_desejado(s_velocity_final),
    .saida_serial    (saida_serial),
    .ocupado         ()
  );

  assign s_id_para_led = (modo_ativo == 2'd1 || modo_ativo == 2'd3) ?
    s_nota_esperada : s_nota_tocada;

  // 3. Logica Visual e Comparacao
  decodificador_cifra decodificador_cifra_inst (
    .nota_id(s_id_para_led),
    .display(leds)
  );

  wire s_match_cru = (s_nota_tocada == s_nota_esperada) && s_tem_nota && (modo_ativo == 2'd1);

  assign tem_nota_ativa = s_tem_nota_final;
  assign acerto_nota    = s_match_cru;
  assign fim_musica     = (modo_ativo == 2'd2) ? cont_fim : (s_nota_esperada == 3'd0);

  // 4. Modulacao de LED (PWM)
  reg [2:0] estado_intensidade_reg;
  always @(posedge clk or posedge arst) begin
    if (arst) begin
      estado_intensidade_reg <= 3'd0;
    end else if (s_btn_intensidade_pulse && !s_modo_pressed) begin
      if (estado_intensidade_reg == 3'd4) begin
        estado_intensidade_reg <= 3'd0;
      end else begin
        estado_intensidade_reg <= estado_intensidade_reg + 3'd1;
      end
    end
  end

  reg [3:0] s_duty_cycle;
  always @* begin
    case (estado_intensidade_reg)
      3'd0:    s_duty_cycle = 4'hF;
      3'd1:    s_duty_cycle = 4'hC;
      3'd2:    s_duty_cycle = 4'h8;
      3'd3:    s_duty_cycle = 4'h4;
      3'd4:    s_duty_cycle = 4'h0;
      default: s_duty_cycle = 4'hF;
    endcase
  end

  gerador_pwm gerador_pwm_inst (
    .clk       (clk),
    .arst(arst),
    .duty_cycle(s_duty_cycle),
    .pwm_out   (pwm_out)
  );

  // Metronomo (tempo de passo em ciclos para 1/7 do beat, pre-dividido por 7)
  reg [31:0] t_passo_metronomo_reg;
  always @* begin
    t_passo_metronomo_reg = 32'd4285714;
    case (s_sel_musica)
      6'd0:    t_passo_metronomo_reg = 32'd3105590; // 138 bpm (Axel_F)
      6'd1:    t_passo_metronomo_reg = 32'd3601440; // 119 bpm (Bad_Romance)
      6'd2:    t_passo_metronomo_reg = 32'd3663003; // 117 bpm (Beat_It)
      6'd3:    t_passo_metronomo_reg = 32'd2801120; // 153 bpm (Careless_Whisper)
      6'd4:    t_passo_metronomo_reg = 32'd5639097; // 76 bpm  (Clair_de_Lune)
      6'd5:    t_passo_metronomo_reg = 32'd2477291; // 173 bpm (Clocks)
      6'd6:    t_passo_metronomo_reg = 32'd4285714; // 100 bpm (Do_Re_Mi_Fa)
      6'd7:    t_passo_metronomo_reg = 32'd3826530; // 112 bpm (Epitafio)
      6'd8:    t_passo_metronomo_reg = 32'd4464285; // 96 bpm  (Fukashigi_No_Carte)
      6'd9:    t_passo_metronomo_reg = 32'd2976190; // 144 bpm (Fur_Elise)
      6'd10:   t_passo_metronomo_reg = 32'd3484320; // 123 bpm (Golden)
      6'd11:   t_passo_metronomo_reg = 32'd3174603; // 135 bpm (Golden_Wind)
      6'd12:   t_passo_metronomo_reg = 32'd5870841; // 73 bpm  (Harry_Potter)
      6'd13:   t_passo_metronomo_reg = 32'd4511278; // 95 bpm  (Head_Over_Heels)
      6'd14:   t_passo_metronomo_reg = 32'd5791505; // 74 bpm  (Hey_Jude)
      6'd15:   t_passo_metronomo_reg = 32'd3631961; // 118 bpm (Homem_Aranha_1900)
      6'd16:   t_passo_metronomo_reg = 32'd4160887; // 103 bpm (Imperial_March)
      6'd17:   t_passo_metronomo_reg = 32'd4285714; // 100 bpm (Interestelar)
      6'd18:   t_passo_metronomo_reg = 32'd4373177; // 98 bpm  (Korobeiniki)
      6'd19:   t_passo_metronomo_reg = 32'd3039513; // 141 bpm (Lugar_Ao_Sol)
      6'd20:   t_passo_metronomo_reg = 32'd1635768; // 524 bpm (Magnetic)
      6'd21:   t_passo_metronomo_reg = 32'd4285714; // 100 bpm (Mario)
      6'd22:   t_passo_metronomo_reg = 32'd5791505; // 74 bpm  (Minecraft_Sweden)
      6'd23:   t_passo_metronomo_reg = 32'd1948051; // 220 bpm (Moonlight_Sonata_3mvt)
      6'd24:   t_passo_metronomo_reg = 32'd3061224; // 140 bpm (Morning_Flower)
      6'd25:   t_passo_metronomo_reg = 32'd3792667; // 113 bpm (Never_Gonna_Give_You_Up)
      6'd26:   t_passo_metronomo_reg = 32'd3896103; // 110 bpm (Numb)
      6'd27:   t_passo_metronomo_reg = 32'd3694581; // 116 bpm (Pink_Panther)
      6'd28:   t_passo_metronomo_reg = 32'd3726708; // 115 bpm (Radio_Ga_Ga)
      6'd29:   t_passo_metronomo_reg = 32'd3061224; // 140 bpm (Sadness_And_Sorrow)
      6'd30:   t_passo_metronomo_reg = 32'd3174603; // 135 bpm (Someone_Like_You)
      6'd31:   t_passo_metronomo_reg = 32'd5163511; // 83 bpm  (Star_Wars_Main_Theme)
      6'd32:   t_passo_metronomo_reg = 32'd3428571; // 125 bpm (Sweet_Child_O_Mine)
      6'd33:   t_passo_metronomo_reg = 32'd5102040; // 84 bpm  (Take_On_Me)
      6'd34:   t_passo_metronomo_reg = 32'd4658385; // 92 bpm  (Trem_Das_Onze)
      6'd35:   t_passo_metronomo_reg = 32'd3571428; // 120 bpm (Undertale_Megalovania)
      6'd36:   t_passo_metronomo_reg = 32'd2645502; // 162 bpm (We_Are_Number_One)
      6'd37:   t_passo_metronomo_reg = 32'd3296703; // 130 bpm (When_Love_Takes_Over)
      6'd38:   t_passo_metronomo_reg = 32'd3061224; // 140 bpm (Zelda_Lost_Woods)
      default: t_passo_metronomo_reg = 32'd4285714;
    endcase
  end

  assign t_passo_metronomo = t_passo_metronomo_reg;

  // Temporizador do Modo Demonstracao (Modo 3)
  wire [7:0] s_dur_efetiva      = (s_duracao_rom == 8'd0) ? 8'd1 : s_duracao_rom;
  wire [7:0] s_pausa_efetiva    = (s_pausa_rom == 8'd0) ? 8'd1 : s_pausa_rom;
  wire [8:0] s_total_ticks_demo = {1'b0, s_dur_efetiva} + {1'b0, s_pausa_efetiva};

  reg [31:0] cont_demo_ciclos_reg;
  reg [8:0]  tick_demo_reg;
  reg        r_pulso_bpm_reg;
  reg        r_aguarda_rom_demo_reg;
  assign pulso_bpm = r_pulso_bpm_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
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
        if (cont_demo_ciclos_reg >= (CiclosTick8ms - 1)) begin
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
