// Descricao: Datapath do metronomo mecanico com contador de beat e registrador angular.
// Funcionamento: Conta 7 passos de t_passo para completar 1 beat e comuta a posicao
// do servo diretamente entre os extremos (3'd0 e 3'd7) ou centro de repouso (3'd3).

`timescale 1ns / 1ps
`default_nettype none

module metronomo_fd (
  input  wire        clk,
  input  wire        arst,
  input  wire [31:0] t_passo,
  input  wire        zera_tempo,
  input  wire        set_pos_min,
  input  wire        set_pos_max,
  input  wire        pos_repouso,
  output wire        fim_beat,
  output wire [2:0]  posicao_servo
);

  reg [31:0] contador_tempo_reg;
  reg [2:0]  contador_passos_reg;
  reg [2:0]  posicao_reg;

  wire fim_passo;

  assign fim_passo = (contador_tempo_reg >= t_passo - 32'd1);
  assign fim_beat  = fim_passo && (contador_passos_reg == 3'd6);

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      contador_tempo_reg  <= 32'd0;
      contador_passos_reg <= 3'd0;
    end else if (zera_tempo) begin
      contador_tempo_reg  <= 32'd0;
      contador_passos_reg <= 3'd0;
    end else if (fim_passo) begin
      contador_tempo_reg <= 32'd0;
      if (contador_passos_reg == 3'd6) begin
        contador_passos_reg <= 3'd0;
      end else begin
        contador_passos_reg <= contador_passos_reg + 3'd1;
      end
    end else begin
      contador_tempo_reg <= contador_tempo_reg + 32'd1;
    end
  end

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      posicao_reg <= 3'd3;
    end else if (pos_repouso) begin
      posicao_reg <= 3'd3;
    end else if (set_pos_max) begin
      posicao_reg <= 3'd7;
    end else if (set_pos_min) begin
      posicao_reg <= 3'd0;
    end
  end

  assign posicao_servo = posicao_reg;

endmodule

`default_nettype wire
