`timescale 1ns / 1ps
`default_nettype none

module tx_serial_8N1_tb;

    // -------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------
    localparam CLK_PERIOD   = 20;
    localparam CLOCK_DIV    = 4;
    localparam WATCHDOG_MAX = 200_000;

    // -------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------
    reg        clock;
    reg        reset;
    reg        partida;
    reg  [7:0] dados_byte;
    wire       saida_serial;
    wire       pronto;
    wire       db_partida;
    wire       db_saida_serial;
    wire [3:0] db_estado;

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
    tx_serial_8N1 #(
        .CLOCK_DIV (CLOCK_DIV)
    ) uut (
        .clock           (clock),
        .reset           (reset),
        .partida         (partida),
        .dados_byte      (dados_byte),
        .saida_serial    (saida_serial),
        .pronto          (pronto),
        .db_partida      (db_partida),
        .db_saida_serial (db_saida_serial),
        .db_estado       (db_estado)
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
            partida    <= 1'b0;
            dados_byte <= 8'd0;
            reset      <= 1'b1;
            repeat (2) @(posedge clock);
            @(negedge clock);
            reset      <= 1'b0;
            @(posedge clock);
        end
    endtask

    task send_and_verify_byte(
        input [7:0]   expected_byte,
        input [127:0] test_tag
    );
        reg [7:0] rx_byte;
        reg       start_bit;
        reg       stop_bit;
        integer   bit_idx;
        begin
            tests_run = tests_run + 1;

            // Ensure line is idle high before starting
            @(negedge clock);
            if (saida_serial !== 1'b1) begin
                $display("[FAIL] %0t ns | %0s: idle line expected 1'b1, got %b",
                         $time, test_tag, saida_serial);
                errors = errors + 1;
            end

            // Pulse partida for 1 clock cycle
            dados_byte <= expected_byte;
            partida    <= 1'b1;
            @(negedge clock);
            partida    <= 1'b0;

            // Concurrently capture the 8N1 serial frame and wait for pronto
            fork
                begin
                    @(negedge saida_serial);
                    // Wait half bit period to sample middle of start bit
                    repeat (CLOCK_DIV / 2) @(posedge clock);
                    #1;
                    start_bit = saida_serial;
                    if (start_bit !== 1'b0) begin
                        $display("[FAIL] %0t ns | %0s: start bit expected 0, got %b",
                                 $time, test_tag, start_bit);
                        errors = errors + 1;
                    end

                    // Sample 8 data bits (LSB first)
                    for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                        repeat (CLOCK_DIV) @(posedge clock);
                        #1;
                        rx_byte[bit_idx] = saida_serial;
                    end

                    // Sample stop bit
                    repeat (CLOCK_DIV) @(posedge clock);
                    #1;
                    stop_bit = saida_serial;
                    if (stop_bit !== 1'b1) begin
                        $display("[FAIL] %0t ns | %0s: stop bit expected 1, got %b",
                                 $time, test_tag, stop_bit);
                        errors = errors + 1;
                    end
                end

                begin
                    @(posedge pronto);
                    @(posedge clock);
                end
            join

            if (rx_byte !== expected_byte) begin
                $display("[FAIL] %0t ns | %0s: expected 8'h%02h, got 8'h%02h",
                         $time, test_tag, expected_byte, rx_byte);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------
    // Main Test Runner
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: tx_serial_8N1_tb");
        $display("========================================");

        setup();

        // Test MSB=1 bytes (MIDI Status bytes) and MSB=0 bytes (MIDI Data bytes)
        send_and_verify_byte(8'h90, "TX_BYTE_90_NOTE_ON");
        send_and_verify_byte(8'h3C, "TX_BYTE_3C_NOTE_60");
        send_and_verify_byte(8'h64, "TX_BYTE_64_VEL_100");
        send_and_verify_byte(8'h80, "TX_BYTE_80_NOTE_OFF");

        #100;
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
