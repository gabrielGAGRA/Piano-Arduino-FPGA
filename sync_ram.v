// Descricao: Memoria RAM sincrona com leitura sincrona para sintese em M10K.
// Funcionamento: Infere blocos de memoria M10K no Cyclone V mediante leitura
// e escrita sincronizadas na borda de subida de clock.

`timescale 1ns / 1ps
`default_nettype none

module sync_ram #(
  parameter DataWidth = 7,
  parameter AddrWidth = 10
)(
  input  wire                 clk,
  input  wire                 we,
  input  wire [AddrWidth-1:0] address,
  input  wire [DataWidth-1:0] data_in,
  output reg  [DataWidth-1:0] data_out
);

  (* ramstyle = "M10K" *) reg [DataWidth-1:0] ram [0:(2**AddrWidth)-1];

  always @(posedge clk) begin
    if (we) begin
      ram[address] <= data_in;
    end
    data_out <= ram[address];
  end

endmodule

`default_nettype wire
