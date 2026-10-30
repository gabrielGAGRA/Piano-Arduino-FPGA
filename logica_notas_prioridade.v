// Descricao: Codificador de prioridade de notas com selecao de borda.
// Funcionamento: Prioriza notas recem-pressionadas em relacao as mantidas,
// garantindo resposta imediata ao dedilhado do usuario.

`timescale 1ns / 1ps
`default_nettype none

module logica_notas_prioridade (
  input  wire       clk,
  input  wire       arst,
  input  wire [6:0] botoes,
  output reg  [2:0] nota_id,
  output wire       tem_nota
);

  reg [6:0] botoes_ant_reg;

  assign tem_nota = (|botoes);

  wire       nota_valida = (nota_id != 3'd0);
  wire [2:0] nota_idx    = nota_valida ? (nota_id - 3'd1) : 3'd0;
  wire       tecla_ativa = nota_valida & botoes[nota_idx];

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      nota_id        <= 3'd0;
      botoes_ant_reg <= 7'd0;
    end else begin
      botoes_ant_reg <= botoes;

      // Detecta borda de subida em cada botao
      if (botoes[0] && !botoes_ant_reg[0]) begin
        nota_id <= 3'd1;
      end else if (botoes[1] && !botoes_ant_reg[1]) begin
        nota_id <= 3'd2;
      end else if (botoes[2] && !botoes_ant_reg[2]) begin
        nota_id <= 3'd3;
      end else if (botoes[3] && !botoes_ant_reg[3]) begin
        nota_id <= 3'd4;
      end else if (botoes[4] && !botoes_ant_reg[4]) begin
        nota_id <= 3'd5;
      end else if (botoes[5] && !botoes_ant_reg[5]) begin
        nota_id <= 3'd6;
      end else if (botoes[6] && !botoes_ant_reg[6]) begin
        nota_id <= 3'd7;
      end

      // Fallback: se a ultima nota ativa foi solta, seleciona a de maior indice
      if (tem_nota && !tecla_ativa) begin
        if (botoes[6]) begin
          nota_id <= 3'd7;
        end else if (botoes[5]) begin
          nota_id <= 3'd6;
        end else if (botoes[4]) begin
          nota_id <= 3'd5;
        end else if (botoes[3]) begin
          nota_id <= 3'd4;
        end else if (botoes[2]) begin
          nota_id <= 3'd3;
        end else if (botoes[1]) begin
          nota_id <= 3'd2;
        end else if (botoes[0]) begin
          nota_id <= 3'd1;
        end
      end
    end
  end

endmodule

`default_nettype wire
