# Verilog-2001 Testbench & Simulation Standards

## Conformance Notation
* ***must*** / ***must not***: Mandatory requirement / absolute prohibition.
---

## 1. File Structure & Instantiation
- Testbench files ***must*** be named `<module>_tb.v` and contain exactly one module named `<module>_tb`.
- Testbench modules ***must not*** declare ports (`module <module>_tb;`).
- Files ***must*** declare `` `timescale 1ns/1ps `` and `` `default_nettype none `` before the module, and `` `default_nettype wire `` after `endmodule`.
- The Unit Under Test (UUT) ***must*** be instantiated with named ports (`.port(sig)`) and named `dut` or `uut`.
- Physical timing parameters (e.g., debounce count, prescalers) ***must*** be overridden in simulation to small values to complete execution in milliseconds.

## 2. Testbench Architecture & Execution
- Testbenches ***must*** be self-checking. Manual waveform inspection ***must not*** be required to determine pass/fail.
- Testbenches ***must*** declare integer counters: `errors = 0` and `tests_run = 0`.
- Testbenches ***must*** terminate deterministically via `$finish;`. `$stop;` ***must not*** be used as simulation completion.
- A concurrent watchdog timer ***must*** be declared in an independent `initial` block to abort deadlocked simulations with `$finish;`.
- Execution ***must*** print an unambiguous summary banner containing `ALL TESTS PASSED` when `errors == 0`, or `TESTBENCH FAILED` with error count when `errors > 0`.
- `$test$plusargs` ***must not*** use; `$value$plusargs` ***must*** be used when reading runtime plusargs.

## 3. Timing, Driving & Sampling
- Clock generation ***must*** use `initial clk = 1'b0;` and `always #(Period/2) clk = ~clk;`.
- Synchronous inputs to the DUT ***must*** be driven on the inactive clock edge (`@(negedge clk)`) or with an explicit delta delay after edge (`@(posedge clk); #1;`) to prevent simulator race conditions.
- Output checks ***must*** be sampled when signals are stable (`@(negedge clk)` or after `#1` propagation delay).
- High-impedance (`Z`) and unknown (`X`) states ***must*** be checked using identity operators (`===`, `!==`).

## 4. Reset & Verification Fixtures
- Test suites ***must*** declare a dedicated `setup` or `reset_dut` task called before each discrete test scenario.
- The `setup` task ***must*** initialize all inputs to inactive values, toggle reset synchronously, and verify that outputs do not remain `X` or `Z`.
- Discrete verification scenarios ***must*** be isolated in dedicated tasks (`test_<scenario>`) to prevent failure cascades.
- Non-fatal checks (`expect_*`) ***must*** increment `errors` and continue simulation. Structural failures (reset deadlock, setup faults) ***must*** abort immediately with `$finish;`.
- Failure messages ***must*** report simulation time (`$time`), test tag, expected value, and actual value, with explicit radix prefixes (`0x%0h`, `0b%0b`, `%0d`).

---

## 5. Canonical Testbench Skeleton

```verilog
`timescale 1ns / 1ps
`default_nettype none

module my_module_tb;
  localparam ClkPeriodNs = 20;
  localparam WatchdogNs  = 20000;

  reg clk;
  reg rst;
  reg in_val;
  wire out_val;

  integer errors = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  my_module #(.SimSpeedup(1'b1)) dut (
    .clk(clk), .rst(rst), .in_val(in_val), .out_val(out_val)
  );

  // Mandatory Watchdog
  initial begin
    #WatchdogNs;
    $display("[FATAL] %0t ns: Watchdog timeout - simulation deadlocked.", $time);
    $finish;
  end

  task setup;
    begin
      rst <= 1'b1; in_val <= 1'b0;
      repeat (2) @(posedge clk);
      @(negedge clk) rst <= 1'b0;
      @(posedge clk);
      if (out_val === 1'bx) begin
        $display("[FATAL] %0t ns: Output X post-reset.", $time);
        $finish;
      end
    end
  endtask

  task expect_val(input exp, input [127:0] tag);
    if (out_val !== exp) begin
      $display("[FAIL] %0t ns | %0s: exp 0b%0b, got 0b%0b", $time, tag, exp, out_val);
      errors = errors + 1;
    end
  endtask

  task test_basic;
    begin
      tests_run = tests_run + 1;
      setup();
      @(negedge clk) in_val <= 1'b1;
      @(posedge clk); #1;
      expect_val(1'b1, "BASIC_RUN");
    end
  endtask

  initial begin
    test_basic();
    if (errors == 0) $display("RESULT: ALL TESTS PASSED! (Tests: %0d)", tests_run);
    else $display("RESULT: TESTBENCH FAILED! Errors: %0d", errors);
    $finish;
  end
endmodule
`default_nettype wire
```
