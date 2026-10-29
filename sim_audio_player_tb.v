// Descrição: Testbench de co-simulacao de audio para piano_top.
// Funcionamento: Executa piano_top acelerado, monitora transmissao UART 8N1
// e emite eventos formatados MIDI_EVENT:<tempo_ms>:<status>:<nota>:<velocity> para o host.

`timescale 1ns / 1ps
`default_nettype none

module sim_audio_player_tb;

  localparam ClkPeriodNs      = 20;
  localparam DebounceTecla    = 4;
  localparam DebounceControle = 4;
  localparam ClockDivUart     = 4;
  localparam CiclosTick8ms    = 40;
  localparam MaxNotas         = 50;

  reg        clk;
  reg        reset_n;
  reg  [6:0] gpio_keys;
  reg        btn_modo_n;
  reg        btn_musica_n;
  reg        btn_intensidade_n;
  reg        btn_oitava_up_n;
  reg        btn_oitava_down_n;
  reg        btn_sustenido;

  wire       saida_serial;

  initial clk = 1'b0;
  always #(ClkPeriodNs / 2) clk = ~clk;

  piano_top #(
    .DebounceTecla   (DebounceTecla),
    .DebounceControle(DebounceControle),
    .ClockDivUart   (ClockDivUart),
    .CiclosTick8ms  (CiclosTick8ms)
  ) piano_top_inst (
    .clk                (clk),
    .reset_n            (reset_n),
    .gpio_keys          (gpio_keys),
    .btn_modo_n         (btn_modo_n),
    .btn_musica_n       (btn_musica_n),
    .btn_intensidade_n  (btn_intensidade_n),
    .btn_oitava_up_n    (btn_oitava_up_n),
    .btn_oitava_down_n  (btn_oitava_down_n),
    .btn_sustenido      (btn_sustenido),
    .saida_serial       (saida_serial),
    .servo_controle     (),
    .led_vermelho       (),
    .led_sustenido      (),
    .led_oitava_up      (),
    .led_oitava_down    (),
    .hex5_modo          (),
    .hex4_oitava        (),
    .hex3_musica_dezena (),
    .hex2_musica_unidade(),
    .hex1_nota          (),
    .hex0_sustenido     ()
  );

  reg [63:0] total_cycles;
  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      total_cycles <= 64'd0;
    end else begin
      total_cycles <= total_cycles + 64'd1;
    end
  end

  wire [63:0] tempo_ms = (total_cycles * 8) / CiclosTick8ms;

  task uart_receive_byte(output reg [7:0] rx_byte);
    integer b;
    begin
      @(negedge saida_serial);
      #(ClkPeriodNs * ClockDivUart * 1.5);

      for (b = 0; b < 8; b = b + 1) begin
        rx_byte[b] = saida_serial;
        #(ClkPeriodNs * ClockDivUart);
      end

      #(ClkPeriodNs * ClockDivUart * 0.5);
    end
  endtask

  integer   nota_count = 0;
  reg [7:0] b0;
  reg [7:0] b1;
  reg [7:0] b2;

  initial begin
    while (nota_count < (MaxNotas * 2)) begin
      uart_receive_byte(b0);
      if (b0[7] == 1'b1) begin
        uart_receive_byte(b1);
        uart_receive_byte(b2);
        $display("MIDI_EVENT:%0d:%02x:%0d:%0d", tempo_ms, b0, b1[6:0], b2[6:0]);
        nota_count = nota_count + 1;
      end
    end
    $display("MIDI_END");
    $finish;
  end

  task press_btn_musica;
    begin
      @(negedge clk);
      btn_musica_n <= 1'b0;
      repeat (DebounceControle + 4) @(posedge clk);
      @(negedge clk);
      btn_musica_n <= 1'b1;
      repeat (DebounceControle + 4) @(posedge clk);
    end
  endtask

  task press_btn_modo;
    begin
      @(negedge clk);
      btn_modo_n <= 1'b0;
      repeat (DebounceControle + 4) @(posedge clk);
      @(negedge clk);
      btn_modo_n <= 1'b1;
      repeat (DebounceControle + 4) @(posedge clk);
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

    repeat (5) @(posedge clk);
    @(negedge clk);
    reset_n <= 1'b1;
    repeat (10) @(posedge clk);

    for (idx = 0; idx < 4; idx = idx + 1) begin
      press_btn_musica();
    end

    press_btn_modo();
    press_btn_modo();
    press_btn_modo();

    @(negedge clk);
    gpio_keys <= 7'b0000001;
    repeat (DebounceTecla + 4) @(posedge clk);
    @(negedge clk);
    gpio_keys <= 7'b0000000;

    #20_000_000;
    $display("MIDI_END");
    $finish;
  end

endmodule

`default_nettype wire
