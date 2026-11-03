module top (
    input  wire       sys_clk,

    input  wire       key0,
    input  wire       key1,

    output wire       HP_BCK,
    output wire       HP_WS,
    output wire       HP_DIN,

    output wire       PA_EN,

    output wire [3:0] led_o
);

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------
    wire audio_clk;
    wire pll_lock;


    // ------------------------------------------------------------
    // Reset
    // ------------------------------------------------------------
    reg [1:0] rst_sync;

    wire audio_rst_n;


    // ------------------------------------------------------------
    // Audio frame
    // ------------------------------------------------------------
    wire frame_tick;


    // ------------------------------------------------------------
    // Debounced key signals
    // ------------------------------------------------------------
    wire key0_down;
    wire key1_down;

    wire key0_press_pulse;
    wire key1_press_pulse;

    wire key0_release_pulse;
    wire key1_release_pulse;


    // ------------------------------------------------------------
    // Note Event Bus
    // ------------------------------------------------------------
    wire        event_valid;
    wire        event_on;

    wire [6:0]  event_note;
    wire [31:0] event_fcw;


    // ------------------------------------------------------------
    // Voice allocator outputs
    // ------------------------------------------------------------
    wire gate0;
    wire gate1;
    wire gate2;
    wire gate3;

    wire [31:0] fcw0;
    wire [31:0] fcw1;
    wire [31:0] fcw2;
    wire [31:0] fcw3;


    wire [3:0] assigned_mask;

    wire alloc_fail_pulse;


    // ------------------------------------------------------------
    // Voice activity feedback
    // ------------------------------------------------------------
    wire voice0_active;
    wire voice1_active;
    wire voice2_active;
    wire voice3_active;


    // ------------------------------------------------------------
    // Mixed audio
    // ------------------------------------------------------------
    wire signed [15:0] mix_pcm;


    // ============================================================
    // PLL
    //
    // 50 MHz -> 48 MHz
    // ============================================================
    Gowin_PLL u_pll (
        .clkin   (sys_clk),
        .clkout0 (audio_clk),
        .mdclk   (sys_clk),
        .lock    (pll_lock)
    );


    // ============================================================
    // Reset synchronization
    // ============================================================
    always @(posedge audio_clk or negedge pll_lock) begin

        if (!pll_lock) begin

            rst_sync <= 2'b00;

        end
        else begin

            rst_sync <= {
                rst_sync[0],
                1'b1
            };

        end

    end


    assign audio_rst_n =
        rst_sync[1];


    // ============================================================
    // KEY0 debounce
    // ============================================================
    key_debounce #(
        .DEBOUNCE_COUNT(480000)
    ) u_key0_debounce (
        .clk               (audio_clk),
        .rst_n             (audio_rst_n),

        .key_in_n          (key0),

        .key_down          (key0_down),
        .key_press_pulse   (key0_press_pulse),
        .key_release_pulse (key0_release_pulse)
    );


    // ============================================================
    // KEY1 debounce
    // ============================================================
    key_debounce #(
        .DEBOUNCE_COUNT(480000)
    ) u_key1_debounce (
        .clk               (audio_clk),
        .rst_n             (audio_rst_n),

        .key_in_n          (key1),

        .key_down          (key1_down),
        .key_press_pulse   (key1_press_pulse),
        .key_release_pulse (key1_release_pulse)
    );


    // ============================================================
    // Physical Key -> Note Event
    // ============================================================
    key_note_event_2 u_key_note_event (
        .clk                (audio_clk),
        .rst_n              (audio_rst_n),

        .key0_press_pulse   (key0_press_pulse),
        .key0_release_pulse (key0_release_pulse),

        .key1_press_pulse   (key1_press_pulse),
        .key1_release_pulse (key1_release_pulse),

        .event_valid        (event_valid),
        .event_on           (event_on),
        .event_note         (event_note),
        .event_fcw          (event_fcw)
    );


    // ============================================================
    // 4-Voice Allocator
    // ============================================================
    voice_allocator_4 u_voice_allocator (
        .clk              (audio_clk),
        .rst_n            (audio_rst_n),

        .event_valid      (event_valid),
        .event_on         (event_on),

        .event_note       (event_note),
        .event_fcw        (event_fcw),

        .voice0_active    (voice0_active),
        .voice1_active    (voice1_active),
        .voice2_active    (voice2_active),
        .voice3_active    (voice3_active),

        .gate0            (gate0),
        .gate1            (gate1),
        .gate2            (gate2),
        .gate3            (gate3),

        .fcw0             (fcw0),
        .fcw1             (fcw1),
        .fcw2             (fcw2),
        .fcw3             (fcw3),

        .assigned_mask    (assigned_mask),

        .alloc_fail_pulse (alloc_fail_pulse)
    );


    // ============================================================
    // 4-Voice Synth Engine
    // ============================================================
    synth_engine_4 u_synth_engine (
        .clk           (audio_clk),
        .rst_n         (audio_rst_n),

        .sample_en     (frame_tick),

        .gate0         (gate0),
        .gate1         (gate1),
        .gate2         (gate2),
        .gate3         (gate3),

        .fcw0          (fcw0),
        .fcw1          (fcw1),
        .fcw2          (fcw2),
        .fcw3          (fcw3),

        .mix_pcm       (mix_pcm),

        .voice0_active (voice0_active),
        .voice1_active (voice1_active),
        .voice2_active (voice2_active),
        .voice3_active (voice3_active)
    );


    // ============================================================
    // PT8211
    // ============================================================
    pt8211_tx_48m u_pt8211_tx (
        .clk_48m      (audio_clk),
        .rst_n        (audio_rst_n),

        .left_sample  (mix_pcm),
        .right_sample (mix_pcm),

        .pt_bck       (HP_BCK),
        .pt_ws        (HP_WS),
        .pt_din       (HP_DIN),

        .frame_tick   (frame_tick)
    );


    // ============================================================
    // Speaker amplifier disabled
    //
    // Headphone output is used.
    // ============================================================
    assign PA_EN =
        1'b1;


    // ============================================================
    // Debug LEDs
    //
    // Show allocator occupancy directly.
    //
    // LED0 -> Voice0 assigned
    // LED1 -> Voice1 assigned
    // LED2 -> Voice2 assigned
    // LED3 -> Voice3 assigned
    //
    // LEDs are active-low.
    // ============================================================
    assign led_o[0] =
        ~assigned_mask[0];

    assign led_o[1] =
        ~assigned_mask[1];

    assign led_o[2] =
        ~assigned_mask[2];

    assign led_o[3] =
        ~assigned_mask[3];


endmodule