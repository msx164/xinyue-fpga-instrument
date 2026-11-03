module synth_engine_4 (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               sample_en,

    input  wire               gate0,
    input  wire               gate1,
    input  wire               gate2,
    input  wire               gate3,

    input  wire [31:0]        fcw0,
    input  wire [31:0]        fcw1,
    input  wire [31:0]        fcw2,
    input  wire [31:0]        fcw3,

    output wire signed [15:0] mix_pcm,

    output wire               voice0_active,
    output wire               voice1_active,
    output wire               voice2_active,
    output wire               voice3_active
);

    wire signed [15:0] voice0_pcm;
    wire signed [15:0] voice1_pcm;
    wire signed [15:0] voice2_pcm;
    wire signed [15:0] voice3_pcm;


    // ============================================================
    // Voice 0
    // ============================================================
    synth_voice #(
        .ATTACK_STEP   (15'd14),
        .DECAY_STEP    (15'd3),
        .SUSTAIN_LEVEL (15'd19660),
        .RELEASE_STEP  (15'd2),

        .OUTPUT_SHIFT  (3)
    ) u_voice0 (
        .clk        (clk),
        .rst_n      (rst_n),

        .sample_en  (sample_en),
        .gate       (gate0),

        .fcw        (fcw0),

        .pcm_out    (voice0_pcm),
        .env_active (voice0_active)
    );


    // ============================================================
    // Voice 1
    // ============================================================
    synth_voice #(
        .ATTACK_STEP   (15'd14),
        .DECAY_STEP    (15'd3),
        .SUSTAIN_LEVEL (15'd19660),
        .RELEASE_STEP  (15'd2),

        .OUTPUT_SHIFT  (3)
    ) u_voice1 (
        .clk        (clk),
        .rst_n      (rst_n),

        .sample_en  (sample_en),
        .gate       (gate1),

        .fcw        (fcw1),

        .pcm_out    (voice1_pcm),
        .env_active (voice1_active)
    );


    // ============================================================
    // Voice 2
    // ============================================================
    synth_voice #(
        .ATTACK_STEP   (15'd14),
        .DECAY_STEP    (15'd3),
        .SUSTAIN_LEVEL (15'd19660),
        .RELEASE_STEP  (15'd2),

        .OUTPUT_SHIFT  (3)
    ) u_voice2 (
        .clk        (clk),
        .rst_n      (rst_n),

        .sample_en  (sample_en),
        .gate       (gate2),

        .fcw        (fcw2),

        .pcm_out    (voice2_pcm),
        .env_active (voice2_active)
    );


    // ============================================================
    // Voice 3
    // ============================================================
    synth_voice #(
        .ATTACK_STEP   (15'd14),
        .DECAY_STEP    (15'd3),
        .SUSTAIN_LEVEL (15'd19660),
        .RELEASE_STEP  (15'd2),

        .OUTPUT_SHIFT  (3)
    ) u_voice3 (
        .clk        (clk),
        .rst_n      (rst_n),

        .sample_en  (sample_en),
        .gate       (gate3),

        .fcw        (fcw3),

        .pcm_out    (voice3_pcm),
        .env_active (voice3_active)
    );


    // ============================================================
    // 4-Voice mixer
    // ============================================================
    audio_mixer_4 u_mixer (
        .voice0_pcm (voice0_pcm),
        .voice1_pcm (voice1_pcm),
        .voice2_pcm (voice2_pcm),
        .voice3_pcm (voice3_pcm),

        .mix_pcm    (mix_pcm)
    );

endmodule