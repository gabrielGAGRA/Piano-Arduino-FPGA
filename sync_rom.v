// Descricao: Memoria ROM sincrona inferida em M10K com suporte a hex ou binario.
// Funcionamento: Carrega arquivo de inicializacao via $readmemh ou $readmemb durante elaboracao.

`timescale 1ns / 1ps
`default_nettype none

module sync_rom #(
  parameter DataWidth = 30,
  parameter AddrWidth = 14,
  parameter Depth     = (1 << AddrWidth),
  parameter InitFile  = "music/partituras.hex",
  parameter HexMode   = 1
)(
  input  wire                 clk,
  input  wire [AddrWidth-1:0] address,
  output reg  [DataWidth-1:0] data_out
);

  localparam RomWordWidth = HexMode ? (((DataWidth + 3) / 4) * 4) : DataWidth;
  (* ramstyle = "M10K" *) reg [RomWordWidth-1:0] rom [0:Depth-1];

  integer i;
  initial begin
    for (i = 0; (i < Depth) && (i < 32'd4050); i = i + 1) begin
      rom[i] = {RomWordWidth{1'b0}};
    end
    if (HexMode) begin
      $readmemh(InitFile, rom);
    end else begin
      $readmemb(InitFile, rom);
    end
  end

  always @(posedge clk) begin
    data_out <= rom[address][DataWidth-1:0];
  end

endmodule

`default_nettype wire
