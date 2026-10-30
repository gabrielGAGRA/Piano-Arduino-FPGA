// Descricao: Testbench auto-verificavel para a memoria ROM sincrona (sync_rom).
// Funcionamento: Valida leitura sincrona em posicoes-chave da Mega-ROM em hexadecimal.

`timescale 1ns / 1ps
`default_nettype none

module sync_rom_tb;

  localparam ClkPeriodNs   = 20;
  localparam DataWidth     = 30;
  localparam AddrWidth     = 14;
  localparam WatchdogMaxNs = 10000;

  reg                  clk;
  reg  [AddrWidth-1:0] address;
  wire [DataWidth-1:0] data_out;

  integer errors    = 0;
  integer tests_run = 0;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  sync_rom #(
    .DataWidth(DataWidth),
    .AddrWidth(AddrWidth),
    .InitFile ("music/partituras.hex"),
    .HexMode  (1)
  ) sync_rom_inst (
    .clk     (clk),
    .address (address),
    .data_out(data_out)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Simulation watchdog timed out!", $time);
    $finish;
  end

  task read_and_verify(
    input [AddrWidth-1:0] addr,
    input [DataWidth-1:0] exp_data,
    input                 check_exact,
    input [255:0]         test_name
  );
    begin
      tests_run = tests_run + 1;
      @(negedge clk);
      address = addr;
      @(posedge clk);
      #1; // Espera saida do registrador
      if (check_exact) begin
        if (data_out !== exp_data) begin
          $display("[FAIL] %0t ns | %0s: addr=%0d, exp=0x%0h, got=0x%0h",
            $time, test_name, addr, exp_data, data_out);
          errors = errors + 1;
        end else begin
          $display("[PASS] %0s: addr=%0d -> data=0x%0h", test_name, addr, data_out);
        end
      end else begin
        // Apenas verifica se a nota nao eh zero
        if (data_out[6:0] == 7'd0) begin
          $display("[FAIL] %0t ns | %0s: addr=%0d nota esperada nao nula, got 0",
            $time, test_name, addr);
          errors = errors + 1;
        end else begin
          $display("[PASS] %0s: addr=%0d -> nota=%0d, data=0x%0h",
            test_name, addr, data_out[6:0], data_out);
        end
      end
    end
  endtask

  initial begin
    $display("STARTING SIMULATION: sync_rom_tb");

    address = {AddrWidth{1'b0}};
    repeat (2) @(posedge clk);

    // Teste 1: Endereco 0 deve ser sentinela nulo (30'h0)
    read_and_verify(14'd0, 30'h0, 1'b1, "ADDR_0_SENTINEL_ZERO");

    // Teste 2: Endereco 1 (Primeira nota de Clair de Lune) deve ser nota valida
    read_and_verify(14'd1, 30'h0, 1'b0, "CLAIR_DE_LUNE_FIRST_NOTE");

    // Teste 3: Endereco 798 (Sentinela ao final de Clair de Lune)
    read_and_verify(14'd798, 30'h0, 1'b1, "CLAIR_DE_LUNE_SENTINEL_ZERO");

    // Teste 4: Endereco 799 (Primeira nota de Do Re Mi Fa) - Nota MIDI 60 (Do)
    // pausa=5, dur=40, vel=100, note=60 -> 0x014a323c
    read_and_verify(14'd799, 30'h0, 1'b0, "DO_RE_MI_FA_FIRST_NOTE");

    // Teste 5: Endereco 805 (Ultima nota da escala Do Re Mi Fa) - Nota MIDI 71
    read_and_verify(14'd805, 30'h0, 1'b0, "DO_RE_MI_FA_LAST_NOTE");

    // Teste 6: Endereco 806 (Sentinela ao final de Do Re Mi Fa)
    read_and_verify(14'd806, 30'h0, 1'b1, "DO_RE_MI_FA_SENTINEL_ZERO");

    // Teste 7: Endereco alem do conteudo (pre-inicializado com zeros)
    read_and_verify(14'd1000, 30'h0, 1'b1, "UNPOPULATED_ADDR_ZERO");

    #20;
    $display("--------------------------------------------------");
    if (errors == 0) begin
      $display("RESULT: ALL %0d TESTS PASSED SUCCESSFULLY!", tests_run);
    end else begin
      $display("RESULT: FAILED WITH %0d ERRORS!", errors);
    end
    $display("--------------------------------------------------");
    $finish;
  end

endmodule

`default_nettype wire
