// Descricao: Gerenciador de transmissao de pacotes MIDI de 3 bytes via UART.
// Funcionamento: Reconcilia nota tocando e nota desejada gerando pacotes Note On
// e Note Off transmitidos sequencialmente byte a byte por transmissor serial.

`timescale 1ns / 1ps
`default_nettype none

module gerenciador_midi_tx #(
  parameter ClockDiv = 434
)(
  input  wire       clk,
  input  wire       arst,
  input  wire [6:0] nota_desejada,
  input  wire [6:0] velocity_desejado,
  output wire       saida_serial,
  output wire       ocupado
);

  localparam [1:0]
    kIdle     = 2'b00,
    kSendByte = 2'b01,
    kWaitByte = 2'b10;

  reg [1:0] estado_reg;
  reg [1:0] estado_next;

  reg [6:0] nota_tocando_reg;
  reg [6:0] nota_tocando_next;

  reg [7:0] byte0_reg;
  reg [7:0] byte0_next;
  reg [7:0] byte1_reg;
  reg [7:0] byte1_next;
  reg [7:0] byte2_reg;
  reg [7:0] byte2_next;

  reg [1:0] byte_idx_reg;
  reg [1:0] byte_idx_next;

  reg  [7:0] tx_dados_byte;
  wire       tx_partida;
  wire       tx_pronto;

  assign tx_partida = (estado_reg == kSendByte);
  assign ocupado    = (estado_reg != kIdle) || (nota_desejada != nota_tocando_reg);

  always @* begin
    case (byte_idx_reg)
      2'd0:    tx_dados_byte = byte0_reg;
      2'd1:    tx_dados_byte = byte1_reg;
      2'd2:    tx_dados_byte = byte2_reg;
      default: tx_dados_byte = 8'h00;
    endcase
  end

  always @* begin
    estado_next       = estado_reg;
    nota_tocando_next = nota_tocando_reg;
    byte0_next        = byte0_reg;
    byte1_next        = byte1_reg;
    byte2_next        = byte2_reg;
    byte_idx_next     = byte_idx_reg;

    case (estado_reg)
      // Aguarda solicitacao de mudanca de nota
      kIdle: begin
        if (nota_desejada != nota_tocando_reg) begin
          byte_idx_next = 2'd0;
          estado_next   = kSendByte;
          if (nota_tocando_reg != 7'd0) begin
            // Note Off para nota anterior
            byte0_next        = 8'h80;
            byte1_next        = {1'b0, nota_tocando_reg};
            byte2_next        = 8'h00;
            nota_tocando_next = 7'd0;
          end else begin
            // Note On para nova nota
            byte0_next        = 8'h90;
            byte1_next        = {1'b0, nota_desejada};
            byte2_next        = {1'b0, velocity_desejado};
            nota_tocando_next = nota_desejada;
          end
        end
      end

      // Inicia transmissao do byte
      kSendByte: begin
        estado_next = kWaitByte;
      end

      // Aguarda UART concluir o byte
      kWaitByte: begin
        if (tx_pronto) begin
          if (byte_idx_reg == 2'd2) begin
            byte_idx_next = 2'd0;
            estado_next   = kIdle;
          end else begin
            byte_idx_next = byte_idx_reg + 2'd1;
            estado_next   = kSendByte;
          end
        end
      end

      default: begin
        estado_next = 2'bxx;
      end
    endcase
  end

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      estado_reg       <= kIdle;
      nota_tocando_reg <= 7'd0;
      byte0_reg        <= 8'd0;
      byte1_reg        <= 8'd0;
      byte2_reg        <= 8'd0;
      byte_idx_reg     <= 2'd0;
    end else begin
      estado_reg       <= estado_next;
      nota_tocando_reg <= nota_tocando_next;
      byte0_reg        <= byte0_next;
      byte1_reg        <= byte1_next;
      byte2_reg        <= byte2_next;
      byte_idx_reg     <= byte_idx_next;
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
