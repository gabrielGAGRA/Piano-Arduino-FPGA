// Descricao: Unidade de controle do avaliador de desempenho.
// Funcionamento: FSM de 3 estados (kIdle, kSendByte, kWaitByte) que gerencia
// a captura de metricas e o sequenciamento da transmissao serial do pacote UART.

`timescale 1ns / 1ps
`default_nettype none

module avaliador_desempenho_uc (
  input  wire clk,
  input  wire arst,
  input  wire envio_necessario,
  input  wire tx_pronto,
  input  wire fim_bytes,
  output reg  carrega_pacote,
  output reg  zera_idx,
  output reg  conta_idx,
  output reg  tx_partida
);

  localparam [1:0]
    kIdle     = 2'd0,
    kSendByte = 2'd1,
    kWaitByte = 2'd2;

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

    case (state_reg)
      // Aguarda condicao de envio de desempenho ao final da melodia
      kIdle: begin
        if (envio_necessario) begin
          carrega_pacote = 1'b1;
          zera_idx       = 1'b1;
          state_next     = kSendByte;
        end
      end

      // Dispara transmissao serial do byte atual
      kSendByte: begin
        tx_partida = 1'b1;
        state_next = kWaitByte;
      end

      // Aguarda transmissao do byte e avanca indice ou encerra pacote
      kWaitByte: begin
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
