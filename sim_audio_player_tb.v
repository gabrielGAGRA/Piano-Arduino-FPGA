`timescale 1ns / 1ps
`default_nettype none

/*
 * Descricao : Testbench de co-simulacao de audio para piano_top.
 *             Executa a FPGA em velocidade acelerada (1 tick = 40 ciclos),
 *             captura a linha saida_serial em UART 8N1 e emite eventos formatados
 *             MIDI_EVENT:<tempo_real_ms>:<status_hex>:<nota>:<velocity>
 *             para reproducao sonora imediata no PC.
 */
module sim_audio_player_tb;

    localparam CLK_PERIOD        = 20;
    localparam DEBOUNCE_TECLA    = 4;
    localparam DEBOUNCE_CONTROLE = 4;
    localparam CLOCK_DIV_UART    = 4;
    localparam CICLOS_TICK_8MS   = 40;
    localparam MAX_NOTAS         = 50;

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

    initial CLOCK_50 = 1'b0;
    always #(CLK_PERIOD / 2) CLOCK_50 = ~CLOCK_50;

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
        .servo_controle      (),
        .led_vermelho        (),
        .led_sustenido       (),
        .led_oitava_up       (),
        .led_oitava_down     (),
        .hex5_modo           (),
        .hex4_oitava         (),
        .hex3_musica_dezena  (),
        .hex2_musica_unidade (),
        .hex1_nota           (),
        .hex0_sustenido      ()
    );

    // Contador de ciclos globais para mapeamento em tempo real (ms)
    reg [63:0] total_cycles;
    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            total_cycles <= 64'd0;
        end else begin
            total_cycles <= total_cycles + 64'd1;
        end
    end

    wire [63:0] tempo_ms = (total_cycles * 8) / CICLOS_TICK_8MS;

    // Receptor UART 8N1 de monitoramento
    task uart_receive_byte(output reg [7:0] rx_byte);
        integer b;
        begin
            @(negedge saida_serial); // Start bit
            #(CLK_PERIOD * CLOCK_DIV_UART * 1.5); // Meio do bit 0

            for (b = 0; b < 8; b = b + 1) begin
                rx_byte[b] = saida_serial;
                #(CLK_PERIOD * CLOCK_DIV_UART);
            end

            // Stop bit
            #(CLK_PERIOD * CLOCK_DIV_UART * 0.5);
        end
    endtask

    integer nota_count = 0;
    reg [7:0] b0, b1, b2;

    initial begin
        while (nota_count < (MAX_NOTAS * 2)) begin
            uart_receive_byte(b0);
            if (b0[7] == 1'b1) begin // Byte de Status MIDI
                uart_receive_byte(b1);
                uart_receive_byte(b2);
                $display("MIDI_EVENT:%0d:%02x:%0d:%0d", tempo_ms, b0, b1[6:0], b2[6:0]);
                nota_count = nota_count + 1;
            end
        end
        $display("MIDI_END");
        $finish;
    end

    // Tarefas de estimulo dos botoes
    task press_btn_musica;
        begin
            @(negedge CLOCK_50);
            btn_musica_n <= 1'b0;
            repeat (DEBOUNCE_CONTROLE + 4) @(posedge CLOCK_50);
            @(negedge CLOCK_50);
            btn_musica_n <= 1'b1;
            repeat (DEBOUNCE_CONTROLE + 4) @(posedge CLOCK_50);
        end
    endtask

    task press_btn_modo;
        begin
            @(negedge CLOCK_50);
            btn_modo_n <= 1'b0;
            repeat (DEBOUNCE_CONTROLE + 4) @(posedge CLOCK_50);
            @(negedge CLOCK_50);
            btn_modo_n <= 1'b1;
            repeat (DEBOUNCE_CONTROLE + 4) @(posedge CLOCK_50);
        end
    endtask

    integer idx;
    initial begin
        reset_n           <= 1'b0;
        gpio_keys         <= 7'd0;
        btn_modo_n        <= 1'b1;
        btn_musica_n      <= 1'b1;
        btn_intensidade_n <= 1'b1;
        btn_oitava_up_n   <= 1'b1;
        btn_oitava_down_n <= 1'b1;
        btn_sustenido     <= 1'b0;

        repeat (5) @(posedge CLOCK_50);
        @(negedge CLOCK_50);
        reset_n <= 1'b1;
        repeat (10) @(posedge CLOCK_50);

        // Seleciona slot 4 (Musicas/Clair_de_Lune.txt)
        for (idx = 0; idx < 4; idx = idx + 1) begin
            press_btn_musica();
        end

        // Navega para o Modo 3 (Demonstracao)
        press_btn_modo();
        press_btn_modo();
        press_btn_modo();

        // Dispara o playback com gpio_keys[0]
        @(negedge CLOCK_50);
        gpio_keys <= 7'b0000001;
        repeat (DEBOUNCE_TECLA + 4) @(posedge CLOCK_50);
        @(negedge CLOCK_50);
        gpio_keys <= 7'b0000000;

        // Watchdog de seguranca (caso a musica acabe antes de MAX_NOTAS)
        #20_000_000;
        $display("MIDI_END");
        $finish;
    end

endmodule

`default_nettype wire
