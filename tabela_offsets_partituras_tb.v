// Descricao: Testbench auto-verificavel para tabela_offsets_partituras.
// Funcionamento: Valida a resolucao correta dos enderecos base para cada indice de musica.

`timescale 1ns / 1ps
`default_nettype none

module tabela_offsets_partituras_tb;

  localparam AddrWidth     = 14;
  localparam WatchdogMaxNs = 10000;

  reg  [5:0]           musica_id;
  wire [AddrWidth-1:0] base_addr;

  integer errors    = 0;
  integer tests_run = 0;

  tabela_offsets_partituras #(
    .AddrWidth(AddrWidth)
  ) tabela_offsets_partituras_inst (
    .musica_id(musica_id),
    .base_addr(base_addr)
  );

  initial begin
    #WatchdogMaxNs;
    $display("\n[FATAL] %0t ns: Simulation watchdog timed out!", $time);
    $finish;
  end

  task check_offset(
    input [5:0]           id,
    input [AddrWidth-1:0] exp_addr,
    input [255:0]         test_name
  );
    begin
      tests_run = tests_run + 1;
      musica_id = id;
      #10;
      if (base_addr !== exp_addr) begin
        $display("[FAIL] %0t ns | %0s: id=%0d, exp=0x%0h, got=0x%0h",
          $time, test_name, id, exp_addr, base_addr);
        errors = errors + 1;
      end else begin
        $display("[PASS] %0s: id=%0d -> base_addr=0x%0h (%0d)",
          test_name, id, base_addr, base_addr);
      end
    end
  endtask

  initial begin
    $display("STARTING SIMULATION: tabela_offsets_partituras_tb");

    // Teste 1: Clair de Lune (Indice 4)
    check_offset(6'd4, 14'd1, "CLAIR_DE_LUNE_OFFSET");

    // Teste 2: Do Re Mi Fa (Indice 6)
    check_offset(6'd6, 14'd799, "DO_RE_MI_FA_OFFSET");

    // Teste 3: Slots nao populados (ex: 0, 1, 5, 38)
    check_offset(6'd0, 14'd0, "AXEL_F_EMPTY_SLOT");
    check_offset(6'd1, 14'd0, "BAD_ROMANCE_EMPTY_SLOT");
    check_offset(6'd5, 14'd0, "CLOCKS_EMPTY_SLOT");
    check_offset(6'd38, 14'd0, "ZELDA_EMPTY_SLOT");

    // Teste 4: Slot 39 (RAM do usuario) e indices fora da faixa
    check_offset(6'd39, 14'd0, "RAM_SLOT_39_OFFSET_ZERO");
    check_offset(6'd63, 14'd0, "OUT_OF_BOUNDS_OFFSET_ZERO");

    #10;
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
