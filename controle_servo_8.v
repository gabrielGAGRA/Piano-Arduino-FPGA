// Descricao: Controlador de largura de pulso para servomotor com 8 posicoes.
// Funcionamento: Gera sinal periodico de 20 ms via modulacao PWM de 50 Hz com
// 8 larguras de pulso calibradas para varredura angular restrita de 30 graus (~90 graus no centro).
// A largura e atualizada no rollover do contador para prevenir glitches durante operacao.

`timescale 1ns / 1ps
`default_nettype none

module controle_servo_8 #(
  parameter ConfPeriodo = 1_000_000,
  parameter Largura000  = 66_667,
  parameter Largura001  = 69_048,
  parameter Largura010  = 71_429,
  parameter Largura011  = 73_810,
  parameter Largura100  = 76_190,
  parameter Largura101  = 78_571,
  parameter Largura110  = 80_952,
  parameter Largura111  = 83_333
)(
  input  wire       clk,
  input  wire       arst,
  input  wire [2:0] posicao,
  output wire       controle
);

  reg [31:0] contador_reg;
  reg [31:0] largura_pwm_reg;
  reg        controle_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      largura_pwm_reg <= Largura011;
    end else if (contador_reg == ConfPeriodo - 32'd1) begin
      case (posicao)
        3'b000:  largura_pwm_reg <= Largura000;
        3'b001:  largura_pwm_reg <= Largura001;
        3'b010:  largura_pwm_reg <= Largura010;
        3'b011:  largura_pwm_reg <= Largura011;
        3'b100:  largura_pwm_reg <= Largura100;
        3'b101:  largura_pwm_reg <= Largura101;
        3'b110:  largura_pwm_reg <= Largura110;
        3'b111:  largura_pwm_reg <= Largura111;
        default: largura_pwm_reg <= Largura011;
      endcase
    end
  end

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      contador_reg <= 32'd0;
      controle_reg <= 1'b0;
    end else begin
      if (contador_reg == ConfPeriodo - 32'd1) begin
        contador_reg <= 32'd0;
      end else begin
        contador_reg <= contador_reg + 32'd1;
      end
      controle_reg <= (contador_reg < largura_pwm_reg);
    end
  end

  assign controle = controle_reg;

endmodule

`default_nettype wire
