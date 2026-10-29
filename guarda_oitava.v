// Descrição: Registrador de oitava atual com controle de incremento e decremento.
// Funcionamento: Mantem a oitava configurada entre 1 e 7, atualizando
// mediante pulsos de borda dos botoes de subir e descer oitava.

`timescale 1ns / 1ps
`default_nettype none

module guarda_oitava (
  input  wire       clk,
  input  wire       arst,
  input  wire       btn_up_pulse,
  input  wire       btn_down_pulse,
  output reg  [2:0] oitava_atual
);

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      oitava_atual <= 3'd4;
    end else begin
      if (btn_up_pulse) begin
        if (oitava_atual < 3'd7) begin
          oitava_atual <= oitava_atual + 3'd1;
        end
      end else if (btn_down_pulse) begin
        if (oitava_atual > 3'd1) begin
          oitava_atual <= oitava_atual - 3'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
