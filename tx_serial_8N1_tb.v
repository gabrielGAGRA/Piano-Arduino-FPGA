// Descrição: Testbench auto-verificavel para o transmissor UART 8N1 (tx_serial_8N1).
// Funcionamento: Valida envio serial assincrono de bytes (start bit, 8 bits LSB
// first, stop bit) na taxa definida por ClockDiv e checa sinalizacao de pronto.

`timescale 1ns / 1ps
`default_nettype none

module tx_serial_8N1_tb;

  localparam ClkPeriodNs   = 20;
  localparam ClockDiv      = 4;
  localparam WatchdogMaxNs = 200_000;

  reg        clk;
  reg        arst;
  reg        partida;
  reg  [7:0] dados_byte;
  wire       saida_serial;
  wire       pronto;
  wire       db_partida;
  wire       db_saida_serial;
  wire [3:0] db_estado;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  tx_serial_8N1 #(
    .ClockDiv (ClockDiv)
  ) tx_serial_8N1_inst (
    .clk             (clk),
    .arst            (arst),
    .partida         (partida),
    .dados_byte      (dados_byte),
    .saida_serial    (saida_serial),
    .pronto          (pronto),
    .db_partida      (db_partida),
    .db_saida_serial (db_saida_serial),
    .db_estado       (db_estado)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Simulation watchdog timed out!", $time);
    $finish;
  end

  task setup;
    begin
      partida    <= 1'b0;
      dados_byte <= 8'd0;
      arst       <= 1'b1;
      repeat (2) @(posedge clk);
      @(negedge clk);
      arst       <= 1'b0;
      @(posedge clk);
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

      @(negedge clk);
      if (saida_serial !== 1'b1) begin
        $display("[FAIL] %0t ns | %0s: idle line expected 1'b1, got %b",
          $time, test_tag, saida_serial);
        errors = errors + 1;
      end

      dados_byte <= expected_byte;
      partida    <= 1'b1;
      @(negedge clk);
      partida    <= 1'b0;

      @(negedge saida_serial);

      repeat (ClockDiv / 2) @(posedge clk);
      #1;
      start_bit = saida_serial;
      if (start_bit !== 1'b0) begin
        $display("[FAIL] %0t ns | %0s: start bit expected 1'b0, got %b",
          $time, test_tag, start_bit);
        errors = errors + 1;
      end

      for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
        repeat (ClockDiv) @(posedge clk);
        #1;
        rx_byte[bit_idx] = saida_serial;
      end

      repeat (ClockDiv) @(posedge clk);
      #1;
      stop_bit = saida_serial;
      if (stop_bit !== 1'b1) begin
        $display("[FAIL] %0t ns | %0s: stop bit expected 1'b1, got %b",
          $time, test_tag, stop_bit);
        errors = errors + 1;
      end

      if (rx_byte !== expected_byte) begin
        $display("[FAIL] %0t ns | %0s: expected 8'h%02h, got 8'h%02h",
          $time, test_tag, expected_byte, rx_byte);
        errors = errors + 1;
      end

      @(posedge pronto);
      @(negedge pronto);
    end
  endtask

  initial begin
    $display("========================================");
    $display("STARTING SIMULATION: tx_serial_8N1_tb");
    $display("========================================");

    setup();

    send_and_verify_byte(8'h55, "PATTERN_0x55_ALT1");
    send_and_verify_byte(8'hAA, "PATTERN_0xAA_ALT2");
    send_and_verify_byte(8'h00, "ALL_ZEROS_0x00");
    send_and_verify_byte(8'hFF, "ALL_ONES_0xFF");
    send_and_verify_byte(8'h90, "MIDI_NOTE_ON_0x90");
    send_and_verify_byte(8'h3C, "MIDI_PITCH_C4_60");
    send_and_verify_byte(8'h7F, "MIDI_VELOCITY_MAX_127");

    #50;
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
