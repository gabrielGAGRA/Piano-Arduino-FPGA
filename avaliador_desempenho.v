// Descricao: Avaliador de desempenho do Modo Assistido.
// Funcionamento: Conta acertos e erros por musica, calcula score percentual e
// envia, ao final da melodia, um pacote estruturado via UART para o dashboard.

`timescale 1ns / 1ps
`default_nettype none

module avaliador_desempenho (
  input  wire        clk,
  input  wire        arst,
  input  wire [1:0]  modo_ativo,
  input  wire [5:0]  sel_musica,
  input  wire        fim_musica,
  input  wire [7:0]  acertos,
  input  wire [7:0]  erros,
  output wire [7:0]  score,
  output wire        saida_serial
);

  localparam [1:0]
    kIdle     = 2'd0,
    kSendByte = 2'd1,
    kWaitByte = 2'd2;

  reg       fim_musica_prev_reg;

  reg [1:0] estado_reg;
  reg [1:0] estado_next;
  reg [2:0] byte_idx_reg;
  reg [2:0] byte_idx_next;

  reg [7:0] byte0_reg;
  reg [7:0] byte1_reg;
  reg [7:0] byte2_reg;
  reg [7:0] byte3_reg;
  reg [7:0] byte4_reg;
  reg [7:0] byte5_reg;
  reg [7:0] byte6_reg;

  reg [7:0]   tx_dados_byte;
  reg [7:0]   score_calc;
  wire        tx_partida;
  wire        tx_pronto;
  wire        em_modo_assistido;
  wire        envio_necessario;
  wire [23:0] score_num;
  wire [8:0]  denom_score;

  assign em_modo_assistido = (modo_ativo == 2'd1);
  assign envio_necessario  = em_modo_assistido && fim_musica && !fim_musica_prev_reg &&
    ((acertos != 8'd0) || (erros != 8'd0));

  assign denom_score = {1'b0, acertos} + {1'b0, erros};
  assign score_num   = (denom_score == 9'd0) ? 24'd0 :
    ({16'd0, acertos} * 24'd100) / {15'd0, denom_score};
  assign score       = score_calc;

  assign tx_partida  = (estado_reg == kSendByte);

  always @* begin
    if (denom_score == 9'd0) begin
      score_calc = 8'd0;
    end else begin
      score_calc = score_num[7:0];
    end
  end

  always @* begin
    case (byte_idx_reg)
      3'd0: tx_dados_byte = byte0_reg;
      3'd1: tx_dados_byte = byte1_reg;
      3'd2: tx_dados_byte = byte2_reg;
      3'd3: tx_dados_byte = byte3_reg;
      3'd4: tx_dados_byte = byte4_reg;
      3'd5: tx_dados_byte = byte5_reg;
      3'd6: tx_dados_byte = byte6_reg;
      default: tx_dados_byte = 8'd0;
    endcase
  end

  always @* begin
    estado_next   = estado_reg;
    byte_idx_next = byte_idx_reg;

    if (estado_reg == kIdle) begin
      if (envio_necessario) begin
        byte_idx_next = 3'd0;
        estado_next   = kSendByte;
      end
    end else if (estado_reg == kSendByte) begin
      estado_next = kWaitByte;
    end else if (estado_reg == kWaitByte) begin
      if (tx_pronto) begin
        if (byte_idx_reg == 3'd6) begin
          byte_idx_next = 3'd0;
          estado_next   = kIdle;
        end else begin
          byte_idx_next = byte_idx_reg + 3'd1;
          estado_next   = kSendByte;
        end
      end
    end
  end

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      fim_musica_prev_reg <= 1'b0;
      estado_reg          <= kIdle;
      byte_idx_reg        <= 3'd0;
      byte0_reg           <= 8'd0;
      byte1_reg           <= 8'd0;
      byte2_reg           <= 8'd0;
      byte3_reg           <= 8'd0;
      byte4_reg           <= 8'd0;
      byte5_reg           <= 8'd0;
      byte6_reg           <= 8'd0;
    end else begin
      fim_musica_prev_reg <= fim_musica;
      estado_reg          <= estado_next;
      byte_idx_reg        <= byte_idx_next;

      if ((estado_reg == kIdle) && envio_necessario) begin
        byte0_reg <= 8'hAA;
        byte1_reg <= 8'hD1;
        byte2_reg <= {2'b00, sel_musica};
        byte3_reg <= acertos;
        byte4_reg <= erros;
        byte5_reg <= score_calc;
        byte6_reg <= 8'hD1 + {2'b00, sel_musica} + acertos + erros + score_calc;
      end
    end
  end

  tx_serial_8N1 #(
    .ClockDiv(434)
  ) tx_serial_8N1_inst (
    .clk          (clk),
    .arst         (arst),
    .partida      (tx_partida),
    .dados_byte   (tx_dados_byte),
    .saida_serial (saida_serial),
    .pronto       (tx_pronto),
    .db_partida   (),
    .db_saida_serial(),
    .db_estado    ()
  );

endmodule

`default_nettype wire
