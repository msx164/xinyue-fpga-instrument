
`timescale 1ns/1ps

module poly_synth_core_32_dualtimbre #(
    parameter [14:0] ATTACK_STEP   = 15'd14,
    parameter [14:0] DECAY_STEP    = 15'd3,
    parameter [14:0] SUSTAIN_LEVEL = 15'd19660,
    parameter [14:0] RELEASE_STEP  = 15'd2,
    parameter integer OUTPUT_SHIFT = 4,
    parameter integer SINE_INTERP_ENABLE = 1,
    parameter integer MIX_PROTECT_MODE = 1
)(
    input wire clk,
    input wire rst_n,
    input wire sample_en,
    input wire timbre_sel,
    input wire [8:0] bend_q12,
    input wire event_valid,
    input wire event_on,
    input wire [6:0] event_note,
    input wire [31:0] event_fcw,

    output wire signed [15:0] mix_pcm,
    output wire [31:0] gate_mask,
    output wire [31:0] assigned_mask,
    output wire [31:0] active_mask,
    output wire alloc_fail_pulse,
    output wire engine_busy
);

    wire [1023:0] fcw_flat;

    voice_allocator_32 u_allocator (
        .clk(clk),
        .rst_n(rst_n),
        .event_valid(event_valid),
        .event_on(event_on),
        .event_note(event_note),
        .event_fcw(event_fcw),
        .active_mask(active_mask),
        .gate_mask(gate_mask),
        .fcw_flat(fcw_flat),
        .assigned_mask(assigned_mask),
        .alloc_fail_pulse(alloc_fail_pulse)
    );

    synth_engine_tdm_32_dualtimbre #(
        .ATTACK_STEP(ATTACK_STEP),
        .DECAY_STEP(DECAY_STEP),
        .SUSTAIN_LEVEL(SUSTAIN_LEVEL),
        .RELEASE_STEP(RELEASE_STEP),
        .OUTPUT_SHIFT(OUTPUT_SHIFT),
        .SINE_INTERP_ENABLE(SINE_INTERP_ENABLE),
        .MIX_PROTECT_MODE(MIX_PROTECT_MODE)
    ) u_engine (
        .clk(clk),
        .rst_n(rst_n),
        .sample_en(sample_en),
        .timbre_sel(timbre_sel),
        .bend_q12(bend_q12),
        .gate_mask(gate_mask),
        .fcw_flat(fcw_flat),
        .mix_pcm(mix_pcm),
        .active_mask(active_mask),
        .engine_busy(engine_busy)
    );

endmodule


module synth_engine_tdm_32_dualtimbre #(
    parameter [14:0] ATTACK_STEP   = 15'd14,
    parameter [14:0] DECAY_STEP    = 15'd3,
    parameter [14:0] SUSTAIN_LEVEL = 15'd19660,
    parameter [14:0] RELEASE_STEP  = 15'd2,
    parameter integer OUTPUT_SHIFT = 4,
    parameter integer SINE_INTERP_ENABLE = 1,
    parameter integer MIX_PROTECT_MODE = 1
)(
    input wire clk,
    input wire rst_n,
    input wire sample_en,
    input wire timbre_sel,
    input wire [8:0] bend_q12,
    input wire [31:0] gate_mask,
    input wire [1023:0] fcw_flat,

    output reg signed [15:0] mix_pcm,
    output wire [31:0] active_mask,
    output reg engine_busy
);

    localparam [14:0] MAX_LEVEL = 15'd32767;

    localparam [2:0] STATE_IDLE    = 3'd0;
    localparam [2:0] STATE_ATTACK  = 3'd1;
    localparam [2:0] STATE_DECAY   = 3'd2;
    localparam [2:0] STATE_SUSTAIN = 3'd3;
    localparam [2:0] STATE_RELEASE = 3'd4;

    // ==================================================
    // 1. Sine ROM
    // ==================================================

    reg signed [15:0] sine_rom [0:1023];

    initial begin
        $readmemh("src/sine_1024.mem", sine_rom);
    end

    // ==================================================
    // 2. Voice state storage
    // ==================================================

    reg [31:0] phase_acc [0:31];
    reg [14:0] env_level [0:31];
    reg [2:0] env_state [0:31];

    reg [5:0] voice_index;
    reg [1:0] process_stage;

    // Full precision mix before 16-bit output
    reg signed [21:0] mix_acc;

    // One final pipeline cycle for mixer protection
    reg finalize_pending;

    reg signed [15:0] sine_base_q;
    reg signed [15:0] sine_next_q;
    reg signed [15:0] sine_interp_q;
    reg [7:0] sine_frac_q;

    // ==================================================
    // 3. Current voice information
    // ==================================================

    wire [31:0] current_fcw =
        fcw_flat[voice_index * 32 +: 32];

    wire [31:0] current_phase =
        phase_acc[voice_index];

    wire [9:0] current_wave_addr =
        current_phase[31:22];

    wire [9:0] sine_read_addr =
        (process_stage == 2'd1) ?
        (current_wave_addr + 10'd1) :
         current_wave_addr;

    wire signed [15:0] sine_rom_data =
        sine_rom[sine_read_addr];

    // ==================================================
    // 4. Pitch bend
    // ==================================================

    wire [40:0] bend_product =
        current_fcw * bend_q12;

    reg [40:0] bend_product_q;
    reg [31:0] base_fcw_q;

    wire [31:0] bend_delta_fcw =
        {3'b000, bend_product_q[40:12]};

    wire [32:0] bent_fcw_sum =
        {1'b0, base_fcw_q} +
        {1'b0, bend_delta_fcw};

    wire [31:0] bent_fcw =
        bent_fcw_sum[32] ?
        32'hFFFFFFFF :
        bent_fcw_sum[31:0];

    // ==================================================
    // 5. B5-A: 8-bit sine interpolation
    // ==================================================

    wire signed [16:0] sine_delta =
        $signed({sine_next_q[15], sine_next_q}) -
        $signed({sine_base_q[15], sine_base_q});

    wire signed [8:0] sine_frac_signed =
        $signed({1'b0, sine_frac_q});

    wire signed [25:0] sine_frac_product =
        sine_delta * sine_frac_signed;

    wire signed [17:0] sine_scaled_delta =
        sine_frac_product >>> 8;

    wire signed [17:0] sine_interp_sum =
        $signed({{2{sine_base_q[15]}}, sine_base_q}) +
        sine_scaled_delta;

    wire signed [15:0] sine_wave =
        (SINE_INTERP_ENABLE != 0) ?
        sine_interp_q : sine_base_q;

    // ==================================================
    // 6. Triangle wave
    // ==================================================

    wire [7:0] triangle_ramp =
        current_wave_addr[8] ?
        ~current_wave_addr[7:0] :
         current_wave_addr[7:0];

    wire signed [15:0] triangle_mag =
        $signed({1'b0, triangle_ramp, 7'b0});

    wire signed [15:0] triangle_wave =
        current_wave_addr[9] ?
        -triangle_mag :
         triangle_mag;

    wire signed [15:0] current_wave =
        timbre_sel ? triangle_wave : sine_wave;

    // ==================================================
    // 7. ADSR gain and voice output
    // ==================================================

    wire signed [15:0] current_env_gain =
        {1'b0, env_level[voice_index]};

    wire signed [31:0] current_product =
        current_wave * current_env_gain;

    wire signed [15:0] current_voice_pcm =
        (current_product >>> 15) >>> OUTPUT_SHIFT;

    // ==================================================
    // 8. Wide audio summation
    // ==================================================

    wire signed [21:0] current_voice_ext =
        {{6{current_voice_pcm[15]}},
          current_voice_pcm};

    wire signed [21:0] mix_acc_next =
        mix_acc + current_voice_ext;

    // Original hard clipping, for comparison.
    function signed [15:0] saturate_16;
        input signed [21:0] value;
        begin
            if (value > 22'sd32767)
                saturate_16 = 16'sh7FFF;
            else if (value < -22'sd32768)
                saturate_16 = 16'sh8000;
            else
                saturate_16 = value[15:0];
        end
    endfunction

    // ==================================================
    // 9. B5-C: piecewise soft-knee compression
    //
    // Range                 Output slope
    // 0      - 16384       1
    // 16384  - 32768       1/2
    // 32768  - 65536       1/8
    // 65536  - 131072      1/16
    //
    // Low-level signals are unchanged.
    // Positive and negative samples are symmetric.
    // No extra multiplier or divider is required.
    // ==================================================

    function signed [15:0] soft_knee_mix;
        input signed [21:0] value;

        reg [21:0] magnitude;
        reg [21:0] shaped;

        begin
            // Absolute value of the signed 22-bit mix
            if (value[21])
                magnitude = (~value) + 22'd1;
            else
                magnitude = value;

            // Piecewise continuous compression
            if (magnitude <= 22'd16384) begin

                shaped = magnitude;

            end
            else if (magnitude <= 22'd32768) begin

                shaped =
                    22'd16384 +
                    ((magnitude - 22'd16384) >> 1);

            end
            else if (magnitude <= 22'd65536) begin

                shaped =
                    22'd24576 +
                    ((magnitude - 22'd32768) >> 3);

            end
            else if (magnitude <= 22'd131072) begin

                shaped =
                    22'd28672 +
                    ((magnitude - 22'd65536) >> 4);

            end
            else begin

                shaped = 22'd32767;

            end

            // Hard safety bound
            if (shaped > 22'd32767)
                shaped = 22'd32767;

            // Restore sign
            if (value[21])
                soft_knee_mix =
                    -$signed(shaped[15:0]);
            else
                soft_knee_mix =
                     $signed(shaped[15:0]);
        end
    endfunction

    // The complete sum has already been registered.
    // This separates the audio multiplier/adder path
    // from the protection logic.

    // B5-C-2: Boost music before soft compression
// SHIFT=1: +6.02 dB
// SHIFT=0: original B5-C behavior

localparam integer MIX_PREGAIN_SHIFT = 1;

wire signed [21:0] mix_boosted =
    mix_acc <<< MIX_PREGAIN_SHIFT;

wire signed [15:0] mixed_pcm_next =
    (MIX_PROTECT_MODE == 0) ?
    saturate_16(mix_acc) :
    soft_knee_mix(mix_boosted);

    // ==================================================
    // 10. Voice activity mask
    // ==================================================

    genvar v;

    generate
        for (v = 0; v < 32; v = v + 1) begin :
            GEN_ACTIVE

            assign active_mask[v] =
                (env_state[v] != STATE_IDLE) ||
                (env_level[v] != 15'd0);

        end
    endgenerate

    // ==================================================
    // 11. Main synthesis engine
    // ==================================================

    integer i;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            voice_index <= 6'd0;
            process_stage <= 2'd0;

            mix_acc <= 22'sd0;
            mix_pcm <= 16'sd0;

            finalize_pending <= 1'b0;
            engine_busy <= 1'b0;

            bend_product_q <= 41'd0;
            base_fcw_q <= 32'd0;

            sine_base_q <= 16'sd0;
            sine_next_q <= 16'sd0;
            sine_interp_q <= 16'sd0;
            sine_frac_q <= 8'd0;

            for (i = 0; i < 32; i = i + 1) begin
                phase_acc[i] <= 32'd0;
                env_level[i] <= 15'd0;
                env_state[i] <= STATE_IDLE;
            end

        end
        else begin

            // Start a new 48kHz audio frame
            if (sample_en && !engine_busy) begin

                voice_index <= 6'd0;
                process_stage <= 2'd0;

                mix_acc <= 22'sd0;
                finalize_pending <= 1'b0;

                engine_busy <= 1'b1;

            end
            else if (engine_busy) begin

                // ==========================================
                // Final stage after all 32 voices
                // ==========================================
                if (finalize_pending) begin

                    mix_pcm <= mixed_pcm_next;

                    mix_acc <= 22'sd0;
                    finalize_pending <= 1'b0;
                    engine_busy <= 1'b0;

                end

                // ==========================================
                // Stage 0: ROM base + bend product
                // ==========================================
                else if (process_stage == 2'd0) begin

                    base_fcw_q <= current_fcw;
                    bend_product_q <= bend_product;

                    sine_base_q <= sine_rom_data;
                    sine_frac_q <= current_phase[21:14];

                    process_stage <= 2'd1;

                end

                // ==========================================
                // Stage 1: next ROM sample
                // ==========================================
                else if (process_stage == 2'd1) begin

                    sine_next_q <= sine_rom_data;
                    process_stage <= 2'd2;

                end

                // ==========================================
                // Stage 2: sine interpolation
                // ==========================================
                else if (process_stage == 2'd2) begin

                    sine_interp_q <= sine_interp_sum[15:0];
                    process_stage <= 2'd3;

                end

                // ==========================================
                // Stage 3: DDS + ADSR + mixing
                // ==========================================
                else begin

                    process_stage <= 2'd0;

                    // Update phase accumulator
                    phase_acc[voice_index] <=
                        phase_acc[voice_index] + bent_fcw;

                    // ADSR state machine
                    case (env_state[voice_index])

                        STATE_IDLE: begin

                            env_level[voice_index] <=
                                15'd0;

                            if (gate_mask[voice_index])
                                env_state[voice_index] <=
                                    STATE_ATTACK;

                        end

                        STATE_ATTACK: begin

                            if (!gate_mask[voice_index]) begin

                                env_state[voice_index] <=
                                    STATE_RELEASE;

                            end
                            else if (
                                env_level[voice_index] >=
                                (MAX_LEVEL - ATTACK_STEP)
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

                        STATE_DECAY: begin

                            if (!gate_mask[voice_index]) begin

                                env_state[voice_index] <=
                                    STATE_RELEASE;

                            end
                            else if (
                                env_level[voice_index] <=
                                (SUSTAIN_LEVEL + DECAY_STEP)
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

                        STATE_SUSTAIN: begin

                            env_level[voice_index] <=
                                SUSTAIN_LEVEL;

                            if (!gate_mask[voice_index])
                                env_state[voice_index] <=
                                    STATE_RELEASE;

                        end

                        STATE_RELEASE: begin

                            if (gate_mask[voice_index]) begin

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

                        default: begin

                            env_level[voice_index] <=
                                15'd0;

                            env_state[voice_index] <=
                                STATE_IDLE;

                        end

                    endcase

                    // --------------------------------------
                    // Finish voice or move to next voice
                    // --------------------------------------

                    if (voice_index == 6'd31) begin

                        // Register full 32-voice result.
                        // Protection runs in following clock.
                        mix_acc <= mix_acc_next;

                        voice_index <= 6'd0;
                        finalize_pending <= 1'b1;

                    end
                    else begin

                        mix_acc <= mix_acc_next;

                        voice_index <=
                            voice_index + 1'b1;

                    end

                end

            end

        end

    end

endmodule
