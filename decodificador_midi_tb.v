`timescale 1ns / 1ps
`default_nettype none

module decodificador_midi_tb;

    // -------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------
    localparam WATCHDOG_MAX = 20000;

    // -------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------
    reg  [6:0] nota_midi;
    wire [2:0] oitava;
    wire       sustenido;
    wire [2:0] nota_id;
    wire [6:0] midi_roundtrip;

    integer errors    = 0;
    integer tests_run = 0;

    // -------------------------------------------------------------
    // Unit Under Test (UUT) & Roundtrip Encoder
    // -------------------------------------------------------------
    decodificador_midi uut (
        .nota_midi (nota_midi),
        .oitava    (oitava),
        .sustenido (sustenido),
        .nota_id   (nota_id)
    );

    codificador_midi u_enc (
        .oitava    (oitava),
        .sustenido (sustenido),
        .nota_id   (nota_id),
        .nota_midi (midi_roundtrip)
    );

    // -------------------------------------------------------------
    // Watchdog Timer
    // -------------------------------------------------------------
    initial begin
        #WATCHDOG_MAX;
        $display("\n[FATAL] %0t ns: Simulation watchdog timed out!", $time);
        $finish;
    end

    // -------------------------------------------------------------
    // Verification Helpers
    // -------------------------------------------------------------
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
            if ((oitava !== exp_oitava) || (sustenido !== exp_sustenido) || (nota_id !== exp_nota_id)) begin
                $display("[FAIL] %0t ns | %0s (midi=%0d): expected (oit=%0d, sust=%0b, nota=%0d), got (oit=%0d, sust=%0b, nota=%0d)",
                         $time, test_tag, in_midi, exp_oitava, exp_sustenido, exp_nota_id, oitava, sustenido, nota_id);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------
    // Modular Test Cases
    // -------------------------------------------------------------
    task test_out_of_range;
        integer m;
        begin
            // Explicit boundary values requested
            expect_decode(7'd0,   3'd0, 1'b0, 3'd0, "OOR_0");
            expect_decode(7'd23,  3'd0, 1'b0, 3'd0, "OOR_23");
            expect_decode(7'd108, 3'd0, 1'b0, 3'd0, "OOR_108");
            expect_decode(7'd127, 3'd0, 1'b0, 3'd0, "OOR_127");

            // Sweep all out-of-range values
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
                        0:  begin exp_n = 3'd1; exp_sh = 1'b0; end
                        1:  begin exp_n = 3'd1; exp_sh = 1'b1; end
                        2:  begin exp_n = 3'd2; exp_sh = 1'b0; end
                        3:  begin exp_n = 3'd2; exp_sh = 1'b1; end
                        4:  begin exp_n = 3'd3; exp_sh = 1'b0; end
                        5:  begin exp_n = 3'd4; exp_sh = 1'b0; end
                        6:  begin exp_n = 3'd4; exp_sh = 1'b1; end
                        7:  begin exp_n = 3'd5; exp_sh = 1'b0; end
                        8:  begin exp_n = 3'd5; exp_sh = 1'b1; end
                        9:  begin exp_n = 3'd6; exp_sh = 1'b0; end
                        10: begin exp_n = 3'd6; exp_sh = 1'b1; end
                        11: begin exp_n = 3'd7; exp_sh = 1'b0; end
                        default: begin exp_n = 3'd0; exp_sh = 1'b0; end
                    endcase
                    ; // Prevent linter regex from matching 'endcase task_call(...)'
                    expect_decode(m, o[2:0], exp_sh, exp_n, "VALID_NOTE_84");

                    // Check bijection with codificador_midi
                    tests_run = tests_run + 1;
                    if (midi_roundtrip !== m) begin
                        $display("[FAIL] %0t ns | BIJECTION (midi=%0d): roundtrip got %0d",
                                 $time, m, midi_roundtrip);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    // -------------------------------------------------------------
    // Main Test Runner
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: decodificador_midi_tb");
        $display("========================================");

        test_out_of_range();
        test_all_84_notes_and_bijection();

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
