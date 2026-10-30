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
    $display(
      "\n[FATAL] %0t ns: Watchdog da simulacao estourou em tabela_offsets_partituras_tb!",
      $time
    );
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
        $display("[FALHA] %0t ns | %0s: id=%0d, esperado=0x%0h, obtido=0x%0h",
          $time, test_name, id, exp_addr, base_addr);
        errors = errors + 1;
      end else begin
        $display("[SUCESSO] %0s: id=%0d -> base_addr=0x%0h (%0d)",
          test_name, id, base_addr, base_addr);
      end
    end
  endtask

  initial begin
    $display("INICIANDO SIMULACAO: tabela_offsets_partituras_tb");

    // Teste 1: Clair de Lune (Indice 4)
    check_offset(6'd4, 14'd1, "CLAIR_DE_LUNE_OFFSET");

    // Teste 2: Do Re Mi Fa (Indice 6)
    check_offset(6'd6, 14'd799, "DO_RE_MI_FA_OFFSET");

    // Teste 3: Slots nao populados (ex: 0, 1, 5, 38)
    check_offset(6'd0, 14'd0, "AXEL_F_SLOT_VAZIO");
    check_offset(6'd1, 14'd0, "BAD_ROMANCE_SLOT_VAZIO");
    check_offset(6'd5, 14'd0, "CLOCKS_SLOT_VAZIO");
    check_offset(6'd38, 14'd0, "ZELDA_SLOT_VAZIO");

    // Teste 4: Slot 39 (RAM do usuario) e indices fora da faixa
    check_offset(6'd39, 14'd0, "RAM_SLOT_39_OFFSET_ZERO");
    check_offset(6'd63, 14'd0, "FORA_DE_LIMITES_OFFSET_ZERO");

    #10;
    $display("--------------------------------------------------");
    $display("RESUMO DOS TESTES");
    $display("Testes executados: %0d", tests_run);
    $display("Erros encontrados: %0d", errors);
    if (errors == 0) begin
      $display("RESULTADO: TODOS OS TESTES PASSARAM!");
    end else begin
      $display("RESULTADO: TESTBENCH FALHOU com %0d erro(s)!", errors);
    end
    $display("--------------------------------------------------");
    $finish;
  end

endmodule

`default_nettype wire
