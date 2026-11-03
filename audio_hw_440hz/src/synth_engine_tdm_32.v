module synth_engine_tdm_32 #(
    parameter [14:0] ATTACK_STEP   = 15'd14,
    parameter [14:0] DECAY_STEP    = 15'd3,
    parameter [14:0] SUSTAIN_LEVEL = 15'd19660,
    parameter [14:0] RELEASE_STEP  = 15'd2,

    // 32 Voices:
    // each Voice is attenuated by 1/32.
    parameter integer OUTPUT_SHIFT = 5
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // One pulse for every audio sample.
    input  wire                 sample_en,

    // ------------------------------------------------------------
    // Voice controls
    // ------------------------------------------------------------
    input  wire [31:0]          gate_mask,

    // 32 × 32-bit FCW
    input  wire [1023:0]        fcw_flat,

    // ------------------------------------------------------------
    // Audio output
    // ------------------------------------------------------------
    output reg signed [15:0]    mix_pcm,

    // ------------------------------------------------------------
    // Voice status
    // ------------------------------------------------------------
    output wire [31:0]          active_mask,

    output reg                  engine_busy
);

    // ============================================================
    // Constants
    // ============================================================

    localparam [14:0] MAX_LEVEL =
        15'd32767;


    localparam [2:0] STATE_IDLE =
        3'd0;

    localparam [2:0] STATE_ATTACK =
        3'd1;

    localparam [2:0] STATE_DECAY =
        3'd2;

    localparam [2:0] STATE_SUSTAIN =
        3'd3;

    localparam [2:0] STATE_RELEASE =
        3'd4;


    // ============================================================
    // Shared sine wavetable
    // ============================================================

    reg signed [15:0] sine_rom [0:1023];


    initial begin

        $readmemh(
            "src/sine_1024.mem",
            sine_rom
        );

    end


    // ============================================================
    // Per-Voice state memory
    // ============================================================

    reg [31:0] phase_acc [0:31];

    reg [14:0] env_level [0:31];

    reg [2:0] env_state [0:31];


    // ============================================================
    // Scheduler
    // ============================================================

    reg [5:0] voice_index;


    // ============================================================
    // Mixing accumulator
    // ============================================================

    reg signed [21:0] mix_acc;


    // ============================================================
    // Current Voice
    // ============================================================

    wire [31:0] current_fcw;

    wire [31:0] current_phase;

    wire [9:0] current_wave_addr;


    wire signed [15:0] current_sine;

    wire signed [15:0] current_env_gain;

    wire signed [31:0] current_product;

    wire signed [15:0] current_voice_pcm;

    wire signed [21:0] current_voice_ext;

    wire signed [21:0] mix_acc_next;


    // ------------------------------------------------------------
    // Select FCW of current Voice.
    //
    // Verilog indexed part-select:
    //
    // Voice0  -> [31:0]
    // Voice1  -> [63:32]
    // ...
    // ------------------------------------------------------------

    assign current_fcw =
        fcw_flat[
            voice_index * 32 +:
            32
        ];


    assign current_phase =
        phase_acc[voice_index];


    assign current_wave_addr =
        current_phase[31:22];


    assign current_sine =
        sine_rom[current_wave_addr];


    // ------------------------------------------------------------
    // Convert unsigned Q15 envelope to positive signed value.
    // ------------------------------------------------------------

    assign current_env_gain = {
        1'b0,
        env_level[voice_index]
    };


    // ------------------------------------------------------------
    // DDS × ADSR
    // ------------------------------------------------------------

    assign current_product =
        current_sine *
        current_env_gain;


    // ------------------------------------------------------------
    // Q15 restore + Voice headroom
    //
    // OUTPUT_SHIFT = 5:
    //
    // each Voice approximately 1/32 full scale.
    // ------------------------------------------------------------

    assign current_voice_pcm =
        (
            current_product >>> 15
        ) >>> OUTPUT_SHIFT;


    // ------------------------------------------------------------
    // Sign extension
    // ------------------------------------------------------------

    assign current_voice_ext = {
        {6{current_voice_pcm[15]}},
        current_voice_pcm
    };


    assign mix_acc_next =
        mix_acc +
        current_voice_ext;


    // ============================================================
    // Voice activity output
    // ============================================================

    genvar active_i;

    generate

        for (
            active_i = 0;
            active_i < 32;
            active_i = active_i + 1
        ) begin : GEN_ACTIVE_MASK

            assign active_mask[active_i] =
                (
                    env_state[active_i] !=
                    STATE_IDLE
                ) ||
                (
                    env_level[active_i] !=
                    15'd0
                );

        end

    endgenerate


    // ============================================================
    // Saturation helper
    // ============================================================

    function signed [15:0] saturate_16;

        input signed [21:0] value;

        begin

            if (
                value >
                22'sd32767
            ) begin

                saturate_16 =
                    16'sh7FFF;

            end
            else if (
                value <
                -22'sd32768
            ) begin

                saturate_16 =
                    -16'sd32768;

            end
            else begin

                saturate_16 =
                    value[15:0];

            end

        end

    endfunction


    // ============================================================
    // Main TDM Engine
    // ============================================================

    integer reset_i;


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            voice_index <= 6'd0;

            mix_acc <= 22'sd0;

            mix_pcm <= 16'sd0;

            engine_busy <= 1'b0;


            for (
                reset_i = 0;
                reset_i < 32;
                reset_i = reset_i + 1
            ) begin

                phase_acc[reset_i] <=
                    32'd0;

                env_level[reset_i] <=
                    15'd0;

                env_state[reset_i] <=
                    STATE_IDLE;

            end

        end
        else begin


            // ====================================================
            // Start a new 32-Voice audio calculation.
            // ====================================================

            if (
                sample_en &&
                !engine_busy
            ) begin

                voice_index <=
                    6'd0;

                mix_acc <=
                    22'sd0;

                engine_busy <=
                    1'b1;

            end


            // ====================================================
            // Process one Voice per 48 MHz clock.
            // ====================================================

            else if (engine_busy) begin


                // =================================================
                // DDS phase update
                // =================================================

                phase_acc[voice_index] <=
                    phase_acc[voice_index] +
                    current_fcw;


                // =================================================
                // ADSR update
                // =================================================

                case (
                    env_state[voice_index]
                )


                    // ---------------------------------------------
                    // IDLE
                    // ---------------------------------------------
                    STATE_IDLE: begin

                        env_level[voice_index] <=
                            15'd0;


                        if (
                            gate_mask[voice_index]
                        ) begin

                            env_state[voice_index] <=
                                STATE_ATTACK;

                        end

                    end


                    // ---------------------------------------------
                    // ATTACK
                    // ---------------------------------------------
                    STATE_ATTACK: begin

                        if (
                            !gate_mask[voice_index]
                        ) begin

                            env_state[voice_index] <=
                                STATE_RELEASE;

                        end
                        else if (
                            env_level[voice_index] >=
                            (
                                MAX_LEVEL -
                                ATTACK_STEP
                            )
                        ) begin

                            env_level[voice_index] <=
                                MAX_LEVEL;

                            env_state[voice_index] <=
                                STATE_DECAY;

                        end
                        else begin

                            env_level[voice_index] <=
                                env_level[voice_index] +
                                ATTACK_STEP;

                        end

                    end


                    // ---------------------------------------------
                    // DECAY
                    // ---------------------------------------------
                    STATE_DECAY: begin

                        if (
                            !gate_mask[voice_index]
                        ) begin

                            env_state[voice_index] <=
                                STATE_RELEASE;

                        end
                        else if (
                            env_level[voice_index] <=
                            (
                                SUSTAIN_LEVEL +
                                DECAY_STEP
                            )
                        ) begin

                            env_level[voice_index] <=
                                SUSTAIN_LEVEL;

                            env_state[voice_index] <=
                                STATE_SUSTAIN;

                        end
                        else begin

                            env_level[voice_index] <=
                                env_level[voice_index] -
                                DECAY_STEP;

                        end

                    end


                    // ---------------------------------------------
                    // SUSTAIN
                    // ---------------------------------------------
                    STATE_SUSTAIN: begin

                        env_level[voice_index] <=
                            SUSTAIN_LEVEL;


                        if (
                            !gate_mask[voice_index]
                        ) begin

                            env_state[voice_index] <=
                                STATE_RELEASE;

                        end

                    end


                    // ---------------------------------------------
                    // RELEASE
                    // ---------------------------------------------
                    STATE_RELEASE: begin

                        if (
                            gate_mask[voice_index]
                        ) begin

                            env_state[voice_index] <=
                                STATE_ATTACK;

                        end
                        else if (
                            env_level[voice_index] <=
                            RELEASE_STEP
                        ) begin

                            env_level[voice_index] <=
                                15'd0;

                            env_state[voice_index] <=
                                STATE_IDLE;

                        end
                        else begin

                            env_level[voice_index] <=
                                env_level[voice_index] -
                                RELEASE_STEP;

                        end

                    end


                    // ---------------------------------------------
                    // Default
                    // ---------------------------------------------
                    default: begin

                        env_level[voice_index] <=
                            15'd0;

                        env_state[voice_index] <=
                            STATE_IDLE;

                    end

                endcase


                // =================================================
                // Mixer
                // =================================================

                if (
                    voice_index ==
                    6'd31
                ) begin

                    // ---------------------------------------------
                    // Final Voice:
                    // include Voice31 in final output.
                    // ---------------------------------------------

                    mix_pcm <=
                        saturate_16(
                            mix_acc_next
                        );


                    mix_acc <=
                        22'sd0;


                    voice_index <=
                        6'd0;


                    engine_busy <=
                        1'b0;

                end
                else begin

                    mix_acc <=
                        mix_acc_next;


                    voice_index <=
                        voice_index +
                        1'b1;

                end

            end

        end

    end

endmodule