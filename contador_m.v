// Descrição: Contador modulo M parametrizavel com saidas de fim e meio periodo.
// Funcionamento: Contador sincrono sature/wrap de 0 a M-1 que gera pulsos
// de strobe no meio da contagem e no overflow final, com clear sincrono sclr.

`timescale 1ns / 1ps
`default_nettype none

module contador_m #(
  parameter Modulo = 50,
  parameter Width  = 6
)(
  input  wire             clk,
  input  wire             arst,
  input  wire             sclr,
  input  wire             conta,
  output reg  [Width-1:0] q,
  output wire             fim,
  output wire             meio
);

  localparam [Width-1:0] MVal  = Modulo[Width-1:0];
  localparam [Width-1:0] MFim  = (Modulo > 0) ? (Modulo - 1) : 0;
  localparam [Width-1:0] MMeio = (Modulo > 1) ? ((Modulo / 2) - 1) : 0;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      q <= {Width{1'b0}};
    end else if (sclr) begin
      q <= {Width{1'b0}};
    end else if (conta) begin
      if (q == MFim) begin
        q <= {Width{1'b0}};
      end else begin
        q <= q + {{(Width-1){1'b0}}, 1'b1};
      end
    end
  end

  assign fim  = (q == MFim);
  assign meio = (q == MMeio);

endmodule

`default_nettype wire
