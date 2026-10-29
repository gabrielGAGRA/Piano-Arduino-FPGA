# Testbench Verification & Simulation Guide

## 1. Golden Rules of RTL Verification

1. **Self-Checking (Automated Pass/Fail):** Testbenches MUST NOT require manual waveform inspection to determine success. Automated checks with assertions and an error counter MUST report unambiguous `PASSED` or `FAILED` banners.
2. **Minimum Testing Requirements (Designer Tests):**
   - The design block must elaborate cleanly with zero compiler or linter errors.
   - The design block must come out of reset with NO `X` (unknown) values on any output port.
   - At least one full transaction must be stimulated and observed correctly.
3. **Test Independence & Isolation:** Tests must be repeatable and independent. The failure or execution of one scenario must not corrupt subsequent scenarios. Always execute a common setup/reset routine before each test scenario.
4. **Informative Failure Diagnostics & Radix Prefixes:** When an assertion fails, print full diagnostic context: simulation time (`$time`), test scenario name, expected value, and actual received value. Printed numbers must be prefixed with their radix (`0x` for hex, `0b` for binary, decimal without radix).
5. **Non-Fatal (`expect_*`) vs. Fatal (`assert_*`) Checks:**
   - **`expect_*` (Non-Fatal):** Logs the mismatch, increments the error tally, and allows execution to continue so multiple bugs can be detected in a single run.
   - **`assert_*` (Fatal):** Used for structural prerequisites (successful reset, handshake synchronization, memory initialization). Aborts simulation immediately if violated to prevent cascading false failures.
6. **Deterministic Termination & Watchdog:** Every testbench MUST end with `$finish`. A parallel watchdog timer MUST run to terminate simulation if a state machine or handshake deadlocks.
7. **Parameter Overrides for Speed:** In simulation, override physical timing parameters (e.g., set `DebounceCycles = 5` instead of `50000`) so tests complete in milliseconds.
8. **Plusarg Values:** When using runtime arguments, use `$value$plusargs` with an explicit value assigned (e.g., `+seed=42`). Do not use `$test$plusargs`.

---

## 2. Core Testing Patterns in Verilog-2001

### A. Test Fixtures (`setup`)
Declare a dedicated `setup` or `reset_dut` task in Verilog:
- Drive all stimulus inputs to known, inactive states.
- Assert and deassert reset synchronously.
- Wait for a defined number of clock cycles to establish steady state.
- Assert that all output ports have emerged from reset without `X` or `Z` values.

### B. Assertion Helper Tasks
Create reusable tasks for value comparisons to eliminate boilerplate:

```verilog
task expect_eq8(
  input [7:0]   actual,
  input [7:0]   expected,
  input [127:0] test_tag
);
  begin
    if (actual !== expected) begin
      $display("[FAIL] %0t ns | %0s: expected 0x%0h (%0d), got 0x%0h (%0d)",
               $time, test_tag, expected, expected, actual, actual);
      errors = errors + 1;
    end
  end
endtask

task assert_true(
  input         cond,
  input [127:0] fatal_tag
);
  begin
    if (!cond) begin
      $display("[FATAL ASSERTION] %0t ns | %0s failed. Aborting simulation.", $time, fatal_tag);
      $finish;
    end
  end
endtask
```

### C. Modular Test Cases
Organize verification into discrete, named tasks (e.g., `test_reset_behavior`, `test_normal_operation`, `test_corner_cases`) called sequentially by a main `initial` runner.

---

## 3. Standard Testbench Template

```verilog
// Descrição: Self-checking testbench for my_module.
// Tests: Reset state, basic transaction flow, edge cases.

`timescale 1ns / 1ps
`default_nettype none

module my_module_test;

  // -------------------------------------------------------------
  // Parameters
  // -------------------------------------------------------------
  localparam ClkPeriodNs   = 20;     // 50 MHz clock
  localparam WatchdogMaxNs = 20000;  // 20 us safety timeout

  // -------------------------------------------------------------
  // Signals
  // -------------------------------------------------------------
  reg        clk;
  reg        rst;
  reg        enable;
  reg  [7:0] data_in;
  wire [7:0] data_out;
  wire       done;

  // Test tracking counters
  integer errors    = 0;
  integer tests_run = 0;

  // -------------------------------------------------------------
  // Clock Generation
  // -------------------------------------------------------------
  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  // -------------------------------------------------------------
  // Unit Under Test (UUT)
  // -------------------------------------------------------------
  my_module #(
    .SimSpeedup(1'b1)
  ) my_module_dut (
    .clk      (clk),
    .rst      (rst),
    .enable   (enable),
    .data_in  (data_in),
    .data_out (data_out),
    .done     (done)
  );

  // -------------------------------------------------------------
  // Watchdog Timer (Deadlock Prevention)
  // -------------------------------------------------------------
  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Simulation watchdog timed out! Potential deadlock.", $time);
    $finish;
  end

  // -------------------------------------------------------------
  // Verification Helpers & Fixtures
  // -------------------------------------------------------------
  task setup;
    begin
      enable  <= 1'b0;
      data_in <= 8'd0;
      rst     <= 1'b1;
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst     <= 1'b0;
      @(posedge clk);

      // Verify no X values emerge on outputs post-reset
      if (data_out === 8'hxx || done === 1'bx) begin
        $display("[FATAL] %0t ns: Output is X post-reset! data_out=0x%0h, done=%0b",
                 $time, data_out, done);
        $finish;
      end
    end
  endtask

  task expect_eq8(
    input [7:0]   actual,
    input [7:0]   expected,
    input [127:0] test_tag
  );
    begin
      if (actual !== expected) begin
        $display("[FAIL] %0t ns | %0s: expected 0x%0h (%0d), got 0x%0h (%0d)",
                 $time, test_tag, expected, expected, actual, actual);
        errors = errors + 1;
      end
    end
  endtask

  // -------------------------------------------------------------
  // Modular Test Cases
  // -------------------------------------------------------------
  task test_reset_behavior;
    begin
      tests_run = tests_run + 1;
      setup();
      @(negedge clk);
      expect_eq8(data_out, 8'd0, "RESET_DATA_OUT");
      if (done !== 1'b0) begin
        $display("[FAIL] %0t ns | RESET_DONE: expected 0b0, got 0b%0b", $time, done);
        errors = errors + 1;
      end
    end
  endtask

  task test_data_increment;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk);
      enable  <= 1'b1;
      data_in <= 8'd42;

      @(posedge clk);
      #1; // Sample post-clock edge
      expect_eq8(data_out, 8'd43, "DATA_INC_STEP1");

      @(negedge clk);
      enable <= 1'b0;
    end
  endtask

  // -------------------------------------------------------------
  // Main Test Runner
  // -------------------------------------------------------------
  initial begin
    $display("========================================");
    $display("STARTING SIMULATION: my_module_test");
    $display("========================================");

    test_reset_behavior();
    test_data_increment();

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
```

---

## 4. Simulation Toolchain & Commands

### A. Icarus Verilog (`iverilog` + `vvp`)
Compile and simulate from terminal or PowerShell:
```bash
# Compile RTL + Testbench
iverilog -Wall -g2001 -o sim.vvp my_module.v my_module_test.v

# Execute simulation
vvp sim.vvp
```

### B. Waveform Dumping (for GTKWave)
```verilog
initial begin
  $dumpfile("waveform.vcd");
  $dumpvars(0, my_module_test);
end
```
Then view with:
```bash
gtkwave waveform.vcd
```
