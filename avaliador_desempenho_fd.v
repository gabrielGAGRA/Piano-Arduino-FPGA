// Descricao: Fluxo de dados (datapath) do avaliador de desempenho.
// Funcionamento: Armazena metricas de desempenho, calcula score percentual,
// monta o pacote UART de 7 bytes e efetua a transmissao serial via tx_serial_8N1.

`timescale 1ns / 1ps
`default_nettype none

module avaliador_desempenho_fd #(
  parameter ClockDivUart = 434
)(
  input  wire        clk,
  input  wire        arst,
  input  wire        carrega_pacote,
  input  wire        zera_idx,
  input  wire        conta_idx,
  input  wire        tx_partida,
  input  wire [1:0]  modo_ativo,
  input  wire [5:0]  sel_musica,
  input  wire        fim_musica,
  input  wire [7:0]  acertos,
  input  wire [7:0]  erros,
  input  wire [9:0]  pontos_apre,
  output wire        envio_necessario,
  output wire        tx_pronto,
  output wire        fim_bytes,
  output wire [7:0]  score,
  output wire        saida_serial
);

  reg       fim_musica_prev_reg;
  reg [2:0] byte_idx_reg;
  reg [7:0] score_reg;

  reg [7:0] byte0_reg;
  reg [7:0] byte1_reg;
  reg [7:0] byte2_reg;
  reg [7:0] byte3_reg;
  reg [7:0] byte4_reg;
  reg [7:0] byte5_reg;
  reg [7:0] byte6_reg;

  reg [7:0]   tx_dados_byte;
  reg [7:0]   score_calc;
  wire        em_modo_assistido;
  wire [23:0] score_num;
  wire [8:0]  denom_score;
  wire [10:0] max_pontos;

  assign em_modo_assistido = (modo_ativo == 2'd1);
  assign envio_necessario  = em_modo_assistido && fim_musica && !fim_musica_prev_reg &&
    ((acertos != 8'd0) || (erros != 8'd0));

  assign denom_score = {1'b0, acertos} + {1'b0, erros};
  assign max_pontos  = {denom_score, 2'b00};
  assign score_num   = (denom_score == 9'd0) ? 24'd0 :
    ({14'd0, pontos_apre} * 24'd100) / {13'd0, max_pontos};
  assign score       = score_reg;
  assign fim_bytes   = (byte_idx_reg == 3'd6);

  always @* begin
    if (denom_score == 9'd0) begin
      score_calc = 8'd0;
    end else if (score_num > 24'd100) begin
      score_calc = 8'd100;
    end else begin
      score_calc = score_num[7:0];
    end
  end

  always @* begin
    tx_dados_byte = 8'd0;
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

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      fim_musica_prev_reg <= 1'b0;
      byte_idx_reg        <= 3'd0;
      score_reg           <= 8'd0;
      byte0_reg           <= 8'd0;
      byte1_reg           <= 8'd0;
      byte2_reg           <= 8'd0;
      byte3_reg           <= 8'd0;
      byte4_reg           <= 8'd0;
      byte5_reg           <= 8'd0;
      byte6_reg           <= 8'd0;
    end else begin
      fim_musica_prev_reg <= fim_musica;
      score_reg           <= score_calc;

      if (zera_idx) begin
        byte_idx_reg <= 3'd0;
      end else if (conta_idx) begin
        byte_idx_reg <= byte_idx_reg + 3'd1;
      end

      if (carrega_pacote) begin
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
    .ClockDiv(ClockDivUart)
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
