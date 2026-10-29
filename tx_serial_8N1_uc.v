`timescale 1ns / 1ps
`default_nettype none

/*
 * Descricao : Unidade de controle do transmissor serial assincrono 8N1.
 */
module tx_serial_8N1_uc (
    input  wire       clock,
    input  wire       reset,
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

    localparam [3:0] STATE_INICIAL     = 4'b0000,
                     STATE_PREPARACAO  = 4'b0001,
                     STATE_ESPERA      = 4'b0011,
                     STATE_TRANSMISSAO = 4'b0111,
                     STATE_FINAL_TX    = 4'b1111;

    reg [3:0] estado_q;
    reg [3:0] estado_d;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            estado_q <= STATE_INICIAL;
        end else begin
            estado_q <= estado_d;
        end
    end

    always @* begin
        case (estado_q)
            STATE_INICIAL:     estado_d = partida ? STATE_PREPARACAO : STATE_INICIAL;
            STATE_PREPARACAO:  estado_d = STATE_ESPERA;
            STATE_ESPERA:      estado_d = tick ? STATE_TRANSMISSAO : (fim ? STATE_FINAL_TX : STATE_ESPERA);
            STATE_TRANSMISSAO: estado_d = fim ? STATE_FINAL_TX : STATE_ESPERA;
            STATE_FINAL_TX:    estado_d = STATE_INICIAL;
            default:           estado_d = STATE_INICIAL;
        endcase
    end

    always @* begin
        carrega = (estado_q == STATE_PREPARACAO) ? 1'b1 : 1'b0;
        zera    = (estado_q == STATE_PREPARACAO) ? 1'b1 : 1'b0;
        desloca = (estado_q == STATE_TRANSMISSAO) ? 1'b1 : 1'b0;
        conta   = (estado_q == STATE_TRANSMISSAO) ? 1'b1 : 1'b0;
        pronto  = (estado_q == STATE_FINAL_TX) ? 1'b1 : 1'b0;

        case (estado_q)
            STATE_INICIAL:     db_estado = 4'b0000;
            STATE_PREPARACAO:  db_estado = 4'b0001;
            STATE_ESPERA:      db_estado = 4'b0011;
            STATE_TRANSMISSAO: db_estado = 4'b0111;
            STATE_FINAL_TX:    db_estado = 4'b1111;
            default:           db_estado = 4'b1110;
        endcase
    end

endmodule

`default_nettype wire
