// Descrição: Indicador de erro de oitava em LEDs dedicados.
// Funcionamento: Compara a oitava certa da partitura com a oitava atual
// configurada pelo usuario e acende o LED de subir ou descer.

`timescale 1ns / 1ps
`default_nettype none

module led_oitava (
  input  wire [2:0] oitava_certa,
  input  wire [2:0] oitava_atual,
  output reg        led_up,
  output reg        led_down
);

  always @* begin
    led_up   = 1'b0;
    led_down = 1'b0;

    if (oitava_certa > oitava_atual) begin
      led_up = 1'b1;
    end else if (oitava_certa < oitava_atual) begin
      led_down = 1'b1;
    end
  end

endmodule

`default_nettype wire
