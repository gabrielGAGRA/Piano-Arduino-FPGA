/*
 *  Descricao : Fluxo de dados do circuito de interface com sensor ultrassonico
 *              de distancia HC-SR04 com deteccao de timeout.
 */

`default_nettype none

module interface_hcsr04_fd #(
    parameter TimeoutTicks = 50_000_000,
    parameter TimeoutBits  = 26
)(
    input  wire        clk,
    input  wire        pulso,
    input  wire        zera,
    input  wire        gera,
    input  wire        registra,
    input  wire        zera_timeout,
    input  wire        conta_timeout,
    input  wire        timeout_sel,
    output wire        fim_medida,
    output wire        fim_timeout,
    output wire        trigger,
    output wire        fim,
    output wire [11:0] distancia
);

    reg [9:0] s_trigger_count;
    reg s_trigger;

    always @(posedge clk or posedge zera) begin
        if (zera) begin
            s_trigger_count <= 10'd0;
            s_trigger <= 1'b0;
        end else if (gera && !s_trigger) begin
            s_trigger_count <= 10'd0;
            s_trigger <= 1'b1;
        end else if (s_trigger) begin
            if (s_trigger_count == 10'd499) begin
                s_trigger_count <= 10'd0;
                s_trigger <= 1'b0;
            end else begin
                s_trigger_count <= s_trigger_count + 10'd1;
            end
        end
    end

    assign trigger = s_trigger;

    wire s_tick_cm;
    contador_m #(
        .Modulo(2941),
        .Width (12)
    ) contador_m_cm (
        .clk  (clk),
        .arst (1'b0),
        .sclr (zera),
        .conta(pulso),
        .q    (),
        .fim  (),
        .meio (s_tick_cm)
    );

    reg [3:0] s_cm_unidades;
    reg [3:0] s_cm_dezenas;
    reg [3:0] s_cm_centenas;
    reg s_fim_medida_reg;
    reg s_pulso_prev;
    reg [11:0] s_medida_reg;

    always @(posedge clk or posedge zera) begin
        if (zera) begin
            s_cm_unidades <= 4'd0;
            s_cm_dezenas <= 4'd0;
            s_cm_centenas <= 4'd0;
        end else if (pulso && s_tick_cm && (s_cm_centenas < 4'd9 ||
            s_cm_dezenas < 4'd9 || s_cm_unidades < 4'd9)) begin
            if (s_cm_unidades == 4'd9) begin
                s_cm_unidades <= 4'd0;
                if (s_cm_dezenas == 4'd9) begin
                    s_cm_dezenas <= 4'd0;
                    s_cm_centenas <= s_cm_centenas + 4'd1;
                end else begin
                    s_cm_dezenas <= s_cm_dezenas + 4'd1;
                end
            end else begin
                s_cm_unidades <= s_cm_unidades + 4'd1;
            end
        end

        if (zera) begin
            s_fim_medida_reg <= 1'b0;
            s_pulso_prev <= 1'b0;
            s_medida_reg <= 12'd0;
        end else begin
            s_pulso_prev <= pulso;
            s_fim_medida_reg <= s_pulso_prev && !pulso;
            if (registra) begin
                if (timeout_sel) begin
                    s_medida_reg <= 12'h999;
                end else begin
                    s_medida_reg <= {s_cm_centenas, s_cm_dezenas, s_cm_unidades};
                end
            end
        end
    end

    assign fim_medida = s_fim_medida_reg;
    assign distancia = s_medida_reg;
    assign fim = (s_cm_centenas == 4'd9) &&
        (s_cm_dezenas == 4'd9) && (s_cm_unidades == 4'd9);

    // Watchdog de timeout
    contador_m #(
        .Modulo(TimeoutTicks),
        .Width (TimeoutBits)
    ) contador_m_timeout (
        .clk  (clk),
        .arst (1'b0),
        .sclr (zera_timeout),
        .conta(conta_timeout),
        .q    (),
        .fim  (fim_timeout),
        .meio ()
    );

endmodule

`default_nettype wire
