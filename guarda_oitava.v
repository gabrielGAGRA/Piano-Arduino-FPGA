`timescale 1ns / 1ps
`default_nettype none

// Modulo: guarda_oitava
// Descricao: Controla oitava atual, incrementando ou decrementando.
module guarda_oitava (
    input  wire       clock,
    input  wire       reset,
    input  wire       btn_up_pulse,
    input  wire       btn_down_pulse,
    output reg  [2:0] oitava_atual
);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            oitava_atual <= 3'd4;
        end else begin
            if (btn_up_pulse) begin
                if (oitava_atual < 3'd7)
                    oitava_atual <= oitava_atual + 3'd1;
            end else if (btn_down_pulse) begin
                if (oitava_atual > 3'd1)
                    oitava_atual <= oitava_atual - 3'd1;
            end
        end
    end

endmodule

`default_nettype wire
