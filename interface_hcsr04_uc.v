/*
 *  Descricao : Unidade de controle do circuito de interface com sensor
 *              ultrassonico de distancia HC-SR04 com suporte a timeout.
 */

`timescale 1ns / 1ps
`default_nettype none

module interface_hcsr04_uc (
  input  wire       clk,
  input  wire       arst,
  input  wire       medir,
  input  wire       echo,
  input  wire       fim_medida,
  input  wire       fim_timeout,
  output reg        zera,
  output reg        gera,
  output reg        registra,
  output reg        pronto,
  output reg        zera_timeout,
  output reg        conta_timeout,
  output reg        timeout_sel,
  output reg  [3:0] db_estado
);

  reg [2:0] estado_q;
  reg [2:0] estado_d;

  localparam [2:0] kInicial       = 3'b000;
  localparam [2:0] kPreparacao    = 3'b001;
  localparam [2:0] kEnviaTrigger  = 3'b010;
  localparam [2:0] kEsperaEcho    = 3'b011;
  localparam [2:0] kMedida        = 3'b100;
  localparam [2:0] kArmazenamento = 3'b101;
  localparam [2:0] kFinalMedida   = 3'b110;
  localparam [2:0] kTimeout       = 3'b111;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      estado_q <= kInicial;
    end else begin
      estado_q <= estado_d;
    end
  end

  always @* begin
    estado_d      = kInicial;
    zera          = 1'b0;
    gera          = 1'b0;
    registra      = 1'b0;
    pronto        = 1'b0;
    zera_timeout  = 1'b0;
    conta_timeout = 1'b0;
    timeout_sel   = 1'b0;
    db_estado     = 4'b1110;

    case (estado_q)
      kInicial: begin
        db_estado = 4'b0000;
        if (medir) begin
          estado_d = kPreparacao;
        end else begin
          estado_d = kInicial;
        end
      end

      kPreparacao: begin
        zera         = 1'b1;
        zera_timeout = 1'b1;
        db_estado    = 4'b0001;
        estado_d     = kEnviaTrigger;
      end

      kEnviaTrigger: begin
        gera          = 1'b1;
        conta_timeout = 1'b1;
        db_estado     = 4'b0010;
        estado_d      = kEsperaEcho;
      end

      kEsperaEcho: begin
        conta_timeout = 1'b1;
        db_estado     = 4'b0011;
        if (echo) begin
          estado_d = kMedida;
        end else if (fim_timeout) begin
          estado_d = kTimeout;
        end else begin
          estado_d = kEsperaEcho;
        end
      end

      kMedida: begin
        conta_timeout = 1'b1;
        db_estado     = 4'b0100;
        if (fim_medida) begin
          estado_d = kArmazenamento;
        end else if (fim_timeout) begin
          estado_d = kTimeout;
        end else begin
          estado_d = kMedida;
        end
      end

      kArmazenamento: begin
        registra    = 1'b1;
        timeout_sel = 1'b0;
        db_estado   = 4'b0101;
        estado_d    = kFinalMedida;
      end

      kTimeout: begin
        registra    = 1'b1;
        timeout_sel = 1'b1;
        db_estado   = 4'b1100;
        estado_d    = kFinalMedida;
      end

      kFinalMedida: begin
        pronto    = 1'b1;
        db_estado = 4'b1111;
        estado_d  = kInicial;
      end

      default: begin
        estado_d = 3'bxxx;
      end
    endcase
  end

endmodule

`default_nettype wire
