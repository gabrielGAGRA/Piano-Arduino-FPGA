`timescale 1ns / 1ps
`default_nettype none

/*
 *  Descricao : Testbench auto-verificavel para a Unidade de Controle do Piano (unidade_controle).
 *              Conforme padroes de docs/llm/testbench-guide.md.
 *              Valida inicializacao e transicoes entre os 4 modos:
 *              0: Livre, 1: Aprendizado, 2: Gravacao, 3: Demonstracao e retorno a Livre.
 *              Checa geracao correta de pulsos de controle: zera_endereco, conta_endereco e escreve_ram.
 */

module unidade_controle_tb;

    // -------------------------------------------------------------
    // Parametros e Constantes
    // -------------------------------------------------------------
    localparam CLK_PERIOD   = 20;     // 50 MHz (20 ns)
    localparam WATCHDOG_MAX = 50_000; // 50 us

    // -------------------------------------------------------------
    // Sinais do DUT
    // -------------------------------------------------------------
    reg        clock;
    reg        reset;

    reg        mudou_modo;
    reg        mudou_musica;
    reg        tem_nota_ativa;
    reg        tecla_pressionada;
    reg        acerto_nota;
    reg        fim_musica;
    reg        pulso_bpm;

    wire [1:0] modo_ativo;
    wire       escreve_ram;
    wire       zera_endereco;
    wire       conta_endereco;
    wire [4:0] estado_hex;

    // Metricas de Teste
    integer errors    = 0;
    integer tests_run = 0;

    // -------------------------------------------------------------
    // Geracao de Clock
    // -------------------------------------------------------------
    initial clock = 1'b0;
    always #(CLK_PERIOD / 2) clock = ~clock;

    // -------------------------------------------------------------
    // Instancia do DUT
    // -------------------------------------------------------------
    unidade_controle dut (
        .clock             (clock),
        .reset             (reset),
        .mudou_modo        (mudou_modo),
        .mudou_musica      (mudou_musica),
        .tem_nota_ativa    (tem_nota_ativa),
        .tecla_pressionada (tecla_pressionada),
        .acerto_nota       (acerto_nota),
        .fim_musica        (fim_musica),
        .pulso_bpm         (pulso_bpm),
        .modo_ativo        (modo_ativo),
        .escreve_ram       (escreve_ram),
        .zera_endereco     (zera_endereco),
        .conta_endereco    (conta_endereco),
        .estado_hex        (estado_hex)
    );

    // -------------------------------------------------------------
    // Watchdog Timer
    // -------------------------------------------------------------
    initial begin
        #WATCHDOG_MAX;
        $display("\n[FATAL] %0t ns: Simulation watchdog timed out in unidade_controle_tb!", $time);
        $finish;
    end

    // -------------------------------------------------------------
    // Fixtures e Helpers
    // -------------------------------------------------------------
    task setup;
        begin
            mudou_modo        <= 1'b0;
            mudou_musica      <= 1'b0;
            tem_nota_ativa    <= 1'b0;
            tecla_pressionada <= 1'b0;
            acerto_nota       <= 1'b0;
            fim_musica        <= 1'b0;
            pulso_bpm         <= 1'b0;
            reset             <= 1'b1;
            repeat (2) @(posedge clock);
            @(negedge clock);
            reset             <= 1'b0;
            repeat (2) @(posedge clock);
        end
    endtask

    task expect_modo_estado(
        input [1:0]   exp_modo,
        input [4:0]   exp_hex,
        input [255:0] tag
    );
        begin
            if (modo_ativo !== exp_modo || estado_hex !== exp_hex) begin
                $display("[FAIL] %0t ns | %0s: esperado (modo=%0d, hex=%0h), obtido (modo=%0d, hex=%0h)",
                         $time, tag, exp_modo, exp_hex, modo_ativo, estado_hex);
                errors = errors + 1;
            end
        end
    endtask

    task expect_flags(
        input         exp_escreve,
        input         exp_zera,
        input         exp_conta,
        input [255:0] tag
    );
        begin
            if (escreve_ram !== exp_escreve || zera_endereco !== exp_zera || conta_endereco !== exp_conta) begin
                $display("[FAIL] %0t ns | %0s: flags esperadas (w=%b, z=%b, c=%b), obtidas (w=%b, z=%b, c=%b)",
                         $time, tag, exp_escreve, exp_zera, exp_conta, escreve_ram, zera_endereco, conta_endereco);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------
    // Casos de Teste Modulares
    // -------------------------------------------------------------
    task test_reset_e_modo_livre;
        begin
            tests_run = tests_run + 1;
            setup();

            @(negedge clock);
            expect_modo_estado(2'd0, 5'h0, "TESTE_LIVRE_MODO_ESTADO");
            expect_flags(1'b0, 1'b1, 1'b0, "TESTE_LIVRE_ZERA_ENDERECO");
        end
    endtask

    task test_modo_aprendizado;
        begin
            tests_run = tests_run + 1;
            setup();

            // Transita para Modo Aprendizado
            @(negedge clock);
            mudou_modo <= 1'b1;

            @(negedge clock);
            mudou_modo <= 1'b0;
            expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_INICIA_MUSICA");
            expect_flags(1'b0, 1'b1, 1'b0, "TESTE_APRENDIZADO_ZERA_END");

            // Avanca para ESPERA_NOTA
            @(negedge clock);
            expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_ESPERA_NOTA");

            // Toca nota (tem_nota_ativa = 1) -> vai para COMPARA_NOTA
            tem_nota_ativa <= 1'b1;
            @(negedge clock);
            expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_COMPARA_NOTA");

            // Acerta a nota -> transita para ESPERA_SOLTAR
            acerto_nota <= 1'b1;
            @(negedge clock);
            acerto_nota <= 1'b0;
            expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_ESPERA_SOLTAR");

            // Solta a nota -> avanca para PROXIMO (com conta_endereco = 1)
            tem_nota_ativa <= 1'b0;
            @(negedge clock);
            expect_flags(1'b0, 1'b0, 1'b1, "TESTE_APRENDIZADO_CONTA_ENDERECO");

            // Avanca por LE_RAM_MODO1 e retorna a ESPERA_NOTA
            @(negedge clock);
            @(negedge clock);
            expect_modo_estado(2'd1, 5'h1, "TESTE_APRENDIZADO_RETORNA_ESPERA_NOTA");
        end
    endtask

    task test_modo_gravacao;
        begin
            tests_run = tests_run + 1;
            setup();

            // Vai para Modo 1 primeiro
            @(negedge clock);
            mudou_modo <= 1'b1;
            repeat (2) @(negedge clock);
            mudou_modo <= 1'b0;

            // De Modo 1 para Modo 2 (Gravacao)
            @(negedge clock);
            mudou_modo <= 1'b1;
            @(negedge clock);
            mudou_modo <= 1'b0;
            expect_modo_estado(2'd2, 5'h2, "TESTE_GRAVACAO_INICIA");
            expect_flags(1'b0, 1'b1, 1'b0, "TESTE_GRAVACAO_ZERA_END");

            // Avanca para GRAV_ESPERA_NOTA
            @(negedge clock);
            expect_modo_estado(2'd2, 5'h2, "TESTE_GRAVACAO_ESPERA_NOTA");

            // Toca nota -> GRAV_SOLTAR (escreve_ram = 0 enquanto segura a tecla)
            tem_nota_ativa <= 1'b1;
            @(negedge clock);
            expect_flags(1'b0, 1'b0, 1'b0, "TESTE_GRAVACAO_SOLTAR_AGUARDA");

            // Solta nota -> GRAV_ARMAZENA (escreve_ram = 1)
            tem_nota_ativa <= 1'b0;
            @(negedge clock);
            expect_flags(1'b1, 1'b0, 1'b0, "TESTE_GRAVACAO_ESCREVE_RAM");

            // Proximo estado: GRAV_PROXIMO (conta_endereco = 1)
            @(negedge clock);
            expect_flags(1'b0, 1'b0, 1'b1, "TESTE_GRAVACAO_CONTA_END");

            // Retorna para GRAV_ESPERA_NOTA
            @(negedge clock);
            expect_modo_estado(2'd2, 5'h2, "TESTE_GRAVACAO_RETORNA_ESPERA");
            expect_flags(1'b0, 1'b0, 1'b0, "TESTE_GRAVACAO_RETORNA_ESPERA_FLAGS");
        end
    endtask

    task test_modo_demo_e_retorno_livre;
        begin
            tests_run = tests_run + 1;
            setup();

            // Navega ate Gravacao
            @(negedge clock);
            mudou_modo <= 1'b1;
            repeat (3) @(negedge clock); // Transita por Modo 1 e vai para Modo 2
            mudou_modo <= 1'b0;

            // De Gravacao para Demonstracao (Modo 3)
            @(negedge clock);
            mudou_modo <= 1'b1;
            @(negedge clock);
            mudou_modo <= 1'b0;
            expect_modo_estado(2'd3, 5'h3, "TESTE_DEMO_INICIA");
            expect_flags(1'b0, 1'b1, 1'b0, "TESTE_DEMO_ZERA_END");

            // Toca tecla para iniciar playback demo
            tecla_pressionada <= 1'b1;
            @(negedge clock);
            tecla_pressionada <= 1'b0;
            expect_modo_estado(2'd3, 5'h3, "TESTE_DEMO_TOCA_NOTA");

            // Pulso BPM avanca endereco no sequenciador
            pulso_bpm <= 1'b1;
            @(negedge clock);
            pulso_bpm <= 1'b0;
            expect_flags(1'b0, 1'b0, 1'b1, "TESTE_DEMO_CONTA_ENDERECO");

            // Retorna ao modo 0 (Livre)
            @(negedge clock);
            mudou_modo <= 1'b1;
            @(negedge clock);
            mudou_modo <= 1'b0;
            expect_modo_estado(2'd0, 5'h0, "TESTE_DEMO_RETORNA_LIVRE");
        end
    endtask

    // -------------------------------------------------------------
    // Runner Principal
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: unidade_controle_tb");
        $display("========================================");

        test_reset_e_modo_livre();
        test_modo_aprendizado();
        test_modo_gravacao();
        test_modo_demo_e_retorno_livre();

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
