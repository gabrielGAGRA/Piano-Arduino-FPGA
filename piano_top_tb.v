`timescale 1ns / 1ps
`default_nettype none

/*
 * Descricao : Testbench auto-verificavel de integracao para piano_top.
 *             Valida:
 *             1. Modo Livre: envio de Note On (0x90, 60, 127) e Note Off (0x80, 60, 0) via saida_serial.
 *             2. Modo Gravacao + Modo Demonstracao: gravacao de nota na RAM com duracao medida
 *                e reproducao automatica (Note On seguido de Note Off) na saida_serial.
 */
module piano_top_tb;

    // -------------------------------------------------------------
    // Parametros Acelerados de Simulacao
    // -------------------------------------------------------------
    localparam CLK_PERIOD        = 20;
    localparam DEBOUNCE_TECLA    = 4;
    localparam DEBOUNCE_CONTROLE = 4;
    localparam CLOCK_DIV_UART    = 2;
    localparam CICLOS_TICK_8MS   = 60;
    localparam WATCHDOG_MAX      = 4_000_000;

    // -------------------------------------------------------------
    // Sinais do DUT
    // -------------------------------------------------------------
    reg        CLOCK_50;
    reg        reset_n;
    reg  [6:0] gpio_keys;
    reg        btn_modo_n;
    reg        btn_musica_n;
    reg        btn_intensidade_n;
    reg        btn_oitava_up_n;
    reg        btn_oitava_down_n;
    reg        btn_sustenido;

    wire       saida_serial;
    wire       servo_controle;
    wire [6:0] led_vermelho;
    wire       led_sustenido;
    wire       led_oitava_up;
    wire       led_oitava_down;
    wire [6:0] hex5_modo;
    wire [6:0] hex4_oitava;
    wire [6:0] hex3_musica_dezena;
    wire [6:0] hex2_musica_unidade;
    wire [6:0] hex1_nota;
    wire [6:0] hex0_sustenido;

    integer errors    = 0;
    integer tests_run = 0;

    // -------------------------------------------------------------
    // Geracao de Clock (50 MHz)
    // -------------------------------------------------------------
    initial CLOCK_50 = 1'b0;
    always #(CLK_PERIOD / 2) CLOCK_50 = ~CLOCK_50;

    // -------------------------------------------------------------
    // Instancia do DUT (piano_top)
    // -------------------------------------------------------------
    piano_top #(
        .DEBOUNCE_TECLA    (DEBOUNCE_TECLA),
        .DEBOUNCE_CONTROLE (DEBOUNCE_CONTROLE),
        .CLOCK_DIV_UART    (CLOCK_DIV_UART),
        .CICLOS_TICK_8MS   (CICLOS_TICK_8MS)
    ) dut (
        .CLOCK_50            (CLOCK_50),
        .reset_n             (reset_n),
        .gpio_keys           (gpio_keys),
        .btn_modo_n          (btn_modo_n),
        .btn_musica_n        (btn_musica_n),
        .btn_intensidade_n   (btn_intensidade_n),
        .btn_oitava_up_n     (btn_oitava_up_n),
        .btn_oitava_down_n   (btn_oitava_down_n),
        .btn_sustenido       (btn_sustenido),
        .saida_serial        (saida_serial),
        .servo_controle      (servo_controle),
        .led_vermelho        (led_vermelho),
        .led_sustenido       (led_sustenido),
        .led_oitava_up       (led_oitava_up),
        .led_oitava_down     (led_oitava_down),
        .hex5_modo           (hex5_modo),
        .hex4_oitava         (hex4_oitava),
        .hex3_musica_dezena  (hex3_musica_dezena),
        .hex2_musica_unidade (hex2_musica_unidade),
        .hex1_nota           (hex1_nota),
        .hex0_sustenido      (hex0_sustenido)
    );

    // -------------------------------------------------------------
    // Watchdog Timer
    // -------------------------------------------------------------
    initial begin
        #WATCHDOG_MAX;
        $display("\n[FATAL] %0t ns: Simulation watchdog timed out in piano_top_tb!", $time);
        $finish;
    end

    // -------------------------------------------------------------
    // Helpers de Estimulo e Verificacao Serial
    // -------------------------------------------------------------
    task setup;
        begin
            gpio_keys         <= 7'b0000000;
            btn_modo_n        <= 1'b1;
            btn_musica_n      <= 1'b1;
            btn_intensidade_n <= 1'b1;
            btn_oitava_up_n   <= 1'b1;
            btn_oitava_down_n <= 1'b1;
            btn_sustenido     <= 1'b0;
            reset_n           <= 1'b0;
            repeat (4) @(posedge CLOCK_50);
            @(negedge CLOCK_50);
            reset_n           <= 1'b1;
            repeat (6) @(posedge CLOCK_50);
        end
    endtask

    task press_btn_modo;
        begin
            @(negedge CLOCK_50);
            btn_modo_n <= 1'b0;
            repeat (DEBOUNCE_CONTROLE + 3) @(posedge CLOCK_50);
            @(negedge CLOCK_50);
            btn_modo_n <= 1'b1;
            repeat (DEBOUNCE_CONTROLE + 3) @(posedge CLOCK_50);
        end
    endtask

    task press_btn_musica;
        begin
            @(negedge CLOCK_50);
            btn_musica_n <= 1'b0;
            repeat (DEBOUNCE_CONTROLE + 3) @(posedge CLOCK_50);
            @(negedge CLOCK_50);
            btn_musica_n <= 1'b1;
            repeat (DEBOUNCE_CONTROLE + 3) @(posedge CLOCK_50);
        end
    endtask

    task receive_uart_byte(
        output [7:0] rx_byte
    );
        integer bit_idx;
        begin
            @(negedge saida_serial);
            repeat (CLOCK_DIV_UART / 2) @(posedge CLOCK_50);
            #1;
            if (saida_serial !== 1'b0) begin
                $display("[FAIL] %0t ns | UART start bit error: expected 0, got %b", $time, saida_serial);
                errors = errors + 1;
            end
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                repeat (CLOCK_DIV_UART) @(posedge CLOCK_50);
                #1;
                rx_byte[bit_idx] = saida_serial;
            end
            repeat (CLOCK_DIV_UART) @(posedge CLOCK_50);
            #1;
            if (saida_serial !== 1'b1) begin
                $display("[FAIL] %0t ns | UART stop bit error: expected 1, got %b", $time, saida_serial);
                errors = errors + 1;
            end
        end
    endtask

    task receive_and_verify_midi_packet(
        input [23:0]  expected_packet,
        input [255:0] test_tag
    );
        reg [7:0]  b0;
        reg [7:0]  b1;
        reg [7:0]  b2;
        reg [23:0] actual_packet;
        begin
            receive_uart_byte(b0);
            receive_uart_byte(b1);
            receive_uart_byte(b2);
            actual_packet = {b0, b1, b2};
            if (actual_packet !== expected_packet) begin
                $display("[FAIL] %0t ns | %0s: expected 24'h%06h, got 24'h%06h",
                         $time, test_tag, expected_packet, actual_packet);
                errors = errors + 1;
            end
        end
    endtask

    // -------------------------------------------------------------
    // Casos de Teste
    // -------------------------------------------------------------
    task test_modo_livre_midi;
        begin
            tests_run = tests_run + 1;
            setup();

            // Pressiona tecla Do (gpio_keys = 7'b0000001) na oitava padrao 4 -> MIDI 60 (8'h3C), Vel 127 (8'h7F)
            @(negedge CLOCK_50);
            gpio_keys <= 7'b0000001;

            receive_and_verify_midi_packet({8'h90, 8'd60, 8'd127}, "LIVRE_NOTE_ON_C4");

            // Solta tecla Do -> Note Off (8'h80, 8'd60, 8'd0)
            @(negedge CLOCK_50);
            gpio_keys <= 7'b0000000;

            receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0}, "LIVRE_NOTE_OFF_C4");
            repeat (10) @(posedge CLOCK_50);
        end
    endtask

    task test_gravacao_e_demonstracao_ram;
        integer idx;
        time    t_on;
        time    t_off;
        begin
            tests_run = tests_run + 1;
            setup();

            // Seleciona slot 39 (RAM de gravacao) para reproducao posterior no Modo Demonstracao
            for (idx = 0; idx < 39; idx = idx + 1) begin
                press_btn_musica();
            end

            // Navega do Modo 0 (Livre) -> Modo 1 (Aprendizado) -> Modo 2 (Gravacao)
            press_btn_modo();
            press_btn_modo();

            // Pressiona tecla Do (MIDI 60) no Modo 2 (Gravacao) e segura por ~2 ticks de 8ms
            fork
                begin
                    receive_and_verify_midi_packet({8'h90, 8'd60, 8'd127}, "GRAV_MONITOR_NOTE_ON");
                    receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "GRAV_MONITOR_NOTE_OFF");
                end
                begin
                    @(negedge CLOCK_50);
                    gpio_keys <= 7'b0000001;
                    repeat ((2 * CICLOS_TICK_8MS) + DEBOUNCE_TECLA + 4) @(posedge CLOCK_50);
                    @(negedge CLOCK_50);
                    gpio_keys <= 7'b0000000;
                    repeat ((2 * CICLOS_TICK_8MS) + DEBOUNCE_TECLA + 4) @(posedge CLOCK_50);
                end
            join

            begin
                // Navega do Modo 2 (Gravacao) -> Modo 3 (Demonstracao)
                press_btn_modo();
            end

            // Dispara inicio da Demonstracao pressionando uma tecla e verifica reproducao da RAM
            fork
                begin
                    receive_and_verify_midi_packet({8'h90, 8'd60, 8'd127}, "DEMO_RAM_PLAYBACK_NOTE_ON");
                    t_on = $time;
                    receive_and_verify_midi_packet({8'h80, 8'd60, 8'd0},   "DEMO_RAM_PLAYBACK_NOTE_OFF");
                    t_off = $time;
                    if ((t_off - t_on) < (2 * CICLOS_TICK_8MS * CLK_PERIOD)) begin
                        $display("[FAIL] %0t ns | DEMO_RAM_DURATION: expected >= %0d ns, got %0d ns",
                                 $time, (2 * CICLOS_TICK_8MS * CLK_PERIOD), (t_off - t_on));
                        errors = errors + 1;
                    end
                end
                begin
                    @(negedge CLOCK_50);
                    gpio_keys <= 7'b0000001;
                    repeat (DEBOUNCE_TECLA + 3) @(posedge CLOCK_50);
                    @(negedge CLOCK_50);
                    gpio_keys <= 7'b0000000;
                end
            join

            begin
                repeat (20) @(posedge CLOCK_50);
            end
        end
    endtask

    task test_demonstracao_clair_de_lune_rom;
        integer idx;
        begin
            tests_run = tests_run + 1;
            setup();

            // Seleciona slot 4 (Musicas/Clair_de_Lune.txt em u_mem4)
            for (idx = 0; idx < 4; idx = idx + 1) begin
                press_btn_musica();
            end

            // Navega do Modo 0 (Livre) -> Modo 1 -> Modo 2 -> Modo 3 (Demonstracao)
            press_btn_modo();
            press_btn_modo();
            press_btn_modo();

            // Dispara inicio da Demonstracao e verifica as 2 primeiras notas de Clair_de_Lune.txt:
            // Nota 0: MIDI 68 (Ab4), Velocity 48, Duracao 78 ticks
            // Nota 1: MIDI 80 (Ab5), Velocity 61, Duracao 245 ticks
            fork
                begin
                    receive_and_verify_midi_packet({8'h90, 8'd68, 8'd48}, "CLAIR_DE_LUNE_N0_ON");
                    receive_and_verify_midi_packet({8'h80, 8'd68, 8'd0},  "CLAIR_DE_LUNE_N0_OFF");
                    receive_and_verify_midi_packet({8'h90, 8'd80, 8'd61}, "CLAIR_DE_LUNE_N1_ON");
                    receive_and_verify_midi_packet({8'h80, 8'd80, 8'd0},  "CLAIR_DE_LUNE_N1_OFF");
                end
                begin
                    @(negedge CLOCK_50);
                    gpio_keys <= 7'b0000001;
                    repeat (DEBOUNCE_TECLA + 3) @(posedge CLOCK_50);
                    @(negedge CLOCK_50);
                    gpio_keys <= 7'b0000000;
                end
            join

            begin
                repeat (20) @(posedge CLOCK_50);
            end
        end
    endtask

    // -------------------------------------------------------------
    // Runner Principal
    // -------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("STARTING SIMULATION: piano_top_tb");
        $display("========================================");

        test_modo_livre_midi();
        test_gravacao_e_demonstracao_ram();
        test_demonstracao_clair_de_lune_rom();

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
