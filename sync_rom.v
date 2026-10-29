// Descrição: Memoria ROM sincrona inicializavel por arquivo binario.
// Funcionamento: Infere M10K ROM sincrona populada com partituras via
// diretiva $readmemb durante elaboracao e simulacao.

`timescale 1ns / 1ps
`default_nettype none

module sync_rom #(
  parameter DataWidth = 30,
  parameter AddrWidth = 10,
  parameter InitFile  = "musica0.bin"
)(
  input  wire                 clk,
  input  wire [AddrWidth-1:0] address,
  output reg  [DataWidth-1:0] data_out
);

  (* ramstyle = "M10K" *) reg [DataWidth-1:0] rom [0:(2**AddrWidth)-1];

  integer i;
  initial begin
    for (i = 0; i < (2**AddrWidth); i = i + 1) begin
      rom[i] = {DataWidth{1'b0}};
    end
    $readmemb(InitFile, rom);
  end

  always @(posedge clk) begin
    data_out <= rom[address];
  end

endmodule

`default_nettype wire
