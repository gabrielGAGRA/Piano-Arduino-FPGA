`timescale 1ns / 1ps
`default_nettype none

module gerenciador_midi_tx_tb;

    // -------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------
    localparam CLK_PERIOD   = 20;
    localparam CLOCK_DIV    = 4;
    localparam WATCHDOG_MAX = 500_000;

    // -------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------
    reg        clock;
    reg        reset;
    reg  [6:0] nota_desejada;
    reg  [6:0] velocity_desejado;
    wire       saida_serial;
    wire       ocupado;

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
    gerenciador_midi_tx #(
        .CLOCK_DIV (CLOCK_DIV)
    ) uut (
        .clock             (clock),
        .reset             (reset),
        .nota_desejada     (nota_desejada),
        .velocity_desejado (velocity_desejado),
        .saida_serial      (saida_serial),
        .ocupado           (ocupado)
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
    // Verification Helpers & Serial Monitor
    // -------------------------------------------------------------
    task setup;
        begin
            nota_desejada     <= 7'd0;
            velocity_desejado <= 7'd0;
            reset             <= 1'b1;
            repeat (2) @(posedge clock);
            @(negedge clock);
            reset             <= 1'b0;
            @(posedge clock);
        end
    endtask

    task receive_uart_byte(
        output [7:0] rx_byte
    );
        integer bit_idx;
        begin
            @(negedge saida_serial);
            repeat (CLOCK_DIV / 2) @(posedge clock);
            #1;
            if (saida_serial !== 1'b0) begin
                $display("[FAIL] %0t ns | UART start bit error: expected 0, got %b", $time, saida_serial);
                errors = errors + 1;
            end
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                repeat (CLOCK_DIV) @(posedge clock);
                #1;
                rx_byte[bit_idx] = saida_serial;
            end
            repeat (CLOCK_DIV) @(posedge clock);
            #1;
            if (saida_serial !== 1'b1) begin
                $display("[FAIL] %0t ns | UART stop bit error: expected 1, got %b", $time, saida_serial);
                errors = errors + 1;
            end
        end
    endtask

    task receive_and_verify_midi_packet(
        input [23:0]  expected_packet,
        input [127:0] test_tag
    );
        reg [7:0]  b0;
        reg [7:0]  b1;
        reg [7:0]  b2;
        reg [23:0] actual_packet;
        begin
            receive_uart_byte(b0);
            receive_uart_byte(b1);
            receive_uart_byte(b2);
            actual_packet = {b0, b1, b2};
            if (actual_packet !== expected_packet) begin
                $display("[FAIL] %0t ns | %0s: expected 24'h%06h, got 24'h%06h",
                         $time, test_tag, expected_packet, actual_packet);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------
    // Modular Test Cases
    // -------------------------------------------------------------
    task test_note_attack_and_release;
        begin
            tests_run = tests_run + 1;
            setup();

            // 1. Ataque de nota (nota_desejada = 60 (8'h3C), velocity = 100 (8'h64)) -> 24'h903C64
            @(negedge clock);
            nota_desejada     <= 7'd60;
            velocity_desejado <= 7'd100;

            receive_and_verify_midi_packet(24'h903C64, "NOTE_ON_60");

            // Wait for ocupado to deassert
            while (ocupado !== 1'b0) @(posedge clock);

            // 2. Soltura de nota (nota_desejada = 0) -> 24'h803C00
            tests_run = tests_run + 1;
            @(negedge clock);
            nota_desejada <= 7'd0;

            receive_and_verify_midi_packet(24'h803C00, "NOTE_OFF_60");

            while (ocupado !== 1'b0) @(posedge clock);
        end
    endtask

    task test_legato_transition_and_mid_tx_change;
        begin
            tests_run = tests_run + 1;
            setup();

            // Start Note 60 (0x3C) with velocity 100 (0x64)
            @(negedge clock);
            nota_desejada     <= 7'd60;
            velocity_desejado <= 7'd100;

            // Change note directly to 64 (0x40) with velocity 95 (0x5F) WHILE Note 60 is still transmitting!
            fork
                begin
                    receive_and_verify_midi_packet(24'h903C64, "LEGATO_INITIAL_ON_60");
                    receive_and_verify_midi_packet(24'h803C00, "LEGATO_AUTO_OFF_60");
                    receive_and_verify_midi_packet(24'h90405F, "LEGATO_FOLLOW_ON_64");
                end

                begin
                    repeat (15) @(posedge clock);
                    @(negedge clock);
                    nota_desejada     <= 7'd64;
                    velocity_desejado <= 7'd95;
                end
            join

            begin
                while (ocupado !== 1'b0) @(posedge clock);
            end
        end
    endtask

    // -------------------------------------------------------------
    // Main Test Runner
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: gerenciador_midi_tx_tb");
        $display("========================================");

        test_note_attack_and_release();
        test_legato_transition_and_mid_tx_change();

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
