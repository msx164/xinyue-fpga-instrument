module synth_voice #(
    parameter [14:0] ATTACK_STEP   = 15'd14,
    parameter [14:0] DECAY_STEP    = 15'd3,
    parameter [14:0] SUSTAIN_LEVEL = 15'd19660,
    parameter [14:0] RELEASE_STEP  = 15'd2,

    parameter integer OUTPUT_SHIFT = 3
)(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               sample_en,
    input  wire               gate,

    input  wire [31:0]        fcw,

    output wire signed [15:0] pcm_out,
    output wire               env_active
);

    // ------------------------------------------------------------
    // DDS output
    // ------------------------------------------------------------
    wire signed [15:0] dds_pcm;


    // ------------------------------------------------------------
    // ADSR envelope
    // ------------------------------------------------------------
    wire [14:0] env_level;


    // ------------------------------------------------------------
    // Signed positive envelope gain
    // ------------------------------------------------------------
    wire signed [15:0] env_gain;


    // ------------------------------------------------------------
    // Multiplication result
    // ------------------------------------------------------------
    wire signed [31:0] env_product;


    // ------------------------------------------------------------
    // ADSR-scaled PCM before final volume reduction
    // ------------------------------------------------------------
    wire signed [15:0] adsr_pcm;


    // ============================================================
    // DDS
    // ============================================================
    dds u_dds (
        .clk       (clk),
        .rst_n     (rst_n),

        .sample_en (sample_en),

        .fcw       (fcw),

        .pcm_out   (dds_pcm)
    );


    // ============================================================
    // ADSR
    // ============================================================
    adsr_envelope #(
        .ATTACK_STEP   (ATTACK_STEP),
        .DECAY_STEP    (DECAY_STEP),
        .SUSTAIN_LEVEL (SUSTAIN_LEVEL),
        .RELEASE_STEP  (RELEASE_STEP)
    ) u_adsr (
        .clk        (clk),
        .rst_n      (rst_n),

        .sample_en  (sample_en),
        .gate       (gate),

        .env_level  (env_level),
        .env_active (env_active)
    );


    // ============================================================
    // Convert unsigned 15-bit envelope to signed positive 16-bit
    // ============================================================
    assign env_gain = {
        1'b0,
        env_level
    };


    // ============================================================
    // Apply ADSR
    //
    // env_level:
    //
    // 32767 ~= 1.0
    // ============================================================
    assign env_product =
        dds_pcm * env_gain;


    assign adsr_pcm =
        env_product >>> 15;


    // ============================================================
    // Final voice output attenuation
    //
    // Default:
    // divide by 8
    //
    // This provides headroom for multi-voice mixing.
    // ============================================================
    assign pcm_out =
        adsr_pcm >>> OUTPUT_SHIFT;


endmodule