`timescale 1ns / 1ps
`default_nettype none

/*
 * Descricao : Gerenciador de pacotes MIDI de 24 bits (3 bytes) via UART 8N1.
 *             Implementa reconciliacao continua entre nota_desejada e nota_tocando_reg
 *             para evitar race conditions ou notas presas em transicoes rapidas/legato.
 */
module gerenciador_midi_tx #(
    parameter CLOCK_DIV = 434
) (
    input  wire       clock,
    input  wire       reset,
    input  wire [6:0] nota_desejada,
    input  wire [6:0] velocity_desejado,
    output wire       saida_serial,
    output wire       ocupado
);

    localparam [1:0] STATE_IDLE      = 2'b00,
                     STATE_SEND_BYTE = 2'b01,
                     STATE_WAIT_BYTE = 2'b10;

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

    assign tx_partida = (estado_reg == STATE_SEND_BYTE);
    assign ocupado    = (estado_reg != STATE_IDLE) || (nota_desejada != nota_tocando_reg);

    // Selecao do byte atual a transmitir
    always @* begin
        case (byte_idx_reg)
            2'd0:    tx_dados_byte = byte0_reg;
            2'd1:    tx_dados_byte = byte1_reg;
            2'd2:    tx_dados_byte = byte2_reg;
            default: tx_dados_byte = byte0_reg;
        endcase
    end

    // Logica de proximo estado e atualizacao de registradores do datapath
    always @* begin
        estado_next       = estado_reg;
        nota_tocando_next = nota_tocando_reg;
        byte0_next        = byte0_reg;
        byte1_next        = byte1_reg;
        byte2_next        = byte2_reg;
        byte_idx_next     = byte_idx_reg;

        case (estado_reg)
            STATE_IDLE: begin
                if (nota_desejada != nota_tocando_reg) begin
                    byte_idx_next = 2'd0;
                    estado_next   = STATE_SEND_BYTE;
                    if (nota_tocando_reg != 7'd0) begin
                        // Envia Note Off da nota que estava tocando
                        byte0_next        = 8'h80;
                        byte1_next        = {1'b0, nota_tocando_reg};
                        byte2_next        = 8'h00;
                        nota_tocando_next = 7'd0;
                    end else begin
                        // Envia Note On da nova nota desejada
                        byte0_next        = 8'h90;
                        byte1_next        = {1'b0, nota_desejada};
                        byte2_next        = {1'b0, velocity_desejado};
                        nota_tocando_next = nota_desejada;
                    end
                end
            end

            STATE_SEND_BYTE: begin
                estado_next = STATE_WAIT_BYTE;
            end

            STATE_WAIT_BYTE: begin
                if (tx_pronto) begin
                    if (byte_idx_reg == 2'd2) begin
                        byte_idx_next = 2'd0;
                        estado_next   = STATE_IDLE;
                    end else begin
                        byte_idx_next = byte_idx_reg + 2'd1;
                        estado_next   = STATE_SEND_BYTE;
                    end
                end
            end

            default: begin
                estado_next = STATE_IDLE;
            end
        endcase
    end

    // Registradores de estado e datapath
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            estado_reg       <= STATE_IDLE;
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
        .CLOCK_DIV (CLOCK_DIV)
    ) u_tx_serial_8N1 (
        .clock           (clock),
        .reset           (reset),
        .partida         (tx_partida),
        .dados_byte      (tx_dados_byte),
        .saida_serial    (saida_serial),
        .pronto          (tx_pronto),
        .db_partida      (),
        .db_saida_serial (),
        .db_estado       ()
    );

endmodule

`default_nettype wire
