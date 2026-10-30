// Descricao: Unidade de controle da transmissao serial assincrona 8N1.
// Funcionamento: FSM com estados kIdle, kPreparacao, kEspera, kTransmissao
// e kFinalTx para orquestrar shift register e contador de bits.

`timescale 1ns / 1ps
`default_nettype none

module tx_serial_8N1_uc (
  input  wire       clk,
  input  wire       arst,
  input  wire       partida,
  input  wire       tick,
  input  wire       fim,
  output reg        zera,
  output reg        conta,
  output reg        carrega,
  output reg        desloca,
  output reg        pronto,
  output reg  [3:0] db_estado
);

  localparam [3:0]
    kIdle        = 4'b0000,
    kPreparacao  = 4'b0001,
    kEspera      = 4'b0011,
    kTransmissao = 4'b0111,
    kFinalTx     = 4'b1111;

  reg [3:0] estado_q;
  reg [3:0] estado_d;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      estado_q <= kIdle;
    end else begin
      estado_q <= estado_d;
    end
  end

  always @* begin
    estado_d = estado_q;
    case (estado_q)
      // Aguarda comando de transmissao
      kIdle: begin
        estado_d = partida ? kPreparacao : kIdle;
      end

      // Carrega dados e reseta contador
      kPreparacao: begin
        estado_d = kEspera;
      end

      // Aguarda tick de baud ou sinal de fim de trama
      kEspera: begin
        estado_d = tick ? kTransmissao : (fim ? kFinalTx : kEspera);
      end

      // Desloca proximo bit
      kTransmissao: begin
        estado_d = fim ? kFinalTx : kEspera;
      end

      // Conclusao da transmissao
      kFinalTx: begin
        estado_d = kIdle;
      end

      default: begin
        estado_d = 4'bxxxx;
      end
    endcase
  end

  always @* begin
    carrega = (estado_q == kPreparacao);
    zera    = (estado_q == kPreparacao);
    desloca = (estado_q == kTransmissao);
    conta   = (estado_q == kTransmissao);
    pronto  = (estado_q == kFinalTx);

    case (estado_q)
      kIdle:        db_estado = 4'b0000;
      kPreparacao:  db_estado = 4'b0001;
      kEspera:      db_estado = 4'b0011;
      kTransmissao: db_estado = 4'b0111;
      kFinalTx:     db_estado = 4'b1111;
      default:      db_estado = 4'bxxxx;
    endcase
  end

endmodule

`default_nettype wire
