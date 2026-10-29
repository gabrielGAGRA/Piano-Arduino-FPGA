`timescale 1ns / 1ps
`default_nettype none

/* 
 *  Descricao : Circuito de controle para servomotor SG90 com 8 posicoes angulares
 *              distribuidas em uma amplitude de 30° (75° a 105° centralizado em ~90°)
 *              via modulacao PWM de 50 Hz.
 */

module controle_servo_8 #(
    parameter CONF_PERIODO = 1000000, // Periodo PWM (20ms a 50MHz)
    parameter LARGURA_000  = 66667,   // 1,333 ms (75,0°)
    parameter LARGURA_001  = 69048,   // 1,381 ms (79,3°)
    parameter LARGURA_010  = 71429,   // 1,429 ms (83,6°)
    parameter LARGURA_011  = 73810,   // 1,476 ms (87,9° - Centro / Repouso)
    parameter LARGURA_100  = 76190,   // 1,524 ms (92,1°)
    parameter LARGURA_101  = 78571,   // 1,571 ms (96,4°)
    parameter LARGURA_110  = 80952,   // 1,619 ms (100,7°)
    parameter LARGURA_111  = 83333    // 1,667 ms (105,0°)
) (
    input  wire       clock,
    input  wire       reset,
    input  wire [2:0] posicao,
    output wire       controle,
    output wire       db_reset,
    output wire [2:0] db_posicao,
    output wire       db_controle
);

    reg [31:0] contagem_q;
    reg [31:0] largura_pwm_q;
    reg        s_controle_q;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            largura_pwm_q <= LARGURA_011; // Repouso no centro
        end else if (contagem_q == CONF_PERIODO - 32'd1) begin
            case (posicao)
                3'b000:  largura_pwm_q <= LARGURA_000;
                3'b001:  largura_pwm_q <= LARGURA_001;
                3'b010:  largura_pwm_q <= LARGURA_010;
                3'b011:  largura_pwm_q <= LARGURA_011;
                3'b100:  largura_pwm_q <= LARGURA_100;
                3'b101:  largura_pwm_q <= LARGURA_101;
                3'b110:  largura_pwm_q <= LARGURA_110;
                3'b111:  largura_pwm_q <= LARGURA_111;
                default: largura_pwm_q <= LARGURA_011;
            endcase
        end
    end

    // Base de tempo periodica continua de 20 ms para o servomotor
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            contagem_q   <= 32'd0;
            s_controle_q <= 1'b0;
        end else begin
            if (contagem_q == CONF_PERIODO - 32'd1) begin
                contagem_q <= 32'd0;
            end else begin
                contagem_q <= contagem_q + 32'd1;
            end
            s_controle_q <= (contagem_q < largura_pwm_q);
        end
    end

    assign controle    = s_controle_q;
    assign db_reset    = reset;
    assign db_posicao  = posicao;
    assign db_controle = s_controle_q;

endmodule

`default_nettype wire
