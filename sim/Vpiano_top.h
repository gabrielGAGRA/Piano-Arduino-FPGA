#ifndef SIM_VPIANO_TOP_H_
#define SIM_VPIANO_TOP_H_

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Cycle-accurate C++ RTL model of piano_top.v and all 28 synthesized Verilog
// submodules (Verilator-compatible Vpiano_top interface).
// Verified cycle-by-cycle against ModelSim (vlog/vsim) in run_cosim_tests.py.
class Vpiano_top
{
public:
  // Configurable timing parameters matching piano_top #( ... )
  uint32_t param_debounce_tecla;
  uint32_t param_debounce_controle;
  uint32_t param_clock_div_uart;
  uint32_t param_ciclos_tick_8ms;
  uint32_t param_clock_freq;

  // Top-level Input Ports
  uint8_t clk;
  uint8_t reset_n;
  uint8_t gpio_keys;
  uint8_t btn_modo_n;
  uint8_t btn_musica_n;
  uint8_t btn_intensidade_n;
  uint8_t btn_oitava_up_n;
  uint8_t btn_oitava_down_n;
  uint8_t btn_sustenido;

  // Top-level Output Ports
  uint8_t saida_serial;
  uint8_t servo_controle;
  uint8_t led_vermelho;
  uint8_t led_sustenido;
  uint8_t led_oitava_up;
  uint8_t led_oitava_down;
  uint8_t hex5_modo;
  uint8_t hex4_oitava;
  uint8_t hex3_musica_dezena;
  uint8_t hex2_musica_unidade;
  uint8_t hex1_nota;
  uint8_t hex0_sustenido;

  explicit Vpiano_top(uint32_t debounce_tecla = 500000,
                      uint32_t debounce_controle = 400000,
                      uint32_t clock_div_uart = 434,
                      uint32_t ciclos_tick_8ms = 400000,
                      const char *rom_hex_path = "music/partituras.hex")
      : param_debounce_tecla(debounce_tecla),
        param_debounce_controle(debounce_controle),
        param_clock_div_uart(clock_div_uart),
        param_ciclos_tick_8ms(ciclos_tick_8ms),
        param_clock_freq(50000000),
        clk(0),
        reset_n(1),
        gpio_keys(0),
        btn_modo_n(1),
        btn_musica_n(1),
        btn_intensidade_n(1),
        btn_oitava_up_n(1),
        btn_oitava_down_n(1),
        btn_sustenido(0),
        saida_serial(1),
        servo_controle(0),
        led_vermelho(0),
        led_sustenido(0),
        led_oitava_up(0),
        led_oitava_down(0),
        hex5_modo(0x7F),
        hex4_oitava(0x7F),
        hex3_musica_dezena(0x7F),
        hex2_musica_unidade(0x7F),
        hex1_nota(0x7F),
        hex0_sustenido(0x7F),
        prev_clk_(0)
  {
    memset(rom_, 0, sizeof(rom_));
    memset(ram_, 0, sizeof(ram_));
    initDefaultRomOffsets();
    loadRomOffsetsFromVerilog("tabela_offsets_partituras.v");
    loadRomHex(rom_hex_path);
    resetAllState();
    updateCombinational();
  }

  void initDefaultRomOffsets()
  {
    memset(rom_offsets_, 0, sizeof(rom_offsets_));
    rom_offsets_[4] = 1;
    rom_offsets_[6] = 799;
    rom_offsets_[18] = 807;
    rom_offsets_[27] = 1355;
    rom_offsets_[40] = 1813;
  }

  bool loadRomOffsetsFromVerilog(const char *verilog_path)
  {
    FILE *f = fopen(verilog_path, "r");
    if (!f)
    {
      return false;
    }
    char line[256];
    while (fgets(line, sizeof(line), f))
    {
      unsigned int idx = 0, addr = 0;
      const char *p = strstr(line, "6'd");
      if (p && sscanf(p, "6'd%u: base_addr = 14'd%u;", &idx, &addr) == 2)
      {
        if (idx < 64)
        {
          rom_offsets_[idx] = static_cast<uint16_t>(addr & 0x3FFFU);
        }
      }
    }
    fclose(f);
    return true;
  }

  bool loadRomHex(const char *path)
  {
    FILE *f = fopen(path, "r");
    if (!f)
    {
      return false;
    }
    char line[256];
    size_t addr = 0;
    while (fgets(line, sizeof(line), f) && addr < kRomDepth)
    {
      char *p = line;
      while (*p == ' ' || *p == '\t')
      {
        ++p;
      }
      if (*p == '\0' || *p == '\n' || *p == '\r' || *p == '/')
      {
        continue;
      }
      if (*p == '@')
      {
        addr = static_cast<size_t>(strtoul(p + 1, nullptr, 16));
        continue;
      }
      uint32_t val = static_cast<uint32_t>(strtoul(p, nullptr, 16));
      rom_[addr++] = val & 0x3FFFFFFFU;
    }
    fclose(f);
    return true;
  }

  void eval()
  {
    // Asynchronous reset of sincronizador_reset when !reset_n
    if ((reset_n & 1U) == 0U)
    {
      sync_rst_s1_ = 1U;
      sync_rst_s2_ = 1U;
    }

    if (sync_rst_s2_ != 0U)
    {
      applyAsyncReset();
    }

    uint8_t cur_clk = clk & 1U;
    if (prev_clk_ == 0U && cur_clk == 1U)
    {
      updateCombinational();
      clockRisingEdge();
    }

    if ((reset_n & 1U) == 0U)
    {
      sync_rst_s1_ = 1U;
      sync_rst_s2_ = 1U;
    }
    if (sync_rst_s2_ != 0U)
    {
      applyAsyncReset();
    }

    updateCombinational();
    prev_clk_ = cur_clk;
  }

  // Diagnostic accessors for white-box verification
  uint8_t debug_modo_ativo() const { return w_fsm_modo_ativo_; }
  uint8_t debug_oitava_atual() const { return w_oitava_atual_; }
  uint8_t debug_sustenido_atual() const { return w_sustenido_atual_; }
  uint8_t debug_sel_musica() const { return w_out_sel_musica_; }
  uint8_t debug_volume() const { return r_estado_vol_; }
  uint8_t debug_mostra_vol() const { return w_mostra_vol_; }
  uint16_t debug_endereco_ram() const { return r_endereco_ram_; }
  uint8_t debug_nota_tocando_tx() const { return r_tx_nota_tocando_; }
  uint8_t debug_fsm_state() const { return r_uc_state_; }
  uint8_t debug_metro_posicao() const { return r_metro_posicao_; }
  uint8_t debug_estado_intensidade() const { return r_estado_intensidade_; }
  uint32_t debug_read_ram(uint16_t addr) const { return ram_[addr & 0x3FFU]; }
  void debug_set_endereco_ram(uint16_t addr)
  {
    r_endereco_ram_ = addr & 0x3FFU;
    updateCombinational();
  }

private:
  static constexpr size_t kRomDepth = 16384;
  static constexpr size_t kRamDepth = 1024;

  // unidad_controle states
  enum UcState : uint8_t
  {
    kUcInicial = 0,
    kUcLivre = 1,
    kUcIniciaMusica = 2,
    kUcEsperaNota = 3,
    kUcComparaNota = 4,
    kUcProximo = 5,
    kUcEsperaSoltar = 6,
    kUcFimMusicaSt = 7,
    kUcIniciaGravacao = 8,
    kUcGravEsperaNota = 9,
    kUcGravArmazena = 10,
    kUcGravProximo = 11,
    kUcGravSoltar = 12,
    kUcDemoTocaNota = 13,
    kUcDemoProximo = 14,
    kUcIniciaDemo = 15,
    kUcLeRamModo1 = 16
  };

  struct Debounce1
  {
    uint8_t sync0;
    uint8_t sync1;
    uint8_t out;
    uint32_t cnt;

    void reset()
    {
      sync0 = 0;
      sync1 = 0;
      out = 0;
      cnt = 0;
    }

    void step(uint8_t in_bit, uint32_t tempo_filtro)
    {
      uint8_t old_sync0 = sync0;
      uint8_t old_sync1 = sync1;
      uint8_t old_out = out;
      uint32_t old_cnt = cnt;
      uint32_t tf = tempo_filtro & 0xFFFFFU;

      sync0 = in_bit & 1U;
      sync1 = old_sync0;
      if (old_sync1 == old_out)
      {
        cnt = 0;
      }
      else
      {
        if (old_cnt >= tf)
        {
          out = old_sync1;
          cnt = 0;
        }
        else
        {
          cnt = (old_cnt + 1U) & 0xFFFFFU;
        }
      }
    }
  };

  struct Debounce7
  {
    uint8_t sync0;
    uint8_t sync1;
    uint8_t out;
    uint32_t cnt[7];

    void reset()
    {
      sync0 = 0;
      sync1 = 0;
      out = 0;
      for (int i = 0; i < 7; ++i)
      {
        cnt[i] = 0;
      }
    }

    void step(uint8_t in_vec, uint32_t tempo_filtro)
    {
      uint8_t old_sync0 = sync0;
      uint8_t old_sync1 = sync1;
      uint8_t old_out = out;
      uint32_t tf = tempo_filtro & 0xFFFFFU;

      sync0 = in_vec & 0x7FU;
      sync1 = old_sync0;
      uint8_t next_out = old_out;
      for (int i = 0; i < 7; ++i)
      {
        uint8_t s1_b = (old_sync1 >> i) & 1U;
        uint8_t o_b = (old_out >> i) & 1U;
        uint32_t old_c = cnt[i];
        if (s1_b == o_b)
        {
          cnt[i] = 0;
        }
        else
        {
          if (old_c >= tf)
          {
            if (s1_b)
            {
              next_out |= (1U << i);
            }
            else
            {
              next_out &= ~(1U << i);
            }
            cnt[i] = 0;
          }
          else
          {
            cnt[i] = (old_c + 1U) & 0xFFFFFU;
          }
        }
      }
      out = next_out;
    }
  };

  struct EdgeDet
  {
    uint8_t d1;
    uint8_t d2;

    void reset()
    {
      d1 = 0;
      d2 = 0;
    }

    void step(uint8_t sig)
    {
      uint8_t old_d1 = d1;
      d1 = sig & 1U;
      d2 = old_d1;
    }

    uint8_t pulse() const { return (d1 != 0U && d2 == 0U) ? 1U : 0U; }
  };

  // Memories (M10K synchronous read/write)
  uint32_t rom_[kRomDepth];
  uint32_t ram_[kRamDepth];
  uint16_t rom_offsets_[64];
  uint32_t r_rom_dout_;
  uint32_t r_ram_dout_;

  // Reset synchronizer
  uint8_t prev_clk_;
  uint8_t sync_rst_s1_;
  uint8_t sync_rst_s2_;

  // Debouncers & edge detectors
  Debounce7 db_notas_;
  Debounce1 db_sustenido_;
  Debounce1 db_modo_;
  Debounce1 db_musica_;
  Debounce1 db_intensidade_;
  Debounce1 db_oitava_up_;
  Debounce1 db_oitava_down_;

  EdgeDet ed_tecla_demo_;
  EdgeDet ed_musica_;
  EdgeDet ed_intensidade_;
  EdgeDet ed_oit_up_;
  EdgeDet ed_oit_down_;

  // unidade_controle state
  uint8_t r_uc_state_;
  uint8_t w_uc_state_next_;
  uint8_t w_fsm_modo_ativo_;
  uint8_t w_fsm_escreve_ram_;
  uint8_t w_fsm_zera_end_;
  uint8_t w_fsm_conta_end_;

  // fluxo_dados registers
  uint8_t r_modo_prev_;
  uint8_t r_combo_ativo_;
  uint8_t r_estado_vol_;
  uint32_t r_timer_display_vol_;
  uint8_t r_sel_musica_;
  uint8_t r_oitava_livre_;
  uint8_t r_nota_tocada_;
  uint8_t r_botoes_ant_;
  uint16_t r_endereco_ram_;

  // Recording mode (Modo 2) registers
  uint32_t r_cont_grav_ciclos_;
  uint8_t r_tem_nota_grav_prev_;
  uint8_t r_nota_grav_;
  uint8_t r_vel_grav_;
  uint8_t r_duracao_grav_;
  uint8_t r_pausa_grav_;
  uint8_t r_grav_tem_dados_;
  uint16_t r_ultimo_end_gravado_;

  // Learning mode (Modo 1) anti-pop latch registers
  uint8_t r_oitava_apre_;
  uint8_t r_sustenido_apre_;

  // LED PWM registers
  uint8_t r_estado_intensidade_;
  uint16_t r_pwm_counter_;

  // Demo mode (Modo 3) timer registers
  uint32_t r_cont_demo_ciclos_;
  uint16_t r_tick_demo_;
  uint8_t r_pulso_bpm_;
  uint8_t r_nota_ativa_bpm_;
  uint8_t r_aguarda_rom_demo_;

  // gerenciador_midi_tx & tx_serial_8N1 registers
  uint8_t r_tx_mgr_estado_;
  uint8_t r_tx_nota_tocando_;
  uint8_t r_tx_byte0_;
  uint8_t r_tx_byte1_;
  uint8_t r_tx_byte2_;
  uint8_t r_tx_byte_idx_;

  uint8_t r_uart_uc_estado_;
  uint16_t r_uart_shift_reg_;
  uint8_t r_uart_bit_cnt_;
  uint16_t r_uart_baud_cnt_;

  // Metronome & servo registers
  uint8_t r_metro_uc_state_;
  uint32_t r_metro_cnt_tempo_;
  uint8_t r_metro_posicao_;
  uint32_t r_servo_cnt_;
  uint32_t r_servo_largura_pwm_;
  uint8_t r_servo_controle_;

  // Internal combinational wires
  uint8_t w_mudou_modo_;
  uint8_t w_mudou_musica_;
  uint8_t w_tem_nota_ativa_;
  uint8_t w_acerto_nota_;
  uint8_t w_fim_musica_;
  uint8_t w_tem_nota_;
  uint8_t w_out_sel_musica_;
  uint16_t w_rom_address_;
  uint32_t w_nota_paragravar_;
  uint8_t w_nota_midi_rom_;
  uint8_t w_velocity_rom_;
  uint8_t w_duracao_rom_;
  uint8_t w_pausa_rom_;
  uint8_t w_oitava_esperada_;
  uint8_t w_sustenido_esperado_;
  uint8_t w_nota_esperada_;
  uint8_t w_oitava_atual_;
  uint8_t w_sustenido_atual_;
  uint8_t w_nota_midi_usuario_;
  uint8_t w_velocity_final_;
  uint8_t w_nota_midi_desejada_;
  uint8_t w_mostra_vol_;
  uint32_t w_t_passo_metronomo_;

  void resetAllState()
  {
    r_rom_dout_ = 0;
    r_ram_dout_ = 0;
    r_endereco_ram_ = 0;
    sync_rst_s1_ = 1U;
    sync_rst_s2_ = 1U;
    applyAsyncReset();
  }

  void applyAsyncReset()
  {
    db_notas_.reset();
    db_sustenido_.reset();
    db_modo_.reset();
    db_musica_.reset();
    db_intensidade_.reset();
    db_oitava_up_.reset();
    db_oitava_down_.reset();

    ed_tecla_demo_.reset();
    ed_musica_.reset();
    ed_intensidade_.reset();
    ed_oit_up_.reset();
    ed_oit_down_.reset();

    r_uc_state_ = kUcInicial;
    r_modo_prev_ = 0;
    r_combo_ativo_ = 0;
    r_estado_vol_ = 0;
    r_timer_display_vol_ = 0;
    r_sel_musica_ = 0;
    r_oitava_livre_ = 4;
    r_nota_tocada_ = 0;
    r_botoes_ant_ = 0;

    r_cont_grav_ciclos_ = 0;
    r_tem_nota_grav_prev_ = 0;
    r_nota_grav_ = 0;
    r_vel_grav_ = 0;
    r_duracao_grav_ = 1;
    r_pausa_grav_ = 0;
    r_grav_tem_dados_ = 0;
    r_ultimo_end_gravado_ = 0;

    r_oitava_apre_ = 4;
    r_sustenido_apre_ = 0;

    r_estado_intensidade_ = 0;
    r_pwm_counter_ = 0;

    r_cont_demo_ciclos_ = 0;
    r_tick_demo_ = 0;
    r_pulso_bpm_ = 0;
    r_nota_ativa_bpm_ = 0;
    r_aguarda_rom_demo_ = 0;

    r_tx_mgr_estado_ = 0;
    r_tx_nota_tocando_ = 0;
    r_tx_byte0_ = 0;
    r_tx_byte1_ = 0;
    r_tx_byte2_ = 0;
    r_tx_byte_idx_ = 0;

    r_uart_uc_estado_ = 0;
    r_uart_shift_reg_ = 0x7FFU;
    r_uart_bit_cnt_ = 0;
    r_uart_baud_cnt_ = 0;

    r_metro_uc_state_ = 0;
    r_metro_cnt_tempo_ = 0;
    r_metro_posicao_ = 3;
    r_servo_cnt_ = 0;
    r_servo_largura_pwm_ = 73810U;
    r_servo_controle_ = 0;
  }

  uint16_t lookupRomOffset(uint8_t musica_id) const
  {
    if (musica_id < 64)
    {
      return rom_offsets_[musica_id];
    }
    return 0;
  }

  static void decodeMidiNote(uint8_t nota_midi, uint8_t &oitava,
                             uint8_t &sustenido, uint8_t &nota_id)
  {
    if (nota_midi < 24 || nota_midi > 107)
    {
      oitava = 0;
      sustenido = 0;
      nota_id = 0;
      return;
    }
    oitava = static_cast<uint8_t>(((nota_midi - 24) / 12) + 1);
    uint8_t semitone = static_cast<uint8_t>((nota_midi - 24) % 12);
    static const uint8_t kSust[12] = {0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0};
    static const uint8_t kId[12] = {1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6, 7};
    sustenido = kSust[semitone];
    nota_id = kId[semitone];
  }

  static uint8_t encodeMidiNote(uint8_t oitava, uint8_t sustenido,
                                uint8_t nota_id)
  {
    if (oitava == 0 || oitava > 7 || nota_id == 0 || nota_id > 7)
    {
      return 0;
    }
    uint8_t base = static_cast<uint8_t>(oitava * 12 + 12);
    uint8_t offset = 0;
    switch (nota_id)
    {
    case 1:
      offset = sustenido ? 1 : 0;
      break;
    case 2:
      offset = sustenido ? 3 : 2;
      break;
    case 3:
      offset = sustenido ? 5 : 4;
      break;
    case 4:
      offset = sustenido ? 6 : 5;
      break;
    case 5:
      offset = sustenido ? 8 : 7;
      break;
    case 6:
      offset = sustenido ? 10 : 9;
      break;
    case 7:
      offset = sustenido ? ((oitava < 7) ? 12 : 11) : 11;
      break;
    default:
      offset = 0;
      break;
    }
    return (base + offset) & 0x7FU;
  }

  static uint8_t decodeCifra(uint8_t nota_id)
  {
    switch (nota_id)
    {
    case 1:
      return 0x46; // C (1000110)
    case 2:
      return 0x21; // d (0100001)
    case 3:
      return 0x06; // E (0000110)
    case 4:
      return 0x0E; // F (0001110)
    case 5:
      return 0x10; // G (0010000)
    case 6:
      return 0x08; // A (0001000)
    case 7:
      return 0x03; // b (0000011)
    default:
      return 0x7F; // Apagado
    }
  }

  static uint8_t decodeHex7Seg(uint8_t hexa)
  {
    switch (hexa & 0x1FU)
    {
    case 0x00:
      return 0x40;
    case 0x01:
      return 0x79;
    case 0x02:
      return 0x24;
    case 0x03:
      return 0x30;
    case 0x04:
      return 0x19;
    case 0x05:
      return 0x12;
    case 0x06:
      return 0x02;
    case 0x07:
      return 0x78;
    case 0x08:
      return 0x00;
    case 0x09:
      return 0x10;
    case 0x0A:
      return 0x08;
    case 0x0B:
      return 0x03;
    case 0x0C:
      return 0x46;
    case 0x0D:
      return 0x21;
    case 0x0E:
      return 0x06;
    case 0x0F:
      return 0x0E;
    default:
      return 0x7F;
    }
  }

  static uint32_t lookupMetronomeStep(uint8_t sel_musica)
  {
    static const uint32_t kSteps[42] = {
        3105590, 3601440, 3663003, 2801120, 5639097, 2477291, 4285714,
        3826530, 4464285, 2976190, 3484320, 3174603, 5870841, 4511278,
        5791505, 3631961, 4160887, 4285714, 2111189, 4373177, 3039513,
        1635768, 4285714, 5791505, 1948051, 3061224, 3792667, 3631961,
        3896103, 3694581, 3726708, 3061224, 3174603, 5163511, 3428571,
        5102040, 4658385, 3571428, 2645502, 3296703, 3571428, 3061224};
    if (sel_musica < 42)
    {
      return kSteps[sel_musica];
    }
    return 4285714U;
  }

  void updateCombinational()
  {
    // 1. Decode current modo_ativo and outputs of unidade_controle (Mealy/Moore)
    w_fsm_modo_ativo_ = 0;
    w_fsm_escreve_ram_ = 0;
    w_fsm_zera_end_ = 0;
    w_fsm_conta_end_ = 0;

    switch (r_uc_state_)
    {
    case kUcInicial:
      w_fsm_zera_end_ = 1;
      w_fsm_modo_ativo_ = 0;
      break;
    case kUcLivre:
      w_fsm_zera_end_ = 1;
      w_fsm_modo_ativo_ = 0;
      break;
    case kUcIniciaMusica:
      w_fsm_modo_ativo_ = 1;
      w_fsm_zera_end_ = 1;
      break;
    case kUcEsperaNota:
    case kUcComparaNota:
    case kUcEsperaSoltar:
    case kUcLeRamModo1:
    case kUcFimMusicaSt:
      w_fsm_modo_ativo_ = 1;
      break;
    case kUcProximo:
      w_fsm_modo_ativo_ = 1;
      w_fsm_conta_end_ = 1;
      break;
    case kUcIniciaGravacao:
      w_fsm_modo_ativo_ = 2;
      w_fsm_zera_end_ = 1;
      break;
    case kUcGravEsperaNota:
    case kUcGravSoltar:
      w_fsm_modo_ativo_ = 2;
      break;
    case kUcGravArmazena:
      w_fsm_modo_ativo_ = 2;
      w_fsm_escreve_ram_ = 1;
      break;
    case kUcGravProximo:
      w_fsm_modo_ativo_ = 2;
      w_fsm_conta_end_ = 1;
      break;
    case kUcIniciaDemo:
      w_fsm_modo_ativo_ = 3;
      w_fsm_zera_end_ = 1;
      break;
    case kUcDemoTocaNota:
      w_fsm_modo_ativo_ = 3;
      break;
    case kUcDemoProximo:
      w_fsm_modo_ativo_ = 3;
      w_fsm_conta_end_ = 1;
      break;
    default:
      break;
    }

    // 2. fluxo_dados combinational signals
    uint8_t s_modo_pressed = db_modo_.out;
    uint8_t s_modo_released = (!s_modo_pressed && r_modo_prev_) ? 1U : 0U;
    w_mudou_modo_ = (s_modo_released && !r_combo_ativo_) ? 1U : 0U;
    w_mudou_musica_ = ed_musica_.pulse();
    w_mostra_vol_ = (r_timer_display_vol_ > 0U) ? 1U : 0U;

    w_out_sel_musica_ = (w_fsm_modo_ativo_ == 2) ? 42U : r_sel_musica_;
    w_tem_nota_ = (db_notas_.out != 0U) ? 1U : 0U;

    uint16_t offset_base = lookupRomOffset(w_out_sel_musica_);
    w_rom_address_ = (offset_base + r_endereco_ram_) & 0x3FFFU;

    w_nota_paragravar_ =
        ((static_cast<uint32_t>(r_pausa_grav_) & 0xFFU) << 22) |
        ((static_cast<uint32_t>(r_duracao_grav_) & 0xFFU) << 14) |
        ((static_cast<uint32_t>(r_vel_grav_) & 0x7FU) << 7) |
        (static_cast<uint32_t>(r_nota_grav_) & 0x7FU);

    uint32_t s_dado_ram =
        (w_out_sel_musica_ == 42U) ? r_ram_dout_ : r_rom_dout_;
    uint32_t s_dado_ram_final =
        ((w_out_sel_musica_ == 42U) &&
         (!r_grav_tem_dados_ || (r_endereco_ram_ > r_ultimo_end_gravado_)))
            ? 0U
            : s_dado_ram;

    w_nota_midi_rom_ = s_dado_ram_final & 0x7FU;
    w_velocity_rom_ = (s_dado_ram_final >> 7) & 0x7FU;
    w_duracao_rom_ = (s_dado_ram_final >> 14) & 0xFFU;
    w_pausa_rom_ = (s_dado_ram_final >> 22) & 0xFFU;

    decodeMidiNote(w_nota_midi_rom_, w_oitava_esperada_, w_sustenido_esperado_,
                   w_nota_esperada_);

    uint8_t s_ativo_apre_demo =
        (w_fsm_modo_ativo_ == 1 || w_fsm_modo_ativo_ == 3) ? 1U : 0U;

    if (w_fsm_modo_ativo_ == 3)
    {
      w_oitava_atual_ =
          (w_nota_esperada_ != 0U) ? w_oitava_esperada_ : r_oitava_livre_;
      w_sustenido_atual_ =
          (w_nota_esperada_ != 0U) ? w_sustenido_esperado_ : db_sustenido_.out;
    }
    else if (w_fsm_modo_ativo_ == 1)
    {
      w_oitava_atual_ = r_oitava_apre_;
      w_sustenido_atual_ = r_sustenido_apre_;
    }
    else
    {
      w_oitava_atual_ = r_oitava_livre_;
      w_sustenido_atual_ = db_sustenido_.out;
    }

    uint8_t s_led_up = (w_oitava_esperada_ > r_oitava_livre_) ? 1U : 0U;
    uint8_t s_led_down = (w_oitava_esperada_ < r_oitava_livre_) ? 1U : 0U;
    led_oitava_up =
        (s_ativo_apre_demo && (w_nota_esperada_ != 0U)) ? s_led_up : 0U;
    led_oitava_down =
        (s_ativo_apre_demo && (w_nota_esperada_ != 0U)) ? s_led_down : 0U;

    w_nota_midi_usuario_ =
        encodeMidiNote(w_oitava_atual_, w_sustenido_atual_, r_nota_tocada_);

    uint8_t s_is_demo = (w_fsm_modo_ativo_ == 3) ? 1U : 0U;
    uint8_t s_tem_nota_usuario =
        (w_tem_nota_ && (r_nota_tocada_ != 0U) && (w_nota_midi_usuario_ != 0U))
            ? 1U
            : 0U;
    w_tem_nota_ativa_ =
        s_is_demo ? ((w_nota_esperada_ != 0U && r_nota_ativa_bpm_) ? 1U : 0U)
                  : s_tem_nota_usuario;

    uint8_t s_vel_base =
        s_is_demo ? ((w_velocity_rom_ == 0U) ? 100U : w_velocity_rom_) : 127U;
    switch (r_estado_vol_)
    {
    case 0:
      w_velocity_final_ = s_vel_base;
      break;
    case 1:
      w_velocity_final_ =
          ((s_vel_base >> 1) + (s_vel_base >> 2)) & 0x7FU;
      break;
    case 2:
      w_velocity_final_ = (s_vel_base >> 1) & 0x7FU;
      break;
    default:
      w_velocity_final_ = s_vel_base;
      break;
    }

    w_nota_midi_desejada_ =
        s_is_demo ? (r_nota_ativa_bpm_ ? w_nota_midi_rom_ : 0U)
                  : (s_tem_nota_usuario ? w_nota_midi_usuario_ : 0U);

    uint8_t s_id_para_led =
        (w_fsm_modo_ativo_ == 1 || w_fsm_modo_ativo_ == 3) ? w_nota_esperada_
                                                           : r_nota_tocada_;
    uint8_t fd_leds_cifra = decodeCifra(s_id_para_led);

    w_acerto_nota_ = ((r_nota_tocada_ == w_nota_esperada_) && w_tem_nota_ &&
                      (w_fsm_modo_ativo_ == 1))
                         ? 1U
                         : 0U;
    uint8_t cont_fim = (r_endereco_ram_ == 1023U) ? 1U : 0U;
    w_fim_musica_ =
        (w_fsm_modo_ativo_ == 2) ? cont_fim : ((w_nota_esperada_ == 0U) ? 1U : 0U);

    // Next state of unidade_controle
    w_uc_state_next_ = r_uc_state_;
    switch (r_uc_state_)
    {
    case kUcInicial:
      w_uc_state_next_ = kUcLivre;
      break;
    case kUcLivre:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcIniciaMusica;
      break;
    case kUcIniciaMusica:
      w_uc_state_next_ = kUcEsperaNota;
      break;
    case kUcEsperaNota:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcIniciaGravacao;
      else if (w_mudou_musica_)
        w_uc_state_next_ = kUcIniciaMusica;
      else if (w_tem_nota_ativa_)
        w_uc_state_next_ = kUcComparaNota;
      break;
    case kUcComparaNota:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcIniciaGravacao;
      else if (w_mudou_musica_)
        w_uc_state_next_ = kUcIniciaMusica;
      else if (w_acerto_nota_)
        w_uc_state_next_ = kUcEsperaSoltar;
      else if (!w_tem_nota_ativa_)
        w_uc_state_next_ = kUcEsperaNota;
      break;
    case kUcEsperaSoltar:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcIniciaGravacao;
      else if (w_mudou_musica_)
        w_uc_state_next_ = kUcIniciaMusica;
      else if (!w_tem_nota_ativa_)
        w_uc_state_next_ = w_fim_musica_ ? kUcFimMusicaSt : kUcProximo;
      break;
    case kUcProximo:
      w_uc_state_next_ = kUcLeRamModo1;
      break;
    case kUcLeRamModo1:
      w_uc_state_next_ = kUcEsperaNota;
      break;
    case kUcFimMusicaSt:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcIniciaGravacao;
      break;
    case kUcIniciaGravacao:
      w_uc_state_next_ = kUcGravEsperaNota;
      break;
    case kUcGravEsperaNota:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcIniciaDemo;
      else if (w_tem_nota_ativa_)
        w_uc_state_next_ = kUcGravSoltar;
      break;
    case kUcGravSoltar:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcIniciaDemo;
      else if (!w_tem_nota_ativa_)
        w_uc_state_next_ = kUcGravArmazena;
      break;
    case kUcGravArmazena:
      w_uc_state_next_ = kUcGravProximo;
      break;
    case kUcGravProximo:
      w_uc_state_next_ = kUcGravEsperaNota;
      break;
    case kUcIniciaDemo:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcLivre;
      else if (w_mudou_musica_)
        w_uc_state_next_ = kUcIniciaDemo;
      else if (ed_tecla_demo_.pulse())
        w_uc_state_next_ = kUcDemoTocaNota;
      break;
    case kUcDemoTocaNota:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcLivre;
      else if (w_mudou_musica_)
        w_uc_state_next_ = kUcIniciaDemo;
      else if (r_pulso_bpm_)
        w_uc_state_next_ = w_fim_musica_ ? kUcIniciaDemo : kUcDemoProximo;
      break;
    case kUcDemoProximo:
      if (w_mudou_modo_)
        w_uc_state_next_ = kUcLivre;
      else if (w_mudou_musica_)
        w_uc_state_next_ = kUcIniciaDemo;
      else
        w_uc_state_next_ = kUcDemoTocaNota;
      break;
    default:
      w_uc_state_next_ = kUcInicial;
      break;
    }

    // PWM output
    uint8_t s_duty_cycle = 0xFU;
    switch (r_estado_intensidade_)
    {
    case 0:
      s_duty_cycle = 0xFU;
      break;
    case 1:
      s_duty_cycle = 0xCU;
      break;
    case 2:
      s_duty_cycle = 0x8U;
      break;
    case 3:
      s_duty_cycle = 0x4U;
      break;
    case 4:
      s_duty_cycle = 0x0U;
      break;
    default:
      s_duty_cycle = 0xFU;
      break;
    }
    uint8_t s_pwm_out =
        (s_duty_cycle == 0U)
            ? 0U
            : ((s_duty_cycle == 0xFU)
                   ? 1U
                   : ((r_pwm_counter_ < (static_cast<uint16_t>(s_duty_cycle) << 12))
                          ? 1U
                          : 0U));

    w_t_passo_metronomo_ = lookupMetronomeStep(r_sel_musica_);

    // Top-level outputs: serial, servo, painel_display_leds
    saida_serial = r_uart_shift_reg_ & 1U;
    servo_controle = r_servo_controle_ & 1U;

    uint8_t hex5_normal = decodeHex7Seg(w_fsm_modo_ativo_);
    hex5_modo = w_mostra_vol_ ? ((r_estado_vol_ == 0U) ? 0x79U : 0x7FU)
                              : hex5_normal;

    uint8_t hex4_normal = decodeHex7Seg(w_oitava_atual_);
    hex4_oitava =
        w_mostra_vol_
            ? ((r_estado_vol_ == 0U) ? 0x40U
                                     : ((r_estado_vol_ == 1U) ? 0x78U : 0x12U))
            : hex4_normal;

    uint8_t musica_dez_val = w_out_sel_musica_ / 10U;
    uint8_t musica_uni_val = w_out_sel_musica_ % 10U;
    uint8_t dez_idx =
        (w_fsm_modo_ativo_ == 0U || musica_dez_val == 0U) ? 0x1FU : musica_dez_val;
    uint8_t hex3_normal = decodeHex7Seg(dez_idx);
    hex3_musica_dezena =
        w_mostra_vol_
            ? ((r_estado_vol_ == 0U) ? 0x40U
                                     : ((r_estado_vol_ == 1U) ? 0x12U : 0x40U))
            : hex3_normal;

    uint8_t uni_idx = (w_fsm_modo_ativo_ == 0U) ? 0x1FU : musica_uni_val;
    uint8_t hex2_normal = decodeHex7Seg(uni_idx);
    hex2_musica_unidade = w_mostra_vol_ ? 0x0CU : hex2_normal;

    hex1_nota = fd_leds_cifra;
    hex0_sustenido = w_sustenido_atual_ ? 0x36U : 0x7FU;

    led_sustenido = (w_fsm_modo_ativo_ == 1U) ? w_sustenido_atual_ : 0U;
    uint8_t nota_led_valida =
        ((w_fsm_modo_ativo_ == 1U || w_fsm_modo_ativo_ == 3U) &&
         (s_id_para_led != 0U))
            ? 1U
            : 0U;
    uint8_t raw_led =
        nota_led_valida ? static_cast<uint8_t>(1U << (s_id_para_led - 1U)) : 0U;
    led_vermelho = s_pwm_out ? raw_led : 0U;
  }

  void clockRisingEdge()
  {
    // Snapshot current state for non-blocking (<=) semantics
    uint8_t old_arst = sync_rst_s2_;

    // Always-clocked blocks that do NOT depend on arst:
    // 1. sync_rom_partituras
    uint32_t next_rom_dout = rom_[w_rom_address_ & 0x3FFFU];

    // 2. sync_ram_gravacao
    uint16_t ram_addr = r_endereco_ram_ & 0x3FFU;
    uint32_t next_ram_dout = ram_[ram_addr];
    if (w_fsm_escreve_ram_)
    {
      ram_[ram_addr] = w_nota_paragravar_;
    }

    // 3. contador_m_addr (has .arst(1'b0))
    uint16_t next_endereco_ram = r_endereco_ram_;
    if (w_fsm_zera_end_)
    {
      next_endereco_ram = 0;
    }
    else if (w_fsm_conta_end_)
    {
      next_endereco_ram =
          (r_endereco_ram_ == 1023U) ? 0U : ((r_endereco_ram_ + 1U) & 0x3FFU);
    }

    // Update reset synchronizer
    if ((reset_n & 1U) == 0U)
    {
      sync_rst_s1_ = 1U;
      sync_rst_s2_ = 1U;
    }
    else
    {
      sync_rst_s2_ = sync_rst_s1_;
      sync_rst_s1_ = 0U;
    }

    if (old_arst != 0U || sync_rst_s2_ != 0U)
    {
      r_rom_dout_ = next_rom_dout;
      r_ram_dout_ = next_ram_dout;
      r_endereco_ram_ = next_endereco_ram;
      applyAsyncReset();
      return;
    }

    // Snapshot pre-clock signals used by multiple sequential blocks
    uint8_t old_db_botoes = db_notas_.out;
    uint8_t old_db_sustenido = db_sustenido_.out;
    uint8_t old_db_modo = db_modo_.out;
    uint8_t old_db_musica = db_musica_.out;
    uint8_t old_db_intensidade = db_intensidade_.out;
    uint8_t old_db_oit_up = db_oitava_up_.out;
    uint8_t old_db_oit_down = db_oitava_down_.out;

    uint8_t pulse_musica = ed_musica_.pulse();
    uint8_t pulse_intensidade = ed_intensidade_.pulse();
    uint8_t pulse_oit_up = ed_oit_up_.pulse();
    uint8_t pulse_oit_down = ed_oit_down_.pulse();

    // Step debouncers and edge detectors
    db_notas_.step(gpio_keys & 0x7FU, param_debounce_tecla);
    db_sustenido_.step(btn_sustenido & 1U, param_debounce_tecla);
    db_modo_.step((~btn_modo_n) & 1U, param_debounce_controle);
    db_musica_.step((~btn_musica_n) & 1U, param_debounce_controle);
    db_intensidade_.step((~btn_intensidade_n) & 1U, param_debounce_controle);
    db_oitava_up_.step((~btn_oitava_up_n) & 1U, param_debounce_controle);
    db_oitava_down_.step((~btn_oitava_down_n) & 1U, param_debounce_controle);

    ed_tecla_demo_.step((old_db_botoes != 0U) ? 1U : 0U);
    ed_musica_.step(old_db_musica);
    ed_intensidade_.step(old_db_intensidade);
    ed_oit_up_.step(old_db_oit_up);
    ed_oit_down_.step(old_db_oit_down);

    // Step unidade_controle
    uint8_t next_uc_state = w_uc_state_next_;

    // Step combo (Modo + Intensidade)
    uint8_t next_modo_prev = old_db_modo;
    uint8_t next_combo_ativo = r_combo_ativo_;
    uint8_t next_estado_vol = r_estado_vol_;
    uint32_t next_timer_vol = r_timer_display_vol_;

    if (next_timer_vol > 0U)
    {
      next_timer_vol -= 1U;
    }
    if (old_db_modo && pulse_intensidade)
    {
      next_combo_ativo = 1U;
      next_timer_vol = (125U * param_ciclos_tick_8ms) & 0x3FFFFFFU;
      next_estado_vol = (r_estado_vol_ == 2U) ? 0U : (r_estado_vol_ + 1U);
    }
    else if (!old_db_modo)
    {
      next_combo_ativo = 0U;
    }

    // Step contador_m_musica (Modulo 43)
    uint8_t next_sel_musica = r_sel_musica_;
    if (pulse_musica)
    {
      next_sel_musica = (r_sel_musica_ == 42U) ? 0U : (r_sel_musica_ + 1U);
    }

    // Step guarda_oitava
    uint8_t next_oitava_livre = r_oitava_livre_;
    if (pulse_oit_up)
    {
      if (r_oitava_livre_ < 7U)
        next_oitava_livre = r_oitava_livre_ + 1U;
    }
    else if (pulse_oit_down)
    {
      if (r_oitava_livre_ > 1U)
        next_oitava_livre = r_oitava_livre_ - 1U;
    }

    // Step logica_notas_prioridade
    uint8_t next_botoes_ant = old_db_botoes;
    uint8_t next_nota_tocada = r_nota_tocada_;
    uint8_t nota_valida = (r_nota_tocada_ != 0U) ? 1U : 0U;
    uint8_t nota_idx = nota_valida ? (r_nota_tocada_ - 1U) : 0U;
    uint8_t tecla_ativa =
        (nota_valida && ((old_db_botoes >> nota_idx) & 1U)) ? 1U : 0U;

    if (!w_tem_nota_)
    {
      next_nota_tocada = 0U;
    }
    else
    {
      bool found_rising = false;
      for (int i = 0; i < 7; ++i)
      {
        if (((old_db_botoes >> i) & 1U) && !((r_botoes_ant_ >> i) & 1U))
        {
          next_nota_tocada = static_cast<uint8_t>(i + 1);
          found_rising = true;
          break;
        }
      }
      if (!found_rising && !tecla_ativa)
      {
        for (int i = 6; i >= 0; --i)
        {
          if ((old_db_botoes >> i) & 1U)
          {
            next_nota_tocada = static_cast<uint8_t>(i + 1);
            break;
          }
        }
      }
    }

    // Step Recording Timer (Modo 2)
    uint32_t next_cont_grav = r_cont_grav_ciclos_;
    uint8_t next_tem_nota_grav_prev = r_tem_nota_grav_prev_;
    uint8_t next_nota_grav = r_nota_grav_;
    uint8_t next_vel_grav = r_vel_grav_;
    uint8_t next_duracao_grav = r_duracao_grav_;
    uint8_t next_pausa_grav = r_pausa_grav_;

    if (w_fsm_modo_ativo_ == 2U)
    {
      next_tem_nota_grav_prev = w_tem_nota_;
      if (w_fsm_zera_end_ || w_fsm_conta_end_)
      {
        next_cont_grav = 0U;
        next_duracao_grav = 1U;
        next_pausa_grav = 0U;
      }
      else if (w_tem_nota_)
      {
        next_nota_grav = w_nota_midi_usuario_;
        next_vel_grav = w_velocity_final_;
        if (!r_tem_nota_grav_prev_)
        {
          next_cont_grav = 0U;
        }
        else if (r_cont_grav_ciclos_ >= (param_ciclos_tick_8ms - 1U))
        {
          next_cont_grav = 0U;
          if (r_duracao_grav_ < 255U)
          {
            next_duracao_grav = r_duracao_grav_ + 1U;
          }
        }
        else
        {
          next_cont_grav = r_cont_grav_ciclos_ + 1U;
        }
      }
      else
      {
        if (r_tem_nota_grav_prev_)
        {
          next_cont_grav = 0U;
        }
        else if (!w_fsm_escreve_ram_)
        {
          if (r_cont_grav_ciclos_ >= (param_ciclos_tick_8ms - 1U))
          {
            next_cont_grav = 0U;
            if (r_pausa_grav_ < 255U)
            {
              next_pausa_grav = r_pausa_grav_ + 1U;
            }
          }
          else
          {
            next_cont_grav = r_cont_grav_ciclos_ + 1U;
          }
        }
      }
    }
    else
    {
      next_cont_grav = 0U;
      next_tem_nota_grav_prev = 0U;
      next_duracao_grav = 1U;
      next_pausa_grav = 0U;
    }

    // Step RAM end-of-recording control
    uint8_t next_grav_tem_dados = r_grav_tem_dados_;
    uint16_t next_ultimo_end_gravado = r_ultimo_end_gravado_;
    if (w_fsm_modo_ativo_ == 2U && w_fsm_zera_end_)
    {
      next_grav_tem_dados = 0U;
      next_ultimo_end_gravado = 0U;
    }
    else if (w_fsm_escreve_ram_)
    {
      next_grav_tem_dados = 1U;
      next_ultimo_end_gravado = r_endereco_ram_;
    }

    // Step Learning Mode (Modo 1) anti-pop octave/sharp latch
    uint8_t next_oitava_apre = r_oitava_apre_;
    uint8_t next_sustenido_apre = r_sustenido_apre_;
    if (w_fsm_modo_ativo_ == 1U)
    {
      if (!w_tem_nota_)
      {
        next_oitava_apre =
            (w_nota_esperada_ != 0U) ? w_oitava_esperada_ : r_oitava_livre_;
        next_sustenido_apre =
            (w_nota_esperada_ != 0U) ? w_sustenido_esperado_ : old_db_sustenido;
      }
    }
    else
    {
      next_oitava_apre = r_oitava_livre_;
      next_sustenido_apre = old_db_sustenido;
    }

    // Step LED PWM intensity & counter
    uint8_t next_estado_intensidade = r_estado_intensidade_;
    if (pulse_intensidade && !old_db_modo)
    {
      next_estado_intensidade =
          (r_estado_intensidade_ == 4U) ? 0U : (r_estado_intensidade_ + 1U);
    }
    uint16_t next_pwm_counter = (r_pwm_counter_ + 1U) & 0xFFFFU;

    // Step Demo Mode (Modo 3) timer
    uint32_t next_cont_demo = r_cont_demo_ciclos_;
    uint16_t next_tick_demo = r_tick_demo_;
    uint8_t next_pulso_bpm = r_pulso_bpm_;
    uint8_t next_nota_ativa_bpm = r_nota_ativa_bpm_;
    uint8_t next_aguarda_rom_demo = r_aguarda_rom_demo_;

    uint16_t s_dur_efetiva = (w_duracao_rom_ == 0U) ? 1U : w_duracao_rom_;
    uint16_t s_pausa_efetiva = (w_pausa_rom_ == 0U) ? 1U : w_pausa_rom_;
    uint16_t s_total_ticks_demo = s_dur_efetiva + s_pausa_efetiva;

    if (w_fsm_modo_ativo_ == 3U)
    {
      next_aguarda_rom_demo = (w_fsm_zera_end_ || w_fsm_conta_end_) ? 1U : 0U;
      if (w_fsm_zera_end_ || w_fsm_conta_end_ || r_aguarda_rom_demo_ ||
          r_pulso_bpm_)
      {
        next_cont_demo = 0U;
        next_tick_demo = 0U;
        next_pulso_bpm = 0U;
        next_nota_ativa_bpm = 0U;
      }
      else if (w_nota_midi_rom_ == 0U)
      {
        next_cont_demo = 0U;
        next_tick_demo = 0U;
        next_pulso_bpm = 1U;
        next_nota_ativa_bpm = 0U;
      }
      else
      {
        if (r_cont_demo_ciclos_ >= (param_ciclos_tick_8ms - 1U))
        {
          next_cont_demo = 0U;
          if (r_tick_demo_ >= (s_total_ticks_demo - 1U))
          {
            next_tick_demo = 0U;
            next_pulso_bpm = 1U;
            next_nota_ativa_bpm = 0U;
          }
          else
          {
            next_tick_demo = (r_tick_demo_ + 1U) & 0x1FFU;
            next_pulso_bpm = 0U;
            next_nota_ativa_bpm =
                ((r_tick_demo_ + 1U) < s_dur_efetiva) ? 1U : 0U;
          }
        }
        else
        {
          next_cont_demo = r_cont_demo_ciclos_ + 1U;
          next_pulso_bpm = 0U;
          next_nota_ativa_bpm = (r_tick_demo_ < s_dur_efetiva) ? 1U : 0U;
        }
      }
    }
    else
    {
      next_cont_demo = 0U;
      next_tick_demo = 0U;
      next_pulso_bpm = 0U;
      next_nota_ativa_bpm = 0U;
      next_aguarda_rom_demo = 0U;
    }

    // Step gerenciador_midi_tx & tx_serial_8N1
    uint8_t tx_partida = (r_tx_mgr_estado_ == 1U) ? 1U : 0U;
    uint8_t tx_dados_byte = 0U;
    switch (r_tx_byte_idx_)
    {
    case 0:
      tx_dados_byte = r_tx_byte0_;
      break;
    case 1:
      tx_dados_byte = r_tx_byte1_;
      break;
    case 2:
      tx_dados_byte = r_tx_byte2_;
      break;
    default:
      tx_dados_byte = 0U;
      break;
    }

    // tx_serial_8N1 combinational signals
    // state codes: 0=kIdle, 1=kPreparacao, 3=kEspera, 7=kTransmissao, 15=kFinalTx
    uint8_t s_carrega = (r_uart_uc_estado_ == 1U) ? 1U : 0U;
    uint8_t s_zera = (r_uart_uc_estado_ == 1U) ? 1U : 0U;
    uint8_t s_desloca = (r_uart_uc_estado_ == 7U) ? 1U : 0U;
    uint8_t s_conta = (r_uart_uc_estado_ == 7U) ? 1U : 0U;
    uint8_t tx_pronto = (r_uart_uc_estado_ == 15U) ? 1U : 0U;

    uint16_t baud_mfim =
        (param_clock_div_uart > 0U) ? ((param_clock_div_uart - 1U) & 0x1FFU) : 0U;
    uint8_t s_tick = (r_uart_baud_cnt_ == baud_mfim) ? 1U : 0U;
    uint8_t s_fim = (r_uart_bit_cnt_ == 11U) ? 1U : 0U;

    uint8_t next_uart_uc_estado = r_uart_uc_estado_;
    switch (r_uart_uc_estado_)
    {
    case 0U: // kIdle
      next_uart_uc_estado = tx_partida ? 1U : 0U;
      break;
    case 1U: // kPreparacao
      next_uart_uc_estado = 3U;
      break;
    case 3U: // kEspera
      next_uart_uc_estado = s_tick ? 7U : (s_fim ? 15U : 3U);
      break;
    case 7U: // kTransmissao
      next_uart_uc_estado = s_fim ? 15U : 3U;
      break;
    case 15U: // kFinalTx
      next_uart_uc_estado = 0U;
      break;
    default:
      next_uart_uc_estado = 0U;
      break;
    }

    uint16_t next_uart_shift_reg = r_uart_shift_reg_;
    if (s_carrega)
    {
      next_uart_shift_reg =
          (1U << 10) | (static_cast<uint16_t>(tx_dados_byte) << 2) | 0x01U;
    }
    else if (s_desloca)
    {
      next_uart_shift_reg = (1U << 10) | (r_uart_shift_reg_ >> 1);
    }

    uint8_t next_uart_bit_cnt = r_uart_bit_cnt_;
    if (s_zera)
    {
      next_uart_bit_cnt = 0U;
    }
    else if (s_conta)
    {
      next_uart_bit_cnt =
          (r_uart_bit_cnt_ == 11U) ? 0U : ((r_uart_bit_cnt_ + 1U) & 0xFU);
    }

    uint16_t next_uart_baud_cnt = r_uart_baud_cnt_;
    if (s_zera)
    {
      next_uart_baud_cnt = 0U;
    }
    else
    {
      next_uart_baud_cnt =
          (r_uart_baud_cnt_ == baud_mfim) ? 0U : ((r_uart_baud_cnt_ + 1U) & 0x1FFU);
    }

    // gerenciador_midi_tx next state
    uint8_t next_tx_mgr_estado = r_tx_mgr_estado_;
    uint8_t next_tx_nota_tocando = r_tx_nota_tocando_;
    uint8_t next_tx_byte0 = r_tx_byte0_;
    uint8_t next_tx_byte1 = r_tx_byte1_;
    uint8_t next_tx_byte2 = r_tx_byte2_;
    uint8_t next_tx_byte_idx = r_tx_byte_idx_;

    switch (r_tx_mgr_estado_)
    {
    case 0U: // kIdle
      if (w_nota_midi_desejada_ != r_tx_nota_tocando_)
      {
        next_tx_byte_idx = 0U;
        next_tx_mgr_estado = 1U; // kSendByte
        if (r_tx_nota_tocando_ != 0U)
        {
          next_tx_byte0 = 0x80U;
          next_tx_byte1 = r_tx_nota_tocando_ & 0x7FU;
          next_tx_byte2 = 0x00U;
          next_tx_nota_tocando = 0U;
        }
        else
        {
          next_tx_byte0 = 0x90U;
          next_tx_byte1 = w_nota_midi_desejada_ & 0x7FU;
          next_tx_byte2 = w_velocity_final_ & 0x7FU;
          next_tx_nota_tocando = w_nota_midi_desejada_ & 0x7FU;
        }
      }
      break;
    case 1U: // kSendByte
      next_tx_mgr_estado = 2U; // kWaitByte
      break;
    case 2U: // kWaitByte
      if (tx_pronto)
      {
        if (r_tx_byte_idx_ == 2U)
        {
          next_tx_byte_idx = 0U;
          next_tx_mgr_estado = 0U;
        }
        else
        {
          next_tx_byte_idx = (r_tx_byte_idx_ + 1U) & 0x3U;
          next_tx_mgr_estado = 1U;
        }
      }
      break;
    default:
      next_tx_mgr_estado = 0U;
      break;
    }

    // Step Metronome & Servo
    uint8_t metro_habilita = (w_fsm_modo_ativo_ == 1U) ? 1U : 0U;
    uint8_t w_fim_passo =
        (r_metro_cnt_tempo_ >= (w_t_passo_metronomo_ - 1U)) ? 1U : 0U;
    uint8_t w_fim_curso_min = (r_metro_posicao_ == 0U) ? 1U : 0U;
    uint8_t w_fim_curso_max = (r_metro_posicao_ == 7U) ? 1U : 0U;

    uint8_t w_zera_tempo = 0U;
    uint8_t w_inc_pos = 0U;
    uint8_t w_dec_pos = 0U;
    uint8_t w_pos_repouso = 0U;
    uint8_t next_metro_uc_state = r_metro_uc_state_;

    switch (r_metro_uc_state_)
    {
    case 0U: // kIdle
      w_zera_tempo = 1U;
      w_pos_repouso = 1U;
      if (metro_habilita)
        next_metro_uc_state = 1U;
      break;
    case 1U: // kMoveDir
      if (!metro_habilita)
      {
        next_metro_uc_state = 0U;
      }
      else if (w_fim_passo)
      {
        w_zera_tempo = 1U;
        if (w_fim_curso_max)
        {
          w_dec_pos = 1U;
          next_metro_uc_state = 2U;
        }
        else
        {
          w_inc_pos = 1U;
        }
      }
      break;
    case 2U: // kMoveEsq
      if (!metro_habilita)
      {
        next_metro_uc_state = 0U;
      }
      else if (w_fim_passo)
      {
        w_zera_tempo = 1U;
        if (w_fim_curso_min)
        {
          w_inc_pos = 1U;
          next_metro_uc_state = 1U;
        }
        else
        {
          w_dec_pos = 1U;
        }
      }
      break;
    default:
      next_metro_uc_state = 0U;
      break;
    }

    uint32_t next_metro_cnt_tempo =
        w_zera_tempo ? 0U : (r_metro_cnt_tempo_ + 1U);
    uint8_t next_metro_posicao = r_metro_posicao_;
    if (w_pos_repouso)
      next_metro_posicao = 3U;
    else if (w_inc_pos)
      next_metro_posicao = (r_metro_posicao_ + 1U) & 0x7U;
    else if (w_dec_pos)
      next_metro_posicao = (r_metro_posicao_ - 1U) & 0x7U;

    uint32_t conf_periodo = param_clock_freq / 50U;
    static const uint32_t kLarguras[8] = {66667U, 69048U, 71429U, 73810U,
                                          76190U, 78571U, 80952U, 83333U};
    uint32_t next_servo_largura = r_servo_largura_pwm_;
    uint32_t next_servo_cnt = r_servo_cnt_;
    if (r_servo_cnt_ == conf_periodo - 1U)
    {
      next_servo_cnt = 0U;
      next_servo_largura = kLarguras[r_metro_posicao_ & 0x7U];
    }
    else
    {
      next_servo_cnt = r_servo_cnt_ + 1U;
    }
    uint8_t next_servo_controle =
        (r_servo_cnt_ < r_servo_largura_pwm_) ? 1U : 0U;

    // Commit all non-blocking assignments
    r_rom_dout_ = next_rom_dout;
    r_ram_dout_ = next_ram_dout;
    r_endereco_ram_ = next_endereco_ram;
    r_uc_state_ = next_uc_state;
    r_modo_prev_ = next_modo_prev;
    r_combo_ativo_ = next_combo_ativo;
    r_estado_vol_ = next_estado_vol;
    r_timer_display_vol_ = next_timer_vol;
    r_sel_musica_ = next_sel_musica;
    r_oitava_livre_ = next_oitava_livre;
    r_botoes_ant_ = next_botoes_ant;
    r_nota_tocada_ = next_nota_tocada;
    r_cont_grav_ciclos_ = next_cont_grav;
    r_tem_nota_grav_prev_ = next_tem_nota_grav_prev;
    r_nota_grav_ = next_nota_grav;
    r_vel_grav_ = next_vel_grav;
    r_duracao_grav_ = next_duracao_grav;
    r_pausa_grav_ = next_pausa_grav;
    r_grav_tem_dados_ = next_grav_tem_dados;
    r_ultimo_end_gravado_ = next_ultimo_end_gravado;
    r_oitava_apre_ = next_oitava_apre;
    r_sustenido_apre_ = next_sustenido_apre;
    r_estado_intensidade_ = next_estado_intensidade;
    r_pwm_counter_ = next_pwm_counter;
    r_cont_demo_ciclos_ = next_cont_demo;
    r_tick_demo_ = next_tick_demo;
    r_pulso_bpm_ = next_pulso_bpm;
    r_nota_ativa_bpm_ = next_nota_ativa_bpm;
    r_aguarda_rom_demo_ = next_aguarda_rom_demo;
    r_tx_mgr_estado_ = next_tx_mgr_estado;
    r_tx_nota_tocando_ = next_tx_nota_tocando;
    r_tx_byte0_ = next_tx_byte0;
    r_tx_byte1_ = next_tx_byte1;
    r_tx_byte2_ = next_tx_byte2;
    r_tx_byte_idx_ = next_tx_byte_idx;
    r_uart_uc_estado_ = next_uart_uc_estado;
    r_uart_shift_reg_ = next_uart_shift_reg;
    r_uart_bit_cnt_ = next_uart_bit_cnt;
    r_uart_baud_cnt_ = next_uart_baud_cnt;
    r_metro_uc_state_ = next_metro_uc_state;
    r_metro_cnt_tempo_ = next_metro_cnt_tempo;
    r_metro_posicao_ = next_metro_posicao;
    r_servo_cnt_ = next_servo_cnt;
    r_servo_largura_pwm_ = next_servo_largura;
    r_servo_controle_ = next_servo_controle;
  }
};

#endif // SIM_VPIANO_TOP_H_
