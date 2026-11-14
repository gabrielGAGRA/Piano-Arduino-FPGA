/*
 * Interface HC-SR04 com disparo, medicao de distancia e timeout.
 */

`default_nettype none

module interface_hcsr04 #(
    parameter TimeoutTicks = 50_000_000,
    parameter TimeoutBits  = 26
)(
    input  wire        clk,
    input  wire        arst,
    input  wire        medir,
    input  wire        echo,
    output wire        trigger,
    output wire [11:0] medida,
    output wire        pronto,
    output wire        db_reset,
    output wire        db_medir,
    output wire [3:0]  db_estado
);

    wire s_zera;
    wire s_gera;
    wire s_registra;
    wire s_fim_medida;
    wire s_fim_timeout;
    wire s_zera_timeout;
    wire s_conta_timeout;
    wire s_timeout_sel;

    interface_hcsr04_uc interface_hcsr04_uc_inst (
        .clk          (clk),
        .arst         (arst),
        .medir        (medir),
        .echo         (echo),
        .fim_medida   (s_fim_medida),
        .fim_timeout  (s_fim_timeout),
        .zera         (s_zera),
        .gera         (s_gera),
        .registra     (s_registra),
        .pronto       (pronto),
        .zera_timeout (s_zera_timeout),
        .conta_timeout(s_conta_timeout),
        .timeout_sel  (s_timeout_sel),
        .db_estado    (db_estado)
    );

    interface_hcsr04_fd #(
        .TimeoutTicks(TimeoutTicks),
        .TimeoutBits (TimeoutBits)
    ) interface_hcsr04_fd_inst (
        .clk          (clk),
        .pulso        (echo),
        .zera         (s_zera),
        .gera         (s_gera),
        .registra     (s_registra),
        .zera_timeout (s_zera_timeout),
        .conta_timeout(s_conta_timeout),
        .timeout_sel  (s_timeout_sel),
        .fim_medida   (s_fim_medida),
        .fim_timeout  (s_fim_timeout),
        .trigger      (trigger),
        .fim          (),
        .distancia    (medida)
    );

    assign db_reset = arst;
    assign db_medir = medir;

endmodule

`default_nettype wire
