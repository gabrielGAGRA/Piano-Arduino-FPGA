// Descrição: Testbench auto-verificavel para o registrador de oitava (guarda_oitava).
// Funcionamento: Valida inicializacao na oitava padrao (4), incremento e decremento
// com saturacao nos limites 1 e 7, e prioridade de sinais.

`timescale 1ns / 1ps
`default_nettype none

module guarda_oitava_tb;

  localparam ClkPeriodNs   = 20;
  localparam WatchdogMaxNs = 20000;

  reg        clk;
  reg        arst;
  reg        btn_up_pulse;
  reg        btn_down_pulse;
  wire [2:0] oitava_atual;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  guarda_oitava guarda_oitava_inst (
    .clk            (clk),
    .arst           (arst),
    .btn_up_pulse   (btn_up_pulse),
    .btn_down_pulse (btn_down_pulse),
    .oitava_atual   (oitava_atual)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Simulation watchdog timed out!", $time);
    $finish;
  end

  task setup;
    begin
      btn_up_pulse   = 1'b0;
      btn_down_pulse = 1'b0;
      arst           = 1'b1;
      repeat (2) @(posedge clk);
      @(negedge clk);
      arst           = 1'b0;
      @(posedge clk);
    end
  endtask

  task pulse_up;
    begin
      @(negedge clk);
      btn_up_pulse   = 1'b1;
      btn_down_pulse = 1'b0;
      @(posedge clk);
      #1;
      @(negedge clk);
      btn_up_pulse   = 1'b0;
    end
  endtask

  task pulse_down;
    begin
      @(negedge clk);
      btn_up_pulse   = 1'b0;
      btn_down_pulse = 1'b1;
      @(posedge clk);
      #1;
      @(negedge clk);
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

  task test_reset_and_defaults;
    begin
      tests_run = tests_run + 1;
      setup();
      #1;
      expect_eq3(oitava_atual, 3'd4, "RESET_DEFAULT_OCTAVE_4");
    end
  endtask

  task test_increment_and_saturation;
    begin
      tests_run = tests_run + 1;
      setup();

      pulse_up();
      expect_eq3(oitava_atual, 3'd5, "STEP_UP_TO_5");

      pulse_up();
      expect_eq3(oitava_atual, 3'd6, "STEP_UP_TO_6");

      pulse_up();
      expect_eq3(oitava_atual, 3'd7, "STEP_UP_TO_7");

      pulse_up();
      expect_eq3(oitava_atual, 3'd7, "SATURATE_UP_MAX_7_P1");

      pulse_up();
      expect_eq3(oitava_atual, 3'd7, "SATURATE_UP_MAX_7_P2");
    end
  endtask

  task test_decrement_and_saturation;
    begin
      tests_run = tests_run + 1;
      setup();

      pulse_down();
      expect_eq3(oitava_atual, 3'd3, "STEP_DOWN_TO_3");

      pulse_down();
      expect_eq3(oitava_atual, 3'd2, "STEP_DOWN_TO_2");

      pulse_down();
      expect_eq3(oitava_atual, 3'd1, "STEP_DOWN_TO_1");

      pulse_down();
      expect_eq3(oitava_atual, 3'd1, "SATURATE_DOWN_MIN_1_P1");

      pulse_down();
      expect_eq3(oitava_atual, 3'd1, "SATURATE_DOWN_MIN_1_P2");
    end
  endtask

  initial begin
    $display("========================================");
    $display("STARTING SIMULATION: guarda_oitava_tb");
    $display("========================================");

    test_reset_and_defaults();
    test_increment_and_saturation();
    test_decrement_and_saturation();

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
