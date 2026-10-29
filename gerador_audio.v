`timescale 1ns / 1ps
`default_nettype none

// Descricao: Simula a dinamica de um piano com ataque rapido e 
// decaimento longo ate o silencio.
module gerador_audio (
    input  wire        clock,       
    input  wire        reset,
    input  wire [17:0] fim_contagem,  
    input  wire        habilitar,     
    input  wire  [3:0] nivel_volume,  
    output wire        buzzer
);

    // 1. Geração da Onda Base (Duty cycle estreito para som mais "fino")
    reg [17:0] contador_freq_reg;
    reg        onda_quadrada_reg;
    wire [17:0] threshold = (fim_contagem >> 4'd4); // 6.25% - som mais percussivo

    // 2. Envelope ADSR Estilo Piano
    reg [9:0]  envelope_val_reg;
    reg [19:0] timer_envelope_reg;
    reg        habilitar_antigo_reg;
    
    // Estados do Envelope
    localparam [1:0] IDLE    = 2'd0,
                     ATTACK  = 2'd1,
                     DECAY   = 2'd2,
                     RELEASE = 2'd3;
    reg [1:0] estado_adsr_reg;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            contador_freq_reg <= 18'd0;
            onda_quadrada_reg <= 1'b0;
        end else if (habilitar || envelope_val_reg > 10'd0) begin
            if (contador_freq_reg >= fim_contagem) begin
                contador_freq_reg <= 18'd0;
            end else begin
                contador_freq_reg <= contador_freq_reg + 18'd1;
            end
            onda_quadrada_reg <= (contador_freq_reg < threshold);
        end else begin
            contador_freq_reg <= 18'd0;
            onda_quadrada_reg <= 1'b0;
        end
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            envelope_val_reg     <= 10'd0;
            timer_envelope_reg   <= 20'd0;
            estado_adsr_reg      <= IDLE;
            habilitar_antigo_reg <= 1'b0;
        end else begin
            habilitar_antigo_reg <= habilitar;

            case (estado_adsr_reg)
                IDLE: begin
                    if (habilitar && !habilitar_antigo_reg) begin
                        estado_adsr_reg    <= ATTACK;
                        timer_envelope_reg <= 20'd0;
                    end else begin
                        envelope_val_reg <= 10'd0;
                    end
                end

                ATTACK: begin
                    // Ataque muito rapido (rampa de ~2ms para evitar estalo)
                    if (timer_envelope_reg >= 20'd100) begin 
                        timer_envelope_reg <= 20'd0;
                        if (envelope_val_reg >= 10'd1000) begin
                            estado_adsr_reg <= DECAY;
                        end else begin
                            envelope_val_reg <= envelope_val_reg + 10'd20; // Sobe em degraus grandes
                        end
                    end else begin
                        timer_envelope_reg <= timer_envelope_reg + 20'd1;
                    end
                end

                DECAY: begin
                    if (!habilitar) begin
                        estado_adsr_reg    <= RELEASE;
                        timer_envelope_reg <= 20'd0;
                    end else begin
                        // Decaimento: mantemos o tempo, mas cortamos no limiar de trepidação
                        if (timer_envelope_reg >= 20'd150_000) begin 
                            timer_envelope_reg <= 20'd0;
                            // Threshold de 150 para evitar o ruído mecânico do buzzer
                            if (envelope_val_reg > 10'd150) begin
                                envelope_val_reg <= envelope_val_reg - 10'd1;
                            end else begin
                                envelope_val_reg <= 10'd0; // Corte abrupto (Noise Gate)
                                estado_adsr_reg  <= IDLE;
                            end
                        end else begin
                            timer_envelope_reg <= timer_envelope_reg + 20'd1;
                        end
                    end
                end

                RELEASE: begin
                    if (habilitar) begin 
                        estado_adsr_reg    <= ATTACK;
                        timer_envelope_reg <= 20'd0;
                    end else begin
                        // Release otimizado: ~68ms total a 50MHz
                        if (timer_envelope_reg >= 20'd20_000) begin
                            timer_envelope_reg <= 20'd0;
                            
                            // Subtrai de 5 em 5 para uma queda natural, mas rápida
                            if (envelope_val_reg > 10'd150) begin
                                envelope_val_reg <= envelope_val_reg - 10'd5;
                            end else begin
                                envelope_val_reg <= 10'd0; // Noise gate: corta a trepidação
                                estado_adsr_reg  <= IDLE;
                            end
                        end else begin
                            timer_envelope_reg <= timer_envelope_reg + 20'd1;
                        end
                    end
                end

                default: begin
                    estado_adsr_reg    <= IDLE;
                    timer_envelope_reg <= 20'd0;
                    envelope_val_reg   <= 10'd0;
                end
            endcase
        end
    end

    // 3. Ganho e PWM
    wire [13:0] calc_ganho = envelope_val_reg * nivel_volume;
    wire [9:0] volume_final = calc_ganho[13:4];
    reg [9:0] contador_pwm_hf_reg;
    
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            contador_pwm_hf_reg <= 10'd0;
        end else if (contador_pwm_hf_reg >= 10'd1000) begin
            contador_pwm_hf_reg <= 10'd0;
        end else begin
            contador_pwm_hf_reg <= contador_pwm_hf_reg + 10'd1;
        end
    end

    assign buzzer = onda_quadrada_reg & (contador_pwm_hf_reg < volume_final);

endmodule

`default_nettype wire
