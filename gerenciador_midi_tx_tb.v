// Descrição: Testbench auto-verificavel para o gerenciador de transmissao MIDI.
// Funcionamento: Valida o envio sequencial dos 3 bytes de mensagem MIDI (Status,
// Nota e Velocity) via UART 8N1 e o controle das flags de ocupado.

`timescale 1ns / 1ps
`default_nettype none

module gerenciador_midi_tx_tb;

  localparam ClkPeriodNs   = 20;
  localparam ClockDiv      = 4;
  localparam WatchdogMaxNs = 500_000;

  reg        clk;
  reg        arst;
  reg  [6:0] nota_desejada;
  reg  [6:0] velocity_desejado;
  wire       saida_serial;
  wire       ocupado;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  gerenciador_midi_tx #(
    .ClockDiv (ClockDiv)
  ) gerenciador_midi_tx_inst (
    .clk               (clk),
    .arst              (arst),
    .nota_desejada     (nota_desejada),
    .velocity_desejado (velocity_desejado),
    .saida_serial      (saida_serial),
    .ocupado           (ocupado)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Simulation watchdog timed out!", $time);
    $finish;
  end

  task setup;
    begin
      nota_desejada     <= 7'd0;
      velocity_desejado <= 7'd0;
      arst              <= 1'b1;
      repeat (2) @(posedge clk);
      @(negedge clk);
      arst              <= 1'b0;
      @(posedge clk);
    end
  endtask

  task receive_uart_byte(
    output [7:0] rx_byte
  );
    integer bit_idx;
    begin
      @(negedge saida_serial);
      repeat (ClockDiv / 2) @(posedge clk);
      #1;
      if (saida_serial !== 1'b0) begin
        $display("[FAIL] %0t ns | UART start bit error: expected 0, got %b", $time, saida_serial);
        errors = errors + 1;
      end
      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        repeat (ClockDiv) @(posedge clk);
        #1;
        rx_byte[bit_idx] = saida_serial;
      end
      repeat (ClockDiv) @(posedge clk);
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

  task test_note_attack_and_release;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      nota_desejada     <= 7'd60;
      velocity_desejado <= 7'd100;

      receive_and_verify_midi_packet(24'h903C64, "NOTE_ON_60");

      while (ocupado !== 1'b0) @(posedge clk);

      tests_run = tests_run + 1;
      @(negedge clk);
      nota_desejada <= 7'd0;

      receive_and_verify_midi_packet(24'h803C00, "NOTE_OFF_60");

      while (ocupado !== 1'b0) @(posedge clk);
    end
  endtask

  task test_legato_transition_and_mid_tx_change;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      nota_desejada     <= 7'd60;
      velocity_desejado <= 7'd100;

      fork
        begin
          receive_and_verify_midi_packet(24'h903C64, "LEGATO_INITIAL_ON_60");
          receive_and_verify_midi_packet(24'h803C00, "LEGATO_AUTO_OFF_60");
          receive_and_verify_midi_packet(24'h90405F, "LEGATO_FOLLOW_ON_64");
        end

        begin
          repeat (15) @(posedge clk);
          @(negedge clk);
          nota_desejada     <= 7'd64;
          velocity_desejado <= 7'd95;
        end
      join

      begin
        while (ocupado !== 1'b0) @(posedge clk);
      end
    end
  endtask

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
