// Descrição: Simula a dinamica de um piano com envelope ADSR e sintese sonora.
// Funcionamento: Combina oscilador de frequencia configuravel com modulador
// de envelope ADSR de 4 estados e atenuador de ganho por PWM de alta frequencia.

`timescale 1ns / 1ps
`default_nettype none

module gerador_audio (
  input  wire        clk,
  input  wire        arst,
  input  wire [17:0] fim_contagem,
  input  wire        habilitar,
  input  wire [3:0]  nivel_volume,
  output wire        buzzer
);

  // 1. Geracao da onda base
  reg [17:0]  contador_freq_reg;
  reg         onda_quadrada_reg;
  wire [17:0] threshold = (fim_contagem >> 4'd4);

  // 2. Envelope ADSR
  reg [9:0]  envelope_val_reg;
  reg [19:0] timer_envelope_reg;
  reg        habilitar_antigo_reg;

  localparam [1:0]
    kIdle    = 2'd0,
    kAttack  = 2'd1,
    kDecay   = 2'd2,
    kRelease = 2'd3;

  reg [1:0] estado_adsr_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      contador_freq_reg <= 18'd0;
      onda_quadrada_reg <= 1'b0;
    end else if (habilitar || (envelope_val_reg > 10'd0)) begin
      if (contador_freq_reg >= fim_contagem) begin
        contador_freq_reg <= 18'd0;
      end else begin
        contador_freq_reg <= contador_freq_reg + 18'd1;
      end
      onda_quadrada_reg <= (contador_freq_reg < threshold);
    end else begin
      contador_freq_reg <= 18'd0;
      onda_quadrada_reg <= 1'b0;
    end
  end

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      envelope_val_reg     <= 10'd0;
      timer_envelope_reg   <= 20'd0;
      estado_adsr_reg      <= kIdle;
      habilitar_antigo_reg <= 1'b0;
    end else begin
      habilitar_antigo_reg <= habilitar;

      case (estado_adsr_reg)
        kIdle: begin
          if (habilitar && !habilitar_antigo_reg) begin
            estado_adsr_reg    <= kAttack;
            timer_envelope_reg <= 20'd0;
          end else begin
            envelope_val_reg <= 10'd0;
          end
        end

        kAttack: begin
          if (timer_envelope_reg >= 20'd100) begin
            timer_envelope_reg <= 20'd0;
            if (envelope_val_reg >= 10'd1000) begin
              estado_adsr_reg <= kDecay;
            end else begin
              envelope_val_reg <= envelope_val_reg + 10'd20;
            end
          end else begin
            timer_envelope_reg <= timer_envelope_reg + 20'd1;
          end
        end

        kDecay: begin
          if (!habilitar) begin
            estado_adsr_reg    <= kRelease;
            timer_envelope_reg <= 20'd0;
          end else if (timer_envelope_reg >= 20'd150_000) begin
            timer_envelope_reg <= 20'd0;
            if (envelope_val_reg > 10'd150) begin
              envelope_val_reg <= envelope_val_reg - 10'd1;
            end else begin
              envelope_val_reg <= 10'd0;
              estado_adsr_reg  <= kIdle;
            end
          end else begin
            timer_envelope_reg <= timer_envelope_reg + 20'd1;
          end
        end

        kRelease: begin
          if (habilitar) begin
            estado_adsr_reg    <= kAttack;
            timer_envelope_reg <= 20'd0;
          end else if (timer_envelope_reg >= 20'd20_000) begin
            timer_envelope_reg <= 20'd0;
            if (envelope_val_reg > 10'd150) begin
              envelope_val_reg <= envelope_val_reg - 10'd5;
            end else begin
              envelope_val_reg <= 10'd0;
              estado_adsr_reg  <= kIdle;
            end
          end else begin
            timer_envelope_reg <= timer_envelope_reg + 20'd1;
          end
        end

        default: begin
          estado_adsr_reg    <= kIdle;
          timer_envelope_reg <= 20'd0;
          envelope_val_reg   <= 10'd0;
        end
      endcase
    end
  end

  // 3. Ganho e PWM
  wire [13:0] calc_ganho = envelope_val_reg * nivel_volume;
  wire [9:0]  volume_final = calc_ganho[13:4];
  reg  [9:0]  contador_pwm_hf_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      contador_pwm_hf_reg <= 10'd0;
    end else if (contador_pwm_hf_reg >= 10'd1000) begin
      contador_pwm_hf_reg <= 10'd0;
    end else begin
      contador_pwm_hf_reg <= contador_pwm_hf_reg + 10'd1;
    end
  end

  assign buzzer = onda_quadrada_reg & (contador_pwm_hf_reg < volume_final);

endmodule

`default_nettype wire
