`timescale 1ns / 1ps
`default_nettype none

// Descricao: ROM Sincrona parametrizavel que le de um arquivo de texto.
module sync_rom #(
    parameter DATA_WIDTH = 4,
    parameter ADDR_WIDTH = 8,
    parameter INIT_FILE = "Au_Clair_de_La_Lune.txt"
)(
    input  wire                  clock,
    input  wire [ADDR_WIDTH-1:0] address,
    output reg  [DATA_WIDTH-1:0] data_out
);

    (* ramstyle = "M10K" *) reg [DATA_WIDTH-1:0] rom [0:(2**ADDR_WIDTH)-1];

    integer i;
    initial begin
        for (i = 0; i < (2**ADDR_WIDTH); i = i + 1) begin
            rom[i] = {DATA_WIDTH{1'b0}};
        end
        $readmemb(INIT_FILE, rom);
    end

    always @(posedge clock) begin
        data_out <= rom[address];
    end

endmodule

`default_nettype wire