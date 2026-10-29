`timescale 1ns / 1ps
`default_nettype none

/* 
 *  Descricao : Testbench auto-verificavel para o subsistema metronomo (metronomo_tb).
 *              Verifica repouso inicial, varredura angular suave com beats nos extremos
 *              e retorno ao centro apos desabilitacao.
 */

module metronomo_tb;

    // -------------------------------------------------------------
    // Constantes e Parametros
    // -------------------------------------------------------------
    localparam CLK_PERIOD   = 20;      // 50 MHz (20 ns)
    localparam SIM_TPASSO   = 20;      // 20 ciclos de clock por passo angular
    localparam WATCHDOG_MAX = 100_000; // 100 us de limite de seguranca

    // -------------------------------------------------------------
    // Sinais do DUT
    // -------------------------------------------------------------
    reg         clock;
    reg         reset;
    reg         habilita;
    reg  [31:0] t_passo;

    wire        servo_controle;
    wire        pulso_beat;
    wire [2:0]  posicao_servo;

    // Metricas de Teste
    integer errors    = 0;
    integer tests_run = 0;
    integer beat_count = 0;
    reg     beat_err   = 1'b0;

    // -------------------------------------------------------------
    // Geracao de Clock Deterministica
    // -------------------------------------------------------------
    initial clock = 1'b0;
    always #(CLK_PERIOD / 2) clock = ~clock;

    // -------------------------------------------------------------
    // Instancia do DUT
    // -------------------------------------------------------------
    metronomo #(
        .CLOCK_FREQ(50_000) // Base reduzida para simulacao rapida
    ) dut (
        .clock         (clock),
        .reset         (reset),
        .habilita      (habilita),
        .t_passo       (t_passo),
        .servo_controle(servo_controle),
        .pulso_beat    (pulso_beat),
        .posicao_servo (posicao_servo)
    );

    // -------------------------------------------------------------
    // Watchdog Timer (Prevencao contra Deadlock)
    // -------------------------------------------------------------
    initial begin
        #WATCHDOG_MAX;
        $display("\n[FATAL] %0t ns: Simulation watchdog timed out! Potential deadlock in metronomo_tb.", $time);
        $finish;
    end

    // -------------------------------------------------------------
    // Monitor de Beats
    // -------------------------------------------------------------
    always @(posedge clock) begin
        if (reset) begin
            beat_count <= 0;
            beat_err   <= 1'b0;
        end else if (pulso_beat) begin
            beat_count <= beat_count + 1;
            if (posicao_servo !== 3'd0 && posicao_servo !== 3'd7) begin
                $display("[FAIL] %0t ns | BEAT_EXTREMO: pulso fora de extremo! Posicao: %0d",
                         $time, posicao_servo);
                beat_err <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------
    // Helpers e Fixtures
    // -------------------------------------------------------------
    task setup;
        begin
            habilita <= 1'b0;
            t_passo  <= SIM_TPASSO;
            reset    <= 1'b1;
            repeat (3) @(posedge clock);
            @(negedge clock);
            reset    <= 1'b0;
            repeat (2) @(posedge clock);
        end
    endtask

    task expect_eq3(
        input [2:0] actual,
        input [2:0] expected,
        input [127:0] test_tag
    );
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0t ns | %0s: esperado 3'd%0d, obtido 3'd%0d",
                         $time, test_tag, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task expect_true(
        input cond,
        input [127:0] test_tag
    );
        begin
            if (!cond) begin
                $display("[FAIL] %0t ns | %0s: condicao esperada VERDADEIRA, obtida FALSA",
                         $time, test_tag);
                errors = errors + 1;
            end
        end
    endtask

    task assert_true(
        input cond,
        input [127:0] fatal_tag
    );
        begin
            if (!cond) begin
                $display("[FATAL ASSERTION] %0t ns | %0s failed. Aborting simulation.", $time, fatal_tag);
                $finish;
            end
        end
    endtask

    // -------------------------------------------------------------
    // Casos de Teste Modulares
    // -------------------------------------------------------------
    task test_repouso;
        begin
            tests_run = tests_run + 1;
            setup();

            @(negedge clock);
            expect_eq3(posicao_servo, 3'd3, "TESTE_REPOUSO_CENTRO");
        end
    endtask

    task test_varredura_e_beats;
        integer timeout_cnt;
        begin
            tests_run = tests_run + 1;
            setup();

            @(negedge clock);
            habilita <= 1'b1;

            // Aguarda 1o beat (extremo direito, posicao 7)
            timeout_cnt = 0;
            while (beat_count < 1 && timeout_cnt < 200) begin
                @(posedge clock);
                timeout_cnt = timeout_cnt + 1;
            end
            assert_true(beat_count >= 1, "TESTE_BEAT1_DIR");

            // Aguarda 2o beat (extremo esquerdo, posicao 0)
            timeout_cnt = 0;
            while (beat_count < 2 && timeout_cnt < 300) begin
                @(posedge clock);
                timeout_cnt = timeout_cnt + 1;
            end
            assert_true(beat_count >= 2, "TESTE_BEAT2_ESQ");

            // Aguarda 3o beat (retorno ao extremo direito, posicao 7)
            timeout_cnt = 0;
            while (beat_count < 3 && timeout_cnt < 300) begin
                @(posedge clock);
                timeout_cnt = timeout_cnt + 1;
            end
            assert_true(beat_count >= 3, "TESTE_BEAT3_DIR");
            expect_true(!beat_err, "TESTE_BEAT_POSICAO_EXTREMO");
        end
    endtask

    task test_desabilitacao;
        begin
            tests_run = tests_run + 1;
            setup();

            @(negedge clock);
            habilita <= 1'b1;
            repeat (50) @(posedge clock); // Permite transitar para movimento

            @(negedge clock);
            habilita <= 1'b0;             // Desabilita no meio do percurso
            repeat (3) @(posedge clock);

            @(negedge clock);
            expect_eq3(posicao_servo, 3'd3, "TESTE_DESAB_RETORNO_CENTRO");
        end
    endtask

    // -------------------------------------------------------------
    // Runner Principal
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: metronomo_tb");
        $display("========================================");

        test_repouso();
        test_varredura_e_beats();
        test_desabilitacao();

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
