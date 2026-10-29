`timescale 1ns / 1ps
`default_nettype none

// Descricao: Gera um sinal PWM com base na configuracao de duty cycle (0 a 15).
// Frequencia do PWM baseada num clock de 50MHz: 50M / 65536 = ~762Hz
module gerador_pwm (
    input  wire       clock,
    input  wire       reset,
    input  wire [3:0] duty_cycle,
    output wire       pwm_out
);

    reg [15:0] counter_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            counter_reg <= 16'd0;
        end else begin
            counter_reg <= counter_reg + 16'd1;
        end
    end

    assign pwm_out = (duty_cycle == 4'h0) ? 1'b0 :
                     (duty_cycle == 4'hF) ? 1'b1 :
                     (counter_reg < {duty_cycle, 12'd0});

endmodule

`default_nettype wire
