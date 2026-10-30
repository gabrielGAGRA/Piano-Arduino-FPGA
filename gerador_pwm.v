// Descricao: Modulador por largura de pulso (PWM) de 4 bits para LEDs.
// Funcionamento: Modula duty cycle de 0 a 15 comparando com contador de 16 bits
// a ~762 Hz (50 MHz / 65536).

`timescale 1ns / 1ps
`default_nettype none

module gerador_pwm (
  input  wire       clk,
  input  wire       arst,
  input  wire [3:0] duty_cycle,
  output wire       pwm_out
);

  reg [15:0] counter_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      counter_reg <= 16'd0;
    end else begin
      counter_reg <= counter_reg + 16'd1;
    end
  end

  assign pwm_out = (duty_cycle == 4'h0) ? 1'b0 :
    ((duty_cycle == 4'hF) ? 1'b1 :
    (counter_reg < {duty_cycle, 12'd0}));

endmodule

`default_nettype wire
