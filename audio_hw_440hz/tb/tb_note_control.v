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
    // Audio reset
    // ------------------------------------------------------------
    reg [1:0] rst_sync;

    wire audio_rst_n;


    // ------------------------------------------------------------
    // DDS
    // ------------------------------------------------------------
    wire signed [15:0] dds_pcm;
    wire signed [15:0] safe_pcm;

    wire [31:0] current_fcw;


    // ------------------------------------------------------------
    // Audio frame
    // ------------------------------------------------------------
    wire frame_tick;


    // ------------------------------------------------------------
    // Key signals
    // ------------------------------------------------------------
    wire key0_down;
    wire key1_down;

    wire key0_press_pulse;
    wire key1_press_pulse;

    wire key0_release_pulse;
    wire key1_release_pulse;


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
    // Audio-domain reset
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
    //
    // 48 MHz * 10 ms = 480000
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
    // Note control
    //
    // Power-up:
    // A4 = 440 Hz
    //
    // KEY0 press:
    // A4 = 440 Hz
    //
    // KEY1 press:
    // C5 = 523.251 Hz
    //
    // Task 6.2 does not implement note gating yet.
    // The selected pitch remains active after key release.
    // ============================================================
    note_control u_note_control (
        .clk              (audio_clk),
        .rst_n            (audio_rst_n),

        .key0_press_pulse (key0_press_pulse),
        .key1_press_pulse (key1_press_pulse),

        .fcw              (current_fcw)
    );


    // ============================================================
    // DDS
    // ============================================================
    dds u_dds (
        .clk       (audio_clk),
        .rst_n     (audio_rst_n),

        .sample_en (frame_tick),

        .fcw       (current_fcw),

        .pcm_out   (dds_pcm)
    );


    // ============================================================
    // Safe headphone amplitude
    //
    // 1/8 full-scale amplitude.
    // ============================================================
    assign safe_pcm =
        dds_pcm >>> 3;


    // ============================================================
    // PT8211 transmitter
    // ============================================================
    pt8211_tx_48m u_pt8211_tx (
        .clk_48m      (audio_clk),
        .rst_n        (audio_rst_n),

        .left_sample  (safe_pcm),
        .right_sample (safe_pcm),

        .pt_bck       (HP_BCK),
        .pt_ws        (HP_WS),
        .pt_din       (HP_DIN),

        .frame_tick   (frame_tick)
    );


    // ============================================================
    // Speaker amplifier
    //
    // Keep speaker amplifier disabled.
    // Headphone output is used.
    // ============================================================
    assign PA_EN = 1'b1;


    // ============================================================
    // LED0
    //
    // PLL lock indicator.
    // ============================================================
    assign led_o[0] =
        ~pll_lock;


    // ============================================================
    // LED1 heartbeat
    // ============================================================
    reg [14:0] heartbeat_count;
    reg        heartbeat_led;


    always @(posedge audio_clk or negedge audio_rst_n) begin

        if (!audio_rst_n) begin

            heartbeat_count <= 15'd0;
            heartbeat_led   <= 1'b0;

        end
        else if (frame_tick) begin

            if (heartbeat_count == 15'd23999) begin

                heartbeat_count <= 15'd0;

                heartbeat_led <=
                    ~heartbeat_led;

            end
            else begin

                heartbeat_count <=
                    heartbeat_count + 1'b1;

            end

        end

    end


    assign led_o[1] =
        ~heartbeat_led;


    // ============================================================
    // LED2
    //
    // KEY0 debounced state.
    // ============================================================
    assign led_o[2] =
        ~key0_down;


    // ============================================================
    // LED3
    //
    // KEY1 debounced state.
    // ============================================================
    assign led_o[3] =
        ~key1_down;


endmodule