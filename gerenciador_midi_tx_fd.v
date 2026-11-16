// Descricao: Fluxo de dados para transmissao MIDI de 3 bytes.
// Funcionamento: Armazena nota tocando e bytes do pacote MIDI, gerencia indice
// do byte em transmissao e instancia transmissor serial UART 8N1.

`timescale 1ns / 1ps
`default_nettype none

module gerenciador_midi_tx_fd #(
  parameter ClockDiv = 434
)(
  input  wire       clk,
  input  wire       arst,
  input  wire       carrega_pacote,
  input  wire       zera_idx,
  input  wire       conta_idx,
  input  wire       tx_partida,
  input  wire [6:0] nota_desejada,
  input  wire [6:0] velocity_desejado,
  output wire       tem_mudanca_nota,
  output wire       tx_pronto,
  output wire       fim_bytes,
  output wire       saida_serial
);

  reg [6:0] nota_tocando_reg;
  reg [7:0] byte0_reg;
  reg [7:0] byte1_reg;
  reg [7:0] byte2_reg;
  reg [1:0] byte_idx_reg;

  reg [7:0] tx_dados_byte;

  assign tem_mudanca_nota = (nota_desejada != nota_tocando_reg);
  assign fim_bytes        = (byte_idx_reg == 2'd2);

  always @* begin
    case (byte_idx_reg)
      2'd0:    tx_dados_byte = byte0_reg;
      2'd1:    tx_dados_byte = byte1_reg;
      2'd2:    tx_dados_byte = byte2_reg;
      default: tx_dados_byte = 8'h00;
    endcase
  end

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      nota_tocando_reg <= 7'd0;
      byte0_reg        <= 8'd0;
      byte1_reg        <= 8'd0;
      byte2_reg        <= 8'd0;
      byte_idx_reg     <= 2'd0;
    end else begin
      if (carrega_pacote) begin
        if (nota_tocando_reg != 7'd0) begin
          // Note Off para nota anterior
          byte0_reg        <= 8'h80;
          byte1_reg        <= {1'b0, nota_tocando_reg};
          byte2_reg        <= 8'h00;
          nota_tocando_reg <= 7'd0;
        end else begin
          // Note On para nova nota
          byte0_reg        <= 8'h90;
          byte1_reg        <= {1'b0, nota_desejada};
          byte2_reg        <= {1'b0, velocity_desejado};
          nota_tocando_reg <= nota_desejada;
        end
      end

      if (zera_idx) begin
        byte_idx_reg <= 2'd0;
      end else if (conta_idx) begin
        byte_idx_reg <= byte_idx_reg + 2'd1;
      end
    end
  end

  tx_serial_8N1 #(
    .ClockDiv(ClockDiv)
  ) tx_serial_8N1_inst (
    .clk            (clk),
    .arst           (arst),
    .partida        (tx_partida),
    .dados_byte     (tx_dados_byte),
    .saida_serial   (saida_serial),
    .pronto         (tx_pronto),
    .db_partida     (),
    .db_saida_serial(),
    .db_estado      ()
  );

endmodule

`default_nettype wire
