`timescale 1ns / 1ps
`default_nettype none

/*
 *  Descricao : Testbench auto-verificavel para a logica de prioridade de notas (logica_notas_prioridade).
 *              Conforme padroes de docs/llm/testbench-guide.md.
 *              Valida reset assincrono, prioridade da ultima tecla pressionada (borda de subida),
 *              fallback para a nota ativa de maior indice quando a ultima e solta,
 *              e desativacao de tem_nota ao soltar todas as teclas.
 */

module logica_notas_prioridade_tb;

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
    reg  [6:0] botoes;

    wire [2:0] nota_id;
    wire       tem_nota;

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
    logica_notas_prioridade dut (
        .clock    (clock),
        .reset    (reset),
        .botoes   (botoes),
        .nota_id  (nota_id),
        .tem_nota (tem_nota)
    );

    // -------------------------------------------------------------
    // Watchdog Timer
    // -------------------------------------------------------------
    initial begin
        #WATCHDOG_MAX;
        $display("\n[FATAL] %0t ns: Simulation watchdog timed out in logica_notas_prioridade_tb!", $time);
        $finish;
    end

    // -------------------------------------------------------------
    // Fixtures e Helpers
    // -------------------------------------------------------------
    task setup;
        begin
            botoes <= 7'd0;
            reset  <= 1'b1;
            repeat (2) @(posedge clock);
            @(negedge clock);
            reset  <= 1'b0;
            repeat (2) @(posedge clock);
        end
    endtask

    task expect_nota(
        input [2:0]   exp_id,
        input         exp_tem,
        input [255:0] tag
    );
        begin
            if (nota_id !== exp_id || tem_nota !== exp_tem) begin
                $display("[FAIL] %0t ns | %0s: esperado (id=%0d, tem=%b), obtido (id=%0d, tem=%b)",
                         $time, tag, exp_id, exp_tem, nota_id, tem_nota);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------
    // Casos de Teste Modulares
    // -------------------------------------------------------------
    task test_reset;
        begin
            tests_run = tests_run + 1;
            setup();

            @(negedge clock);
            expect_nota(3'd0, 1'b0, "TESTE_RESET_ESTADO_LIMPO");
        end
    endtask

    task test_teclas_individuais;
        begin
            tests_run = tests_run + 1;
            setup();

            // Pressiona Do (botao 0)
            @(negedge clock);
            botoes <= 7'b0000001;
            @(negedge clock);
            expect_nota(3'd1, 1'b1, "TESTE_PRESSIONA_DO");

            // Solta botao 0
            @(negedge clock);
            botoes <= 7'b0000000;
            #1;
            expect_nota(3'd1, 1'b0, "TESTE_SOLTA_DO_TEM_NOTA_ZERO");

            // Pressiona Si (botao 6)
            @(negedge clock);
            botoes <= 7'b1000000;
            @(negedge clock);
            expect_nota(3'd7, 1'b1, "TESTE_PRESSIONA_SI");

            // Solta botao 6
            @(negedge clock);
            botoes <= 7'b0000000;
            #1;
            expect_nota(3'd7, 1'b0, "TESTE_SOLTA_SI_TEM_NOTA_ZERO");
        end
    endtask

    task test_prioridade_ultima_tecla;
        begin
            tests_run = tests_run + 1;
            setup();

            // Pressiona Do (botao 0) -> nota 1
            @(negedge clock);
            botoes <= 7'b0000001;
            @(negedge clock);
            expect_nota(3'd1, 1'b1, "TESTE_PRIORIDADE_PRIMEIRA_NOTA");

            // Mantem Do pressionado e pressiona Fa (botao 3) -> comuta para nota 4
            @(negedge clock);
            botoes <= 7'b0001001;
            @(negedge clock);
            expect_nota(3'd4, 1'b1, "TESTE_PRIORIDADE_SOBREPOSICAO_FA");

            // Mantem ambos e pressiona Re (botao 1) -> comuta para nota 2
            @(negedge clock);
            botoes <= 7'b0001011;
            @(negedge clock);
            expect_nota(3'd2, 1'b1, "TESTE_PRIORIDADE_SOBREPOSICAO_RE");
        end
    endtask

    task test_fallback_maior_indice;
        begin
            tests_run = tests_run + 1;
            setup();

            // Pressiona Do (0), depois Fa (3), depois Re (1)
            @(negedge clock);
            botoes <= 7'b0000001;
            @(negedge clock);
            botoes <= 7'b0001001;
            @(negedge clock);
            botoes <= 7'b0001011;
            @(negedge clock);
            expect_nota(3'd2, 1'b1, "TESTE_FALLBACK_PRECOND_RE_ATIVO");

            // Solta Re (botao 1). Restam Do (0) e Fa (3).
            // Fallback deve selecionar a de maior indice (Fa = nota 4).
            @(negedge clock);
            botoes <= 7'b0001001;
            @(negedge clock);
            expect_nota(3'd4, 1'b1, "TESTE_FALLBACK_PARA_FA");

            // Solta Fa (botao 3). Resta apenas Do (0).
            // Fallback deve selecionar Do = nota 1.
            @(negedge clock);
            botoes <= 7'b0000001;
            @(negedge clock);
            expect_nota(3'd1, 1'b1, "TESTE_FALLBACK_PARA_DO");

            // Solta todas as teclas
            @(negedge clock);
            botoes <= 7'b0000000;
            #1;
            expect_nota(3'd1, 1'b0, "TESTE_FALLBACK_SOLTA_TUDO");
        end
    endtask

    // -------------------------------------------------------------
    // Runner Principal
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: logica_notas_prioridade_tb");
        $display("========================================");

        test_reset();
        test_teclas_individuais();
        test_prioridade_ultima_tecla();
        test_fallback_maior_indice();

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
