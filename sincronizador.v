// Descrição: Sincronizador de sinal assincrono com 2 estagios de flip-flops.
// Funcionamento: Captura um sinal assincrono em dois registradores em cascata
// para mitigar metaestabilidade na transicao para o dominio de clock.

`timescale 1ns / 1ps
`default_nettype none

module sincronizador #(
  parameter Width     = 1,
  parameter InitValue = 1'b0
)(
  input  wire             clk,
  input  wire             arst,
  input  wire [Width-1:0] async_in,
  output wire [Width-1:0] sync_out
);

  reg [Width-1:0] sync_stage1_reg;
  reg [Width-1:0] sync_stage2_reg;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      sync_stage1_reg <= {Width{InitValue}};
      sync_stage2_reg <= {Width{InitValue}};
    end else begin
      sync_stage1_reg <= async_in;
      sync_stage2_reg <= sync_stage1_reg;
    end
  end

  assign sync_out = sync_stage2_reg;

endmodule

`default_nettype wire
