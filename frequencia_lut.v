// Descrição: Tabela LUT de frequencias das notas musicais para o sintetizador.
// Funcionamento: Converte oitava (4 a 7), nota_id (1 a 7) e sustenido
// na contagem limite do oscilador (n_ticks) a 50 MHz.

`timescale 1ns / 1ps
`default_nettype none

module frequencia_lut (
  input  wire [2:0]  nota_id,
  input  wire        sustenido,
  input  wire [2:0]  oitava,
  output reg  [17:0] n_ticks
);

  reg [17:0] base_freq;

  always @* begin
    case (oitava)
      3'b100: begin // Oitava 4
        case (nota_id)
          3'd1:    base_freq = (!sustenido) ? 18'd191113 : 18'd180386; // Do4 / Do#4
          3'd2:    base_freq = (!sustenido) ? 18'd170262 : 18'd160706; // Re4 / Re#4
          3'd3:    base_freq = (!sustenido) ? 18'd151686 : 18'd143173; // Mi4
          3'd4:    base_freq = (!sustenido) ? 18'd143173 : 18'd135137; // Fa4 / Fa#4
          3'd5:    base_freq = (!sustenido) ? 18'd127553 : 18'd120394; // Sol4 / Sol#4
          3'd6:    base_freq = (!sustenido) ? 18'd113636 : 18'd107258; // La4 / La#4
          3'd7:    base_freq = (!sustenido) ? 18'd101238 : 18'd95556;  // Si4
          default: base_freq = 18'd0;
        endcase
      end

      3'b101: begin // Oitava 5
        case (nota_id)
          3'd1:    base_freq = (!sustenido) ? 18'd95557 : 18'd90193;
          3'd2:    base_freq = (!sustenido) ? 18'd85131 : 18'd80353;
          3'd3:    base_freq = (!sustenido) ? 18'd75844 : 18'd71586;
          3'd4:    base_freq = (!sustenido) ? 18'd71586 : 18'd67569;
          3'd5:    base_freq = (!sustenido) ? 18'd63776 : 18'd60197;
          3'd6:    base_freq = (!sustenido) ? 18'd56818 : 18'd53629;
          3'd7:    base_freq = (!sustenido) ? 18'd50619 : 18'd47778;
          default: base_freq = 18'd0;
        endcase
      end

      3'b110: begin // Oitava 6
        case (nota_id)
          3'd1:    base_freq = (!sustenido) ? 18'd47778 : 18'd45097;
          3'd2:    base_freq = (!sustenido) ? 18'd42566 : 18'd40177;
          3'd3:    base_freq = (!sustenido) ? 18'd37922 : 18'd35793;
          3'd4:    base_freq = (!sustenido) ? 18'd35793 : 18'd33784;
          3'd5:    base_freq = (!sustenido) ? 18'd31888 : 18'd30098;
          3'd6:    base_freq = (!sustenido) ? 18'd28409 : 18'd26815;
          3'd7:    base_freq = (!sustenido) ? 18'd25310 : 18'd23889;
          default: base_freq = 18'd0;
        endcase
      end

      3'b111: begin // Oitava 7
        case (nota_id)
          3'd1:    base_freq = (!sustenido) ? 18'd23889 : 18'd22548;
          3'd2:    base_freq = (!sustenido) ? 18'd21283 : 18'd20088;
          3'd3:    base_freq = (!sustenido) ? 18'd18961 : 18'd17897;
          3'd4:    base_freq = (!sustenido) ? 18'd17897 : 18'd16892;
          3'd5:    base_freq = (!sustenido) ? 18'd15944 : 18'd15049;
          3'd6:    base_freq = (!sustenido) ? 18'd14205 : 18'd13408;
          3'd7:    base_freq = (!sustenido) ? 18'd12655 : 18'd11945;
          default: base_freq = 18'd0;
        endcase
      end

      default: begin
        base_freq = 18'd0;
      end
    endcase

    n_ticks = base_freq;
  end

endmodule

`default_nettype wire
