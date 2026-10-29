// Descrição: Testbench auto-verificavel para o codificador MIDI (codificador_midi).
// Funcionamento: Valida notas naturais, sustenidos e condicoes de silencio
// em todas as oitavas (0 a 7), garantindo conformidade com a tabela MIDI.

`timescale 1ns / 1ps
`default_nettype none

module codificador_midi_tb;

  localparam WatchdogMaxNs = 20000;

  reg  [2:0] oitava;
  reg        sustenido;
  reg  [2:0] nota_id;
  wire [6:0] nota_midi;

  integer errors    = 0;
  integer tests_run = 0;

  codificador_midi codificador_midi_inst (
    .oitava    (oitava),
    .sustenido (sustenido),
    .nota_id   (nota_id),
    .nota_midi (nota_midi)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Simulation watchdog timed out!", $time);
    $finish;
  end

  task expect_midi(
    input [2:0]   in_oitava,
    input         in_sustenido,
    input [2:0]   in_nota_id,
    input [6:0]   expected_midi,
    input [127:0] test_tag
  );
    begin
      tests_run = tests_run + 1;
      oitava    = in_oitava;
      sustenido = in_sustenido;
      nota_id   = in_nota_id;
      #5;
      if (nota_midi !== expected_midi) begin
        $display("[FAIL] %0t ns | %0s (oitava=%0d, sust=%0b, nota=%0d): expected %0d, got %0d",
          $time, test_tag, in_oitava, in_sustenido, in_nota_id, expected_midi, nota_midi);
        errors = errors + 1;
      end
    end
  endtask

  task test_silence_cases;
    integer o;
    integer n;
    begin
      for (o = 0; o <= 7; o = o + 1) begin
        expect_midi(o[2:0], 1'b0, 3'd0, 7'd0, "NOTA_ZERO_NAT");
        expect_midi(o[2:0], 1'b1, 3'd0, 7'd0, "NOTA_ZERO_SHARP");
      end
      for (n = 1; n <= 7; n = n + 1) begin
        expect_midi(3'd0, 1'b0, n[2:0], 7'd0, "OITAVA_ZERO_NAT");
        expect_midi(3'd0, 1'b1, n[2:0], 7'd0, "OITAVA_ZERO_SHARP");
      end
    end
  endtask

  task test_all_octaves_and_notes;
    integer o;
    reg [6:0] base;
    begin
      for (o = 1; o <= 7; o = o + 1) begin
        base = 7'd12 + (o[6:0] * 7'd12);

        expect_midi(o[2:0], 1'b0, 3'd1, base + 7'd0,  "DO_NAT");
        expect_midi(o[2:0], 1'b0, 3'd2, base + 7'd2,  "RE_NAT");
        expect_midi(o[2:0], 1'b0, 3'd3, base + 7'd4,  "MI_NAT");
        expect_midi(o[2:0], 1'b0, 3'd4, base + 7'd5,  "FA_NAT");
        expect_midi(o[2:0], 1'b0, 3'd5, base + 7'd7,  "SOL_NAT");
        expect_midi(o[2:0], 1'b0, 3'd6, base + 7'd9,  "LA_NAT");
        expect_midi(o[2:0], 1'b0, 3'd7, base + 7'd11, "SI_NAT");

        expect_midi(o[2:0], 1'b1, 3'd1, base + 7'd1,  "DO_SHARP");
        expect_midi(o[2:0], 1'b1, 3'd2, base + 7'd3,  "RE_SHARP");
        expect_midi(o[2:0], 1'b1, 3'd3, base + 7'd5,  "MI_SHARP");
        expect_midi(o[2:0], 1'b1, 3'd4, base + 7'd6,  "FA_SHARP");
        expect_midi(o[2:0], 1'b1, 3'd5, base + 7'd8,  "SOL_SHARP");
        expect_midi(o[2:0], 1'b1, 3'd6, base + 7'd10, "LA_SHARP");

        if (o < 7) begin
          expect_midi(o[2:0], 1'b1, 3'd7, base + 7'd12, "SI_SHARP_NEXT_OCT");
        end else begin
          expect_midi(o[2:0], 1'b1, 3'd7, base + 7'd11, "SI_SHARP_SAT_OCT7");
        end
      end
    end
  endtask

  initial begin
    $display("========================================");
    $display("STARTING SIMULATION: codificador_midi_tb");
    $display("========================================");

    test_silence_cases();
    test_all_octaves_and_notes();

    #20;
    $display("\n========================================");
    $display("TEST SUMMARY");
    $display("Tests Executed: %0d", tests_run);
    $display("Errors Found:   %0d", errors);
    if (errors == 0) begin
      $display("RESULT: ALL TESTS PASSED!");
      $display("========================================");
    end else begin
      $display("RESULT: TESTBENCH FAILED with %0d error(s)!", errors);
      $display("========================================");
    end

    $finish;
  end

endmodule

`default_nettype wire
