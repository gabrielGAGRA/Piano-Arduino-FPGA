// Descricao: FSM de controle principal do piano (modos Livre, Aprendizado, Gravacao, Demo).
// Funcionamento: FSM de dois processos que orquestra os 4 modos operacionais,
// transicoes de estado por botoes e pulsos de gravacao/leitura de memoria.

`timescale 1ns / 1ps
`default_nettype none

module unidade_controle (
  input  wire       clk,
  input  wire       arst,
  input  wire       mudou_modo,
  input  wire       mudou_musica,
  input  wire       tem_nota_ativa,
  input  wire       tecla_pressionada,
  input  wire       acerto_nota,
  input  wire       fim_musica,
  input  wire       pulso_bpm,
  output reg  [1:0] modo_ativo,
  output reg        escreve_ram,
  output reg        zera_endereco,
  output reg        conta_endereco,
  output reg  [4:0] estado_hex
);

  localparam [4:0]
    kInicial        = 5'd0,
    kLivre          = 5'd1,
    kIniciaMusica   = 5'd2,
    kEsperaNota     = 5'd3,
    kComparaNota    = 5'd4,
    kProximo        = 5'd5,
    kEsperaSoltar   = 5'd6,
    kFimMusicaSt    = 5'd7,
    kLeRamModo1     = 5'd16,
    kIniciaGravacao = 5'd8,
    kGravEsperaNota = 5'd9,
    kGravArmazena   = 5'd10,
    kGravProximo    = 5'd11,
    kGravSoltar     = 5'd12,
    kIniciaDemo     = 5'd15,
    kDemoTocaNota   = 5'd13,
    kDemoProximo    = 5'd14;

  reg [4:0] state_reg;
  reg [4:0] state_next;

  always @(posedge clk or posedge arst) begin
    if (arst) begin
      state_reg <= kInicial;
    end else begin
      state_reg <= state_next;
    end
  end

  always @* begin
    state_next     = state_reg;
    modo_ativo     = 2'd0;
    escreve_ram    = 1'b0;
    zera_endereco  = 1'b0;
    conta_endereco = 1'b0;
    estado_hex     = 5'd0;

    case (state_reg)
      kInicial: begin
        zera_endereco = 1'b1;
        estado_hex    = 5'h0;
        modo_ativo    = 2'd0;
        state_next    = kLivre;
      end

      kLivre: begin
        zera_endereco = 1'b1;
        estado_hex    = 5'h0;
        modo_ativo    = 2'd0;
        if (mudou_modo) begin
          state_next = kIniciaMusica;
        end
      end

      kIniciaMusica: begin
        modo_ativo    = 2'd1;
        zera_endereco = 1'b1;
        estado_hex    = 5'h1;
        state_next    = kEsperaNota;
      end

      kEsperaNota: begin
        modo_ativo = 2'd1;
        estado_hex = 5'h1;
        if (mudou_modo) begin
          state_next = kIniciaGravacao;
        end else if (mudou_musica) begin
          state_next = kIniciaMusica;
        end else if (tem_nota_ativa) begin
          state_next = kComparaNota;
        end
      end

      kComparaNota: begin
        modo_ativo = 2'd1;
        estado_hex = 5'h1;
        if (mudou_modo) begin
          state_next = kIniciaGravacao;
        end else if (mudou_musica) begin
          state_next = kIniciaMusica;
        end else if (acerto_nota) begin
          state_next = kEsperaSoltar;
        end else if (!tem_nota_ativa) begin
          state_next = kEsperaNota;
        end
      end

      kEsperaSoltar: begin
        modo_ativo = 2'd1;
        estado_hex = 5'h1;
        if (mudou_modo) begin
          state_next = kIniciaGravacao;
        end else if (mudou_musica) begin
          state_next = kIniciaMusica;
        end else if (!tem_nota_ativa) begin
          if (fim_musica) begin
            state_next = kFimMusicaSt;
          end else begin
            state_next = kProximo;
          end
        end
      end

      kProximo: begin
        modo_ativo     = 2'd1;
        estado_hex     = 5'h1;
        conta_endereco = 1'b1;
        state_next     = kLeRamModo1;
      end

      kLeRamModo1: begin
        modo_ativo = 2'd1;
        estado_hex = 5'h1;
        state_next = kEsperaNota;
      end

      kFimMusicaSt: begin
        modo_ativo = 2'd1;
        estado_hex = 5'h1;
        if (mudou_modo) begin
          state_next = kIniciaGravacao;
        end
      end

      kIniciaGravacao: begin
        modo_ativo    = 2'd2;
        zera_endereco = 1'b1;
        estado_hex    = 5'h2;
        state_next    = kGravEsperaNota;
      end

      kGravEsperaNota: begin
        modo_ativo = 2'd2;
        estado_hex = 5'h2;
        if (mudou_modo) begin
          state_next = kIniciaDemo;
        end else if (tem_nota_ativa) begin
          state_next = kGravSoltar;
        end
      end

      kGravSoltar: begin
        modo_ativo = 2'd2;
        estado_hex = 5'h2;
        if (mudou_modo) begin
          state_next = kIniciaDemo;
        end else if (!tem_nota_ativa) begin
          state_next = kGravArmazena;
        end
      end

      kGravArmazena: begin
        modo_ativo  = 2'd2;
        estado_hex  = 5'h2;
        escreve_ram = 1'b1;
        state_next  = kGravProximo;
      end

      kGravProximo: begin
        modo_ativo     = 2'd2;
        estado_hex     = 5'h2;
        conta_endereco = 1'b1;
        state_next     = kGravEsperaNota;
      end

      kIniciaDemo: begin
        modo_ativo    = 2'd3;
        zera_endereco = 1'b1;
        estado_hex    = 5'h3;
        if (mudou_modo) begin
          state_next = kLivre;
        end else if (mudou_musica) begin
          state_next = kIniciaDemo;
        end else if (tecla_pressionada) begin
          state_next = kDemoTocaNota;
        end
      end

      kDemoTocaNota: begin
        modo_ativo = 2'd3;
        estado_hex = 5'h3;
        if (mudou_modo) begin
          state_next = kLivre;
        end else if (mudou_musica) begin
          state_next = kIniciaDemo;
        end else if (pulso_bpm) begin
          if (fim_musica) begin
            state_next = kIniciaDemo;
          end else begin
            state_next = kDemoProximo;
          end
        end
      end

      kDemoProximo: begin
        modo_ativo     = 2'd3;
        estado_hex     = 5'h3;
        conta_endereco = 1'b1;
        if (mudou_modo) begin
          state_next = kLivre;
        end else if (mudou_musica) begin
          state_next = kIniciaDemo;
        end else begin
          state_next = kDemoTocaNota;
        end
      end

      default: begin
        state_next = kInicial;
      end
    endcase
  end

endmodule

`default_nettype wire
