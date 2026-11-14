/*
 *  Descricao : Unidade de controle do circuito de interface com sensor
 *              ultrassonico de distancia HC-SR04 com suporte a timeout.
 */

`default_nettype none

module interface_hcsr04_uc (
    input  wire       clk,
    input  wire       arst,
    input  wire       medir,
    input  wire       echo,
    input  wire       fim_medida,
    input  wire       fim_timeout,
    output reg        zera,
    output reg        gera,
    output reg        registra,
    output reg        pronto,
    output reg        zera_timeout,
    output reg        conta_timeout,
    output reg        timeout_sel,
    output reg  [3:0] db_estado
);

    reg [2:0] estado_q, estado_d;

    localparam [2:0] kInicial       = 3'b000;
    localparam [2:0] kPreparacao    = 3'b001;
    localparam [2:0] kEnviaTrigger  = 3'b010;
    localparam [2:0] kEsperaEcho    = 3'b011;
    localparam [2:0] kMedida        = 3'b100;
    localparam [2:0] kArmazenamento = 3'b101;
    localparam [2:0] kFinalMedida   = 3'b110;
    localparam [2:0] kTimeout       = 3'b111;

    always @(posedge clk or posedge arst) begin
        if (arst)
            estado_q <= kInicial;
        else
            estado_q <= estado_d;
    end

    always @* begin
        case (estado_q)
            kInicial: begin
                if (medir)
                    estado_d = kPreparacao;
                else
                    estado_d = kInicial;
            end

            kPreparacao: begin
                estado_d = kEnviaTrigger;
            end

            kEnviaTrigger: begin
                estado_d = kEsperaEcho;
            end

            kEsperaEcho: begin
                if (echo)
                    estado_d = kMedida;
                else if (fim_timeout)
                    estado_d = kTimeout;
                else
                    estado_d = kEsperaEcho;
            end

            kMedida: begin
                if (fim_medida)
                    estado_d = kArmazenamento;
                else if (fim_timeout)
                    estado_d = kTimeout;
                else
                    estado_d = kMedida;
            end

            kArmazenamento: begin
                estado_d = kFinalMedida;
            end

            kTimeout: begin
                estado_d = kFinalMedida;
            end

            kFinalMedida: begin
                estado_d = kInicial;
            end

            default: begin
                estado_d = kInicial;
            end
        endcase
    end

    always @* begin
        zera          = 1'b0;
        gera          = 1'b0;
        registra      = 1'b0;
        pronto        = 1'b0;
        zera_timeout  = 1'b0;
        conta_timeout = 1'b0;
        timeout_sel   = 1'b0;
        db_estado     = 4'b1110;

        case (estado_q)
            kInicial: begin
                db_estado = 4'b0000;
            end

            kPreparacao: begin
                zera         = 1'b1;
                zera_timeout = 1'b1;
                db_estado    = 4'b0001;
            end

            kEnviaTrigger: begin
                gera          = 1'b1;
                conta_timeout = 1'b1;
                db_estado     = 4'b0010;
            end

            kEsperaEcho: begin
                conta_timeout = 1'b1;
                db_estado     = 4'b0011;
            end

            kMedida: begin
                conta_timeout = 1'b1;
                db_estado     = 4'b0100;
            end

            kArmazenamento: begin
                registra    = 1'b1;
                timeout_sel = 1'b0;
                db_estado   = 4'b0101;
            end

            kTimeout: begin
                registra    = 1'b1;
                timeout_sel = 1'b1;
                db_estado   = 4'b1100;
            end

            kFinalMedida: begin
                pronto    = 1'b1;
                db_estado = 4'b1111;
            end

            default: begin
                zera          = 1'b0;
                gera          = 1'b0;
                registra      = 1'b0;
                pronto        = 1'b0;
                zera_timeout  = 1'b0;
                conta_timeout = 1'b0;
                timeout_sel   = 1'b0;
                db_estado     = 4'b1110;
            end
        endcase
    end

endmodule

`default_nettype wire
