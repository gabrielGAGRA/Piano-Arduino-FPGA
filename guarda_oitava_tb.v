`timescale 1ns / 1ps
`default_nettype none

module guarda_oitava_tb;

    // -------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------
    localparam CLK_PERIOD   = 20;
    localparam WATCHDOG_MAX = 20000;

    // -------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------
    reg        clock;
    reg        reset;
    reg        btn_up_pulse;
    reg        btn_down_pulse;
    wire [2:0] oitava_atual;

    integer errors    = 0;
    integer tests_run = 0;

    // -------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------
    initial clock = 1'b0;
    always #(CLK_PERIOD / 2) clock = ~clock;

    // -------------------------------------------------------------
    // Unit Under Test (UUT)
    // -------------------------------------------------------------
    guarda_oitava uut (
        .clock          (clock),
        .reset          (reset),
        .btn_up_pulse   (btn_up_pulse),
        .btn_down_pulse (btn_down_pulse),
        .oitava_atual   (oitava_atual)
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
    // Verification Helpers & Fixtures
    // -------------------------------------------------------------
    task setup;
        begin
            btn_up_pulse   = 1'b0;
            btn_down_pulse = 1'b0;
            reset          = 1'b1;
            repeat (2) @(posedge clock);
            @(negedge clock);
            reset          = 1'b0;
            @(posedge clock);
        end
    endtask

    task pulse_up;
        begin
            @(negedge clock);
            btn_up_pulse   = 1'b1;
            btn_down_pulse = 1'b0;
            @(posedge clock);
            #1;
            @(negedge clock);
            btn_up_pulse   = 1'b0;
        end
    endtask

    task pulse_down;
        begin
            @(negedge clock);
            btn_up_pulse   = 1'b0;
            btn_down_pulse = 1'b1;
            @(posedge clock);
            #1;
            @(negedge clock);
            btn_down_pulse = 1'b0;
        end
    endtask

    task expect_eq3(
        input [2:0]   actual,
        input [2:0]   expected,
        input [127:0] test_tag
    );
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0t ns | %0s: expected 3'd%0d, got 3'd%0d",
                         $time, test_tag, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------
    // Modular Test Cases
    // -------------------------------------------------------------
    task test_reset_state;
        begin
            tests_run = tests_run + 1;
            setup();
            #1;
            expect_eq3(oitava_atual, 3'd4, "RESET_OITAVA_4");
        end
    endtask

    task test_down_to_1_and_saturate;
        begin
            tests_run = tests_run + 1;
            setup();

            pulse_down();
            expect_eq3(oitava_atual, 3'd3, "DOWN_TO_3");

            pulse_down();
            expect_eq3(oitava_atual, 3'd2, "DOWN_TO_2");

            pulse_down();
            expect_eq3(oitava_atual, 3'd1, "DOWN_TO_1");

            // Saturate at 1
            pulse_down();
            expect_eq3(oitava_atual, 3'd1, "SATURATE_AT_1_A");

            pulse_down();
            expect_eq3(oitava_atual, 3'd1, "SATURATE_AT_1_B");
        end
    endtask

    task test_up_to_7_and_saturate;
        begin
            tests_run = tests_run + 1;
            // Start from 1 (after previous test or reset and go down to 1)
            setup();
            pulse_down();
            pulse_down();
            pulse_down();
            expect_eq3(oitava_atual, 3'd1, "START_AT_1");

            pulse_up();
            expect_eq3(oitava_atual, 3'd2, "UP_TO_2");

            pulse_up();
            expect_eq3(oitava_atual, 3'd3, "UP_TO_3");

            pulse_up();
            expect_eq3(oitava_atual, 3'd4, "UP_TO_4");

            pulse_up();
            expect_eq3(oitava_atual, 3'd5, "UP_TO_5");

            pulse_up();
            expect_eq3(oitava_atual, 3'd6, "UP_TO_6");

            pulse_up();
            expect_eq3(oitava_atual, 3'd7, "UP_TO_7");

            // Saturate at 7
            pulse_up();
            expect_eq3(oitava_atual, 3'd7, "SATURATE_AT_7_A");

            pulse_up();
            expect_eq3(oitava_atual, 3'd7, "SATURATE_AT_7_B");
        end
    endtask

    // -------------------------------------------------------------
    // Main Test Runner
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: guarda_oitava_tb");
        $display("========================================");

        test_reset_state();
        test_down_to_1_and_saturate();
        test_up_to_7_and_saturate();

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
