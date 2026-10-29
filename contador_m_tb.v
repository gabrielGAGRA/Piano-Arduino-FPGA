`timescale 1ns / 1ps
`default_nettype none

/*
 *  Descricao : Testbench auto-verificavel para o contador parametrizavel (contador_m).
 *              Conforme padroes de docs/llm/testbench-guide.md.
 *              Valida reset assincrono, contagem progressiva, deteccao de meio e fim,
 *              wrap-around, clear sincrono (sclr) e inibicao de contagem.
 */

module contador_m_tb;

    // -------------------------------------------------------------
    // Parametros e Constantes
    // -------------------------------------------------------------
    localparam CLK_PERIOD   = 20;     // 50 MHz (20 ns)
    localparam WATCHDOG_MAX = 50_000; // 50 us
    localparam TEST_M       = 8;      // Modulo 8 para simulacao rapida
    localparam TEST_N       = 4;      // 4 bits suficientes para contar ate 8

    // -------------------------------------------------------------
    // Sinais do DUT
    // -------------------------------------------------------------
    reg               clock;
    reg               reset;
    reg               sclr;
    reg               conta;

    wire [TEST_N-1:0] q;
    wire              fim;
    wire              meio;

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
    contador_m #(
        .M(TEST_M),
        .N(TEST_N)
    ) dut (
        .clock (clock),
        .reset (reset),
        .sclr  (sclr),
        .conta (conta),
        .q     (q),
        .fim   (fim),
        .meio  (meio)
    );

    // -------------------------------------------------------------
    // Watchdog Timer
    // -------------------------------------------------------------
    initial begin
        #WATCHDOG_MAX;
        $display("\n[FATAL] %0t ns: Simulation watchdog timed out in contador_m_tb!", $time);
        $finish;
    end

    // -------------------------------------------------------------
    // Fixtures e Helpers
    // -------------------------------------------------------------
    task setup;
        begin
            sclr  <= 1'b0;
            conta <= 1'b0;
            reset <= 1'b1;
            repeat (2) @(posedge clock);
            @(negedge clock);
            reset <= 1'b0;
            repeat (2) @(posedge clock);
        end
    endtask

    task expect_eq4(
        input [TEST_N-1:0] actual,
        input [TEST_N-1:0] expected,
        input [255:0]      test_tag
    );
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0t ns | %0s: esperado %0d, obtido %0d",
                         $time, test_tag, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task expect_flag(
        input         actual,
        input         expected,
        input [255:0] test_tag
    );
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0t ns | %0s: esperado %b, obtido %b",
                         $time, test_tag, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task assert_true(
        input         cond,
        input [255:0] fatal_tag
    );
        begin
            if (!cond) begin
                $display("[FATAL ASSERTION] %0t ns | %0s falhou. Abortando simulacao.", $time, fatal_tag);
                $finish;
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
            expect_eq4(q, 4'd0, "TESTE_RESET_Q");
            expect_flag(fim, 1'b0, "TESTE_RESET_FIM");
            expect_flag(meio, 1'b0, "TESTE_RESET_MEIO");
        end
    endtask

    task test_contagem_e_flags;
        integer i;
        begin
            tests_run = tests_run + 1;
            setup();

            @(negedge clock);
            expect_eq4(q, 4'd0, "TESTE_CONTA_INICIAL");
            conta <= 1'b1;

            // Percorre incrementos de 1 ate TEST_M - 1 (1 ate 7)
            for (i = 1; i < TEST_M; i = i + 1) begin
                @(negedge clock);
                expect_eq4(q, i[TEST_N-1:0], "TESTE_CONTA_PASSO");

                // Meio ocorre em (M/2) - 1 = 3
                if (i == 3) begin
                    expect_flag(meio, 1'b1, "TESTE_FLAG_MEIO_ATIVO");
                end else begin
                    expect_flag(meio, 1'b0, "TESTE_FLAG_MEIO_INATIVO");
                end

                // Fim ocorre em M - 1 = 7
                if (i == 7) begin
                    expect_flag(fim, 1'b1, "TESTE_FLAG_FIM_ATIVO");
                end else begin
                    expect_flag(fim, 1'b0, "TESTE_FLAG_FIM_INATIVO");
                end
            end

            // Apos o valor maximo (7), no proximo clock com conta=1 deve reiniciar em 0
            @(negedge clock);
            expect_eq4(q, 4'd0, "TESTE_WRAPAROUND_Q");
            expect_flag(fim, 1'b0, "TESTE_WRAPAROUND_FIM");

            conta <= 1'b0;
        end
    endtask

    task test_sclr;
        begin
            tests_run = tests_run + 1;
            setup();

            @(negedge clock);
            conta <= 1'b1;
            repeat (3) @(negedge clock); // q atinge 3

            expect_eq4(q, 4'd3, "TESTE_SCLR_PRECOND");
            sclr <= 1'b1; // sclr ativo simultaneo com conta

            @(negedge clock);
            expect_eq4(q, 4'd0, "TESTE_SCLR_PRIORIDADE_SOBRE_CONTA");

            sclr  <= 1'b0;
            conta <= 1'b0;
        end
    endtask

    task test_inibe_conta;
        begin
            tests_run = tests_run + 1;
            setup();

            @(negedge clock);
            conta <= 1'b1;
            repeat (2) @(negedge clock); // q atinge 2

            expect_eq4(q, 4'd2, "TESTE_INIBE_PRECOND");
            conta <= 1'b0; // Desabilita contagem

            repeat (3) @(negedge clock);
            expect_eq4(q, 4'd2, "TESTE_INIBE_VALOR_ESTATICO");
        end
    endtask

    // -------------------------------------------------------------
    // Runner Principal
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: contador_m_tb");
        $display("========================================");

        test_reset();
        test_contagem_e_flags();
        test_sclr();
        test_inibe_conta();

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
