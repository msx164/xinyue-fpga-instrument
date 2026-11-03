module poly_synth_core_32 #(
    parameter [14:0] ATTACK_STEP   = 15'd14,
    parameter [14:0] DECAY_STEP    = 15'd3,
    parameter [14:0] SUSTAIN_LEVEL = 15'd19660,
    parameter [14:0] RELEASE_STEP  = 15'd2,

    parameter integer OUTPUT_SHIFT = 5
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // ============================================================
    // Audio sample enable
    // ============================================================
    input  wire                 sample_en,

    // ============================================================
    // Note Event input
    // ============================================================
    input  wire                 event_valid,
    input  wire                 event_on,

    input  wire [6:0]           event_note,
    input  wire [31:0]          event_fcw,

    // ============================================================
    // Audio output
    // ============================================================
    output wire signed [15:0]   mix_pcm,

    // ============================================================
    // Debug / status
    // ============================================================
    output wire [31:0]          gate_mask,
    output wire [31:0]          assigned_mask,
    output wire [31:0]          active_mask,

    output wire                 alloc_fail_pulse,
    output wire                 engine_busy
);

    // ============================================================
    // FCW table
    //
    // 32 Voices × 32 bits
    // ============================================================

    wire [1023:0] fcw_flat;


    // ============================================================
    // 32-Voice Allocator
    // ============================================================

    voice_allocator_32 u_voice_allocator (
        .clk              (clk),
        .rst_n            (rst_n),

        .event_valid      (event_valid),
        .event_on         (event_on),

        .event_note       (event_note),
        .event_fcw        (event_fcw),

        .active_mask      (active_mask),

        .gate_mask        (gate_mask),
        .fcw_flat         (fcw_flat),

        .assigned_mask    (assigned_mask),

        .alloc_fail_pulse (alloc_fail_pulse)
    );


    // ============================================================
    // 32-Voice TDM Synthesizer Engine
    // ============================================================

    synth_engine_tdm_32 #(
        .ATTACK_STEP   (ATTACK_STEP),
        .DECAY_STEP    (DECAY_STEP),
        .SUSTAIN_LEVEL (SUSTAIN_LEVEL),
        .RELEASE_STEP  (RELEASE_STEP),

        .OUTPUT_SHIFT  (OUTPUT_SHIFT)
    ) u_synth_engine (
        .clk         (clk),
        .rst_n       (rst_n),

        .sample_en   (sample_en),

        .gate_mask   (gate_mask),
        .fcw_flat    (fcw_flat),

        .mix_pcm     (mix_pcm),

        .active_mask (active_mask),

        .engine_busy (engine_busy)
    );


endmodule