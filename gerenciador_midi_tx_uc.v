// Descricao: Unidade de controle para transmissao MIDI de 3 bytes.
// Funcionamento: FSM de 3 estados para sequenciamento dos bytes de pacotes
// Note On e Note Off transmitidos via transmissor serial UART 8N1.

`timescale 1ns / 1ps
`default_nettype none

module gerenciador_midi_tx_uc (
  input  wire clk,
  input  wire arst,
  input  wire tem_mudanca_nota,
  input  wire tx_pronto,
  input  wire fim_bytes,
  output reg  carrega_pacote,
  output reg  zera_idx,
  output reg  conta_idx,
  output reg  tx_partida,
  output reg  ocupado_uc
);

  localparam [1:0]
    kIdle     = 2'b00,
    kSendByte = 2'b01,
    kWaitByte = 2'b10;

  reg [1:0] state_reg;
  reg [1:0] state_next;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      state_reg <= kIdle;
    end else begin
      state_reg <= state_next;
    end
  end

  always @* begin
    state_next     = state_reg;
    carrega_pacote = 1'b0;
    zera_idx       = 1'b0;
    conta_idx      = 1'b0;
    tx_partida     = 1'b0;
    ocupado_uc     = 1'b0;

    case (state_reg)
      // Aguarda solicitacao de mudanca de nota
      kIdle: begin
        if (tem_mudanca_nota) begin
          carrega_pacote = 1'b1;
          zera_idx       = 1'b1;
          state_next     = kSendByte;
        end
      end

      // Inicia transmissao do byte atual pela UART
      kSendByte: begin
        ocupado_uc = 1'b1;
        tx_partida = 1'b1;
        state_next = kWaitByte;
      end

      // Aguarda UART concluir envio do byte atual
      kWaitByte: begin
        ocupado_uc = 1'b1;
        if (tx_pronto) begin
          if (fim_bytes) begin
            zera_idx   = 1'b1;
            state_next = kIdle;
          end else begin
            conta_idx  = 1'b1;
            state_next = kSendByte;
          end
        end
      end

      default: begin
        state_next = 2'bxx;
      end
    endcase
  end

endmodule

`default_nettype wire
