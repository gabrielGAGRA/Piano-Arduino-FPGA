// Descricao: Testbench auto-verificavel para o decodificador MIDI (decodificador_midi).
// Funcionamento: Valida a traducao de numeros de notas MIDI (24..107) para oitava,
// sustenido e ID da nota, alem de testar valores fora de escala e bijecao com o codificador.

`timescale 1ns / 1ps
`default_nettype none

module decodificador_midi_tb;

  localparam WatchdogMaxNs = 20000;

  reg  [6:0] nota_midi;
  wire [2:0] oitava;
  wire       sustenido;
  wire [2:0] nota_id;
  wire [6:0] midi_roundtrip;

  integer errors    = 0;
  integer tests_run = 0;

  decodificador_midi decodificador_midi_inst (
    .nota_midi (nota_midi),
    .oitava    (oitava),
    .sustenido (sustenido),
    .nota_id   (nota_id)
  );

  codificador_midi codificador_midi_inst (
    .oitava    (oitava),
    .sustenido (sustenido),
    .nota_id   (nota_id),
    .nota_midi (midi_roundtrip)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Watchdog da simulacao estourou em decodificador_midi_tb!", $time);
    $finish;
  end

  task expect_decode(
    input [6:0]   in_midi,
    input [2:0]   exp_oitava,
    input         exp_sustenido,
    input [2:0]   exp_nota_id,
    input [127:0] test_tag
  );
    begin
      tests_run = tests_run + 1;
      nota_midi = in_midi;
      #5;
      if ((oitava !== exp_oitava) || (sustenido !== exp_sustenido) ||
          (nota_id !== exp_nota_id)) begin
        $display(
          "[FALHA] %0t ns | %0s (midi=%0d): esperado (%0d,%0b,%0d), obtido (%0d,%0b,%0d)",
          $time, test_tag, in_midi,
          exp_oitava, exp_sustenido, exp_nota_id,
          oitava, sustenido, nota_id
        );
        errors = errors + 1;
      end
    end
  endtask

  task test_out_of_range;
    integer m;
    begin
      expect_decode(7'd0,   3'd0, 1'b0, 3'd0, "OOR_0");
      expect_decode(7'd23,  3'd0, 1'b0, 3'd0, "OOR_23");
      expect_decode(7'd108, 3'd0, 1'b0, 3'd0, "OOR_108");
      expect_decode(7'd127, 3'd0, 1'b0, 3'd0, "OOR_127");

      for (m = 0; m < 24; m = m + 1) begin
        expect_decode(m[6:0], 3'd0, 1'b0, 3'd0, "OOR_LOW");
      end
      for (m = 108; m <= 127; m = m + 1) begin
        expect_decode(m[6:0], 3'd0, 1'b0, 3'd0, "OOR_HIGH");
      end
    end
  endtask

  task test_all_84_notes_and_bijection;
    integer o;
    integer s;
    reg [6:0] m;
    reg [2:0] exp_n;
    reg       exp_sh;
    begin
      for (o = 1; o <= 7; o = o + 1) begin
        for (s = 0; s < 12; s = s + 1) begin
          m = 7'd12 + (o[6:0] * 7'd12) + s[6:0];
          case (s)
            0:  begin exp_sh = 1'b0; exp_n = 3'd1; end // Do
            1:  begin exp_sh = 1'b1; exp_n = 3'd1; end // Do#
            2:  begin exp_sh = 1'b0; exp_n = 3'd2; end // Re
            3:  begin exp_sh = 1'b1; exp_n = 3'd2; end // Re#
            4:  begin exp_sh = 1'b0; exp_n = 3'd3; end // Mi
            5:  begin exp_sh = 1'b0; exp_n = 3'd4; end // Fa
            6:  begin exp_sh = 1'b1; exp_n = 3'd4; end // Fa#
            7:  begin exp_sh = 1'b0; exp_n = 3'd5; end // Sol
            8:  begin exp_sh = 1'b1; exp_n = 3'd5; end // Sol#
            9:  begin exp_sh = 1'b0; exp_n = 3'd6; end // La
            10: begin exp_sh = 1'b1; exp_n = 3'd6; end // La#
            11: begin exp_sh = 1'b0; exp_n = 3'd7; end // Si
            default: begin exp_sh = 1'b0; exp_n = 3'd0; end
          endcase

          expect_decode(m, o[2:0], exp_sh, exp_n, "VALID_NOTE");

          #5;
          if (midi_roundtrip !== m) begin
            $display("[FALHA DE IDA E VOLTA] %0t ns | midi=%0d -> decodificado -> enc_midi=%0d",
              $time, m, midi_roundtrip);
            errors = errors + 1;
          end
        end
      end
    end
  endtask

  initial begin
    $display("INICIANDO SIMULACAO: decodificador_midi_tb");

    test_out_of_range();
    test_all_84_notes_and_bijection();

    #20;
    $display("RESUMO DOS TESTES");
    $display("Testes executados: %0d", tests_run);
    $display("Erros encontrados: %0d", errors);
    if (errors == 0) begin
      $display("RESULTADO: TODOS OS TESTES PASSARAM!");
    end else begin
      $display("RESULTADO: TESTBENCH FALHOU com %0d erro(s)!", errors);
    end

    $finish;
  end

endmodule

`default_nettype wire
