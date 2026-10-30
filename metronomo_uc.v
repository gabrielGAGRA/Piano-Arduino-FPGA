// Descricao: FSM do metronomo mecanico para controle de oscilacao angular.
// Funcionamento: Transita entre kIdle, kMoveDir e kMoveEsq gerando pulsos de beat
// nos limites angulares do braco oscilante.

`timescale 1ns / 1ps
`default_nettype none

module metronomo_uc (
  input  wire clk,
  input  wire arst,
  input  wire habilita,
  input  wire fim_passo,
  input  wire fim_curso_min,
  input  wire fim_curso_max,
  output reg  zera_tempo,
  output reg  incrementa_pos,
  output reg  decrementa_pos,
  output reg  pos_repouso,
  output reg  pulso_beat
);

  localparam [1:0]
    kIdle    = 2'd0,
    kMoveDir = 2'd1,
    kMoveEsq = 2'd2;

  reg [1:0] state_reg;
  reg [1:0] state_next;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      state_reg <= kIdle;
    end else begin
      state_reg <= state_next;
    end
  end

  always @* begin
    state_next     = state_reg;
    zera_tempo     = 1'b0;
    incrementa_pos = 1'b0;
    decrementa_pos = 1'b0;
    pos_repouso    = 1'b0;
    pulso_beat     = 1'b0;

    case (state_reg)
      // Posicao central de repouso
      kIdle: begin
        zera_tempo  = 1'b1;
        pos_repouso = 1'b1;
        if (habilita) begin
          state_next = kMoveDir;
        end
      end

      // Movimento para a direita
      kMoveDir: begin
        if (!habilita) begin
          state_next = kIdle;
        end else if (fim_passo) begin
          zera_tempo = 1'b1;
          if (fim_curso_max) begin
            pulso_beat     = 1'b1;
            decrementa_pos = 1'b1;
            state_next     = kMoveEsq;
          end else begin
            incrementa_pos = 1'b1;
          end
        end
      end

      // Movimento para a esquerda
      kMoveEsq: begin
        if (!habilita) begin
          state_next = kIdle;
        end else if (fim_passo) begin
          zera_tempo = 1'b1;
          if (fim_curso_min) begin
            pulso_beat     = 1'b1;
            incrementa_pos = 1'b1;
            state_next     = kMoveDir;
          end else begin
            decrementa_pos = 1'b1;
          end
        end
      end

      default: begin
        state_next = 2'bxx;
      end
    endcase
  end

endmodule

`default_nettype wire
