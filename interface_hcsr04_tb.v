/*
 *  Descricao : Testbench auto-verificavel para interface_hcsr04.
 */

`timescale 1ns / 1ps
`default_nettype none

module interface_hcsr04_tb;
  localparam ClkPeriodNs  = 20;
  localparam WatchdogNs   = 50000;
  localparam TriggerTicks = 10;
  localparam TickCmModulo = 10;
  localparam TimeoutTicks = 200;
  localparam TimeoutBits  = 8;

  reg         clk;
  reg         arst;
  reg         medir;
  reg         echo;
  wire        trigger;
  wire [11:0] medida;
  wire        pronto;
  wire        db_reset;
  wire        db_medir;
  wire [3:0]  db_estado;

  integer errors = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  interface_hcsr04 #(
    .TriggerTicks(TriggerTicks),
    .TickCmModulo(TickCmModulo),
    .TimeoutTicks(TimeoutTicks),
    .TimeoutBits (TimeoutBits)
  ) dut (
    .clk      (clk),
    .arst     (arst),
    .medir    (medir),
    .echo     (echo),
    .trigger  (trigger),
    .medida   (medida),
    .pronto   (pronto),
    .db_reset (db_reset),
    .db_medir (db_medir),
    .db_estado(db_estado)
  );

  // Watchdog obrigatorio
  initial begin
    #WatchdogNs;
    $display("[FATAL] %0t ns: Watchdog timeout - simulation deadlocked.", $time);
    $finish;
  end

  task setup;
    begin
      arst  <= 1'b1;
      medir <= 1'b0;
      echo  <= 1'b0;
      repeat (2) @(posedge clk);
      @(negedge clk) arst <= 1'b0;
      @(posedge clk);
      #1;
      if (trigger === 1'bx || pronto === 1'bx || medida === 12'hxxx) begin
        $display("[FATAL] %0t ns: Output X post-reset.", $time);
        $finish;
      end
    end
  endtask

  task expect_medida(input [11:0] exp, input [191:0] tag);
    begin
      if (medida !== exp) begin
        $display("[FAIL] %0t ns | %0s: exp 0x%0h, got 0x%0h", $time, tag, exp, medida);
        errors = errors + 1;
      end
    end
  endtask

  task expect_bit(input exp, input actual, input [191:0] tag);
    begin
      if (actual !== exp) begin
        $display("[FAIL] %0t ns | %0s: exp 0b%0b, got 0b%0b", $time, tag, exp, actual);
        errors = errors + 1;
      end
    end
  endtask

  task test_medida_normal;
    integer cycles;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk) medir <= 1'b1;
      @(posedge clk);
      @(negedge clk) medir <= 1'b0;

      // Aguarda pulso de trigger
      wait (trigger === 1'b1);
      @(posedge clk);
      #1;
      expect_bit(1'b1, trigger, "TRIGGER_ACTIVE");

      repeat (TriggerTicks + 1) @(posedge clk);
      #1;
      expect_bit(1'b0, trigger, "TRIGGER_DONE");

      // Simula eco correspondente a 2 cm (2 * TickCmModulo ciclos)
      @(negedge clk) echo <= 1'b1;
      repeat (2 * TickCmModulo + 1) @(posedge clk);
      @(negedge clk) echo <= 1'b0;

      cycles = 0;
      while (pronto !== 1'b1 && cycles < 50) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
      end
      expect_bit(1'b1, pronto, "PRONTO_NORMAL");
      expect_medida(12'h002, "MEDIDA_2CM");
    end
  endtask

  task test_timeout_sem_echo;
    integer cycles;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk) medir <= 1'b1;
      @(posedge clk);
      @(negedge clk) medir <= 1'b0;

      cycles = 0;
      while (pronto !== 1'b1 && cycles < (TimeoutTicks + 20)) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
      end
      expect_bit(1'b1, pronto, "PRONTO_TIMEOUT_NO_ECHO");
      expect_medida(12'h999, "MEDIDA_TIMEOUT_NO_ECHO");
    end
  endtask

  task test_timeout_durante_echo;
    integer cycles;
    begin
      tests_run = tests_run + 1;
      setup();

      @(negedge clk) medir <= 1'b1;
      @(posedge clk);
      @(negedge clk) medir <= 1'b0;

      wait (trigger === 1'b1);
      repeat (TriggerTicks + 1) @(posedge clk);
      @(negedge clk) echo <= 1'b1;

      cycles = 0;
      while (pronto !== 1'b1 && cycles < (TimeoutTicks + 20)) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
      end
      @(negedge clk) echo <= 1'b0;

      expect_bit(1'b1, pronto, "PRONTO_TIMEOUT_ECHO");
      expect_medida(12'h999, "MEDIDA_TIMEOUT_ECHO");
    end
  endtask

  initial begin
    test_medida_normal();
    test_timeout_sem_echo();
    test_timeout_durante_echo();

    if (errors == 0) begin
      $display("RESULT: ALL TESTS PASSED! (Tests: %0d)", tests_run);
    end else begin
      $display("RESULT: TESTBENCH FAILED! Errors: %0d", errors);
    end
    $finish;
  end

endmodule

`default_nettype wire
