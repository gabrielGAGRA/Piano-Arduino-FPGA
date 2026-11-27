// Descricao: FSM do metronomo mecanico para controle de batida nos extremos.
// Funcionamento: Transita entre kIdle, kMoveDir e kMoveEsq, saltando diretamente
// entre os extremos (0 e 7) a cada beat e gerando pulso_beat registrado.

`timescale 1ns / 1ps
`default_nettype none

module metronomo_uc (
  input  wire clk,
  input  wire arst,
  input  wire habilita,
  input  wire fim_beat,
  output reg  zera_tempo,
  output reg  set_pos_min,
  output reg  set_pos_max,
  output reg  pos_repouso,
  output reg  pulso_beat
);

  localparam [1:0]
    kIdle    = 2'd0,
    kMoveDir = 2'd1,
    kMoveEsq = 2'd2;

  reg [1:0] state_reg;
  reg [1:0] state_next;
  reg       pulso_beat_next;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      state_reg  <= kIdle;
      pulso_beat <= 1'b0;
    end else begin
      state_reg  <= state_next;
      pulso_beat <= pulso_beat_next;
    end
  end

  always @* begin
    state_next      = state_reg;
    zera_tempo      = 1'b0;
    set_pos_min     = 1'b0;
    set_pos_max     = 1'b0;
    pos_repouso     = 1'b0;
    pulso_beat_next = 1'b0;

    case (state_reg)
      // Posicao central de repouso
      kIdle: begin
        zera_tempo  = 1'b1;
        pos_repouso = 1'b1;
        if (habilita) begin
          state_next = kMoveDir;
        end
      end

      // Aguarda 1 beat e salta para o extremo direito (posicao 7)
      kMoveDir: begin
        if (!habilita) begin
          state_next = kIdle;
        end else if (fim_beat) begin
          zera_tempo      = 1'b1;
          set_pos_max     = 1'b1;
          pulso_beat_next = 1'b1;
          state_next      = kMoveEsq;
        end
      end

      // Aguarda 1 beat e salta para o extremo esquerdo (posicao 0)
      kMoveEsq: begin
        if (!habilita) begin
          state_next = kIdle;
        end else if (fim_beat) begin
          zera_tempo      = 1'b1;
          set_pos_min     = 1'b1;
          pulso_beat_next = 1'b1;
          state_next      = kMoveDir;
        end
      end

      default: begin
        state_next = 2'bxx;
      end
    endcase
  end

endmodule

`default_nettype wire
