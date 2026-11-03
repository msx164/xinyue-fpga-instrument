`timescale 1ns/1ps

module top (
    input  wire sys_clk,
    input  wire key0,
    input  wire key1,
    input  wire ttp_sdo,
    output wire ttp_scl,

    output wire HP_BCK,
    output wire HP_WS,
    output wire HP_DIN,
    output wire PA_EN,

    // Independent Philips I2S output for PCM5102A
    output wire i2s_bck,
    output wire i2s_lrck,
    output wire i2s_din,

    // ADS1015 ALERT/RDY
    input  wire ads_alrt_n,

    output wire [3:0] led_o,
    inout wire ads_scl,
    inout wire ads_sda,

    // NEW: Independent SSD1306 OLED I2C
    inout wire oled_scl,
    inout wire oled_sda
);

    // =====================================================
    // B5-D configuration
    // OLED display integration
    // =====================================================

    localparam integer VOICE_OUTPUT_SHIFT = 3;
    localparam integer SINE_INTERP_ENABLE = 1;
    localparam integer MIX_PROTECT_MODE = 1;

    // MIX_PREGAIN_SHIFT = 1 is retained in the B5-C
    // synthesizer module. Do not replace that module.

    localparam integer KEY_DEBOUNCE_CYCLES = 960000;
    localparam integer SCALE_HOLD_CYCLES = 24000000;
    localparam integer COMBO_MIN_CYCLES = 960000;
    localparam integer COMBO_MAX_CYCLES = 9600000;

    // =====================================================
    // 1. PLL: 50 MHz -> 48 MHz
    // =====================================================

    wire audio_clk;
    wire pll_lock;

    Gowin_PLL u_pll (
        .clkin   (sys_clk),
        .clkout0 (audio_clk),
        .mdclk   (sys_clk),
        .lock    (pll_lock)
    );

    reg [1:0] rst_sync;

    always @(posedge audio_clk or negedge pll_lock) begin
        if (!pll_lock)
            rst_sync <= 2'b00;
        else
            rst_sync <= {rst_sync[0], 1'b1};
    end

    wire audio_rst_n = rst_sync[1];

    // =====================================================
    // 2. TTP229
    // =====================================================

    wire [15:0] touch_keys;
    wire scan_valid;

    ttp229_reader #(
        .POWERUP_CYCLES     (24000000),
        .SCAN_GAP_CYCLES    (96000),
        .HALF_PERIOD_CYCLES (240)
    ) u_ttp229_reader (
        .clk        (audio_clk),
        .rst_n      (audio_rst_n),
        .ttp_scl    (ttp_scl),
        .ttp_sdo    (ttp_sdo),
        .key_state  (touch_keys),
        .scan_valid (scan_valid)
    );

    // =====================================================
    // 3. TTP229 scan watchdog
    // =====================================================

    localparam [21:0] SCAN_TIMEOUT = 22'd2400000;
    reg [21:0] scan_age;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n)
            scan_age <= SCAN_TIMEOUT;
        else if (scan_valid)
            scan_age <= 22'd0;
        else if (scan_age < SCAN_TIMEOUT)
            scan_age <= scan_age + 1'b1;
    end

    wire scan_alive = (scan_age < SCAN_TIMEOUT);
    wire touch_any = |touch_keys;

    // =====================================================
    // 4. Note events
    // =====================================================

    wire event_valid;
    wire event_on;
    wire [6:0] event_note;
    wire [31:0] event_fcw;
    wire [1:0] octave_mode;
    wire scale_mode;
    wire [15:0] sent_keys;
    wire event_busy;

    performance_note_event_16 #(
        .DEBOUNCE_CYCLES   (KEY_DEBOUNCE_CYCLES),
        .SCALE_HOLD_CYCLES (SCALE_HOLD_CYCLES)
    ) u_performance_note_event (
        .clk          (audio_clk),
        .rst_n        (audio_rst_n),
        .key0_n       (key0),
        .key1_n       (key1),
        .touch_keys   (touch_keys),
        .touch_update (scan_valid),
        .event_valid  (event_valid),
        .event_on     (event_on),
        .event_note   (event_note),
        .event_fcw    (event_fcw),
        .octave_mode  (octave_mode),
        .scale_mode   (scale_mode),
        .sent_keys    (sent_keys),
        .busy         (event_busy)
    );

    // =====================================================
    // 5. Synth status
    // =====================================================

    wire [31:0] gate_mask;
    wire [31:0] assigned_mask;
    wire [31:0] active_mask;
    wire engine_busy;
    wire signed [15:0] mix_pcm;
    wire frame_tick;

    // =====================================================
    // 6. Timbre switching
    // =====================================================

    reg [1:0] key0_sync;
    reg [1:0] key1_sync;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            key0_sync <= 2'b11;
            key1_sync <= 2'b11;
        end
        else begin
            key0_sync <= {key0_sync[0], key0};
            key1_sync <= {key1_sync[0], key1};
        end
    end

    wire both_down = !key0_sync[1] && !key1_sync[1];
    wire both_up = key0_sync[1] && key1_sync[1];

    reg timbre_sel;
    reg combo_session;
    reg combo_both_seen;
    reg combo_short_seen;
    reg combo_long_seen;
    reg combo_blocked;
    reg [23:0] combo_count;

    wire control_idle =
        (touch_keys == 16'd0) &&
        (sent_keys == 16'd0) &&
        (gate_mask == 32'd0) &&
        (active_mask == 32'd0) &&
        (assigned_mask == 32'd0) &&
        (mix_pcm == 16'sd0) &&
        !event_busy;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            timbre_sel <= 1'b0;
            combo_session <= 1'b0;
            combo_both_seen <= 1'b0;
            combo_short_seen <= 1'b0;
            combo_long_seen <= 1'b0;
            combo_blocked <= 1'b0;
            combo_count <= 24'd0;
        end
        else begin
            if (!both_up) begin
                combo_session <= 1'b1;

                if (!control_idle)
                    combo_blocked <= 1'b1;

                if (both_down) begin
                    combo_both_seen <= 1'b1;

                    if (combo_count < COMBO_MAX_CYCLES)
                        combo_count <= combo_count + 1'b1;

                    if (combo_count >= COMBO_MIN_CYCLES-1)
                        combo_short_seen <= 1'b1;

                    if (combo_count >= COMBO_MAX_CYCLES-1)
                        combo_long_seen <= 1'b1;
                end
            end
            else if (combo_session) begin
                if (
                    combo_both_seen &&
                    combo_short_seen &&
                    !combo_long_seen &&
                    !combo_blocked &&
                    control_idle
                ) begin
                    timbre_sel <= ~timbre_sel;
                end

                combo_session <= 1'b0;
                combo_both_seen <= 1'b0;
                combo_short_seen <= 1'b0;
                combo_long_seen <= 1'b0;
                combo_blocked <= 1'b0;
                combo_count <= 24'd0;
            end
        end
    end

    // =====================================================
    // 7. ADS1015 + ALERT/RDY
    // =====================================================

    wire [15:0] adc0;
    wire [15:0] adc1;
    wire [15:0] adc2;
    wire [15:0] adc3;
    wire adc_valid;

    ads1115_pressure4 u_adc (
        .clk              (audio_clk),
        .rst_n            (audio_rst_n),
        .scl              (ads_scl),
        .sda              (ads_sda),
        .alrt_n           (ads_alrt_n),
        .value0           (adc0),
        .value1           (adc1),
        .value2           (adc2),
        .value3           (adc3),
        .sample_valid     (adc_valid),
        .ack_error        (),
        .rdy_timeout_seen ()
    );

    // =====================================================
    // 8. ADC freshness watchdog
    // =====================================================

    localparam [13:0] ADC_STALE_FRAMES = 14'd9600;

    reg [13:0] adc_age_frames;
    reg adc_sample_seen;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            adc_age_frames <= 14'd0;
            adc_sample_seen <= 1'b0;
        end
        else if (adc_valid) begin
            adc_age_frames <= 14'd0;
            adc_sample_seen <= 1'b1;
        end
        else if (
            frame_tick &&
            adc_age_frames < ADC_STALE_FRAMES
        ) begin
            adc_age_frames <= adc_age_frames + 1'b1;
        end
    end

    wire adc_stream_ok =
        adc_sample_seen &&
        (adc_age_frames < ADC_STALE_FRAMES);

    // =====================================================
    // 9. FSR calibration function
    // =====================================================

    function [8:0] fsr_map;
        input [15:0] adc;
        input [8:0] p1;
        input [8:0] p2;
        input [8:0] p3;
        input [8:0] p4;
        input [8:0] s1;
        input [8:0] s2;
        input [8:0] s3;
        input [8:0] s4;

        reg [15:0] delta;
        reg [24:0] product;

        begin
            delta = 16'd0;
            product = 25'd0;
            fsr_map = 9'd0;

            if (adc[15]) begin
                fsr_map = 9'd0;
            end
            else if (adc <= 16'd8000) begin
                delta = adc;
                product = delta * s1;
                fsr_map = product >> 13;
            end
            else if (adc <= 16'd16000) begin
                delta = adc - 16'd8000;
                product = delta * s2;
                fsr_map = p1 + (product >> 13);
            end
            else if (adc <= 16'd24000) begin
                delta = adc - 16'd16000;
                product = delta * s3;
                fsr_map = p2 + (product >> 13);
            end
            else if (adc <= 16'd24800) begin
                delta = adc - 16'd24000;
                product = delta * s4;
                fsr_map = p3 + (product >> 10);
            end
            else begin
                fsr_map = p4;
            end
        end
    endfunction

    // =====================================================
    // 10. Four FSR mapping curves
    // =====================================================

    wire [8:0] fsr1_level_raw =
        fsr_map(
            adc0,
            9'd24, 9'd64, 9'd180, 9'd255,
            9'd25, 9'd41, 9'd119, 9'd96
        );

    wire [8:0] fsr2_depth_raw =
        fsr_map(
            adc1,
            9'd30, 9'd70, 9'd125, 9'd160,
            9'd31, 9'd41, 9'd57, 9'd45
        );

    wire [8:0] fsr3_bend_raw =
        fsr_map(
            adc2,
            9'd40, 9'd160, 9'd420, 9'd502,
            9'd41, 9'd123, 9'd267, 9'd105
        );

    wire [8:0] fsr4_echo_raw =
        fsr_map(
            adc3,
            9'd20, 9'd50, 9'd120, 9'd160,
            9'd21, 9'd31, 9'd72, 9'd52
        );

    // =====================================================
    // 11. FSR1 volume
    // =====================================================

    wire [7:0] fsr1_level = fsr1_level_raw[7:0];

    wire [15:0] fsr1_gain_product =
        fsr1_level * 8'd150;

    wire [7:0] fsr1_target_gain =
        8'd40 + fsr1_gain_product[15:8];

    wire [7:0] target_gain =
        adc_stream_ok ? fsr1_target_gain : 8'd40;

    reg signed [24:0] gain_smooth_q16;

    wire signed [24:0] target_gain_q16 =
        $signed({1'b0, target_gain, 16'd0});

    wire signed [24:0] gain_diff =
        target_gain_q16 - gain_smooth_q16;

    wire signed [24:0] gain_step =
        gain_diff >>> 9;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            gain_smooth_q16 <=
                $signed({1'b0, 8'd40, 16'd0});
        end
        else if (frame_tick) begin
            gain_smooth_q16 <=
                gain_smooth_q16 + gain_step;
        end
    end

    wire [7:0] volume_gain =
        gain_smooth_q16[23:16];

    // =====================================================
    // 12. FSR2 tremolo depth
    // =====================================================

    wire [7:0] fsr2_depth_target =
        adc_stream_ok ? fsr2_depth_raw[7:0] : 8'd0;

    reg [7:0] fsr2_depth;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n)
            fsr2_depth <= 8'd0;
        else if (frame_tick) begin
            if (fsr2_depth < fsr2_depth_target)
                fsr2_depth <= fsr2_depth + 1'b1;
            else if (fsr2_depth > fsr2_depth_target)
                fsr2_depth <= fsr2_depth - 1'b1;
        end
    end

    // =====================================================
    // 13. FSR3 pitch bend
    // =====================================================

    wire [8:0] bend_target =
        adc_stream_ok ? fsr3_bend_raw : 9'd0;

    reg [8:0] bend_q12;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            bend_q12 <= 9'd0;
        end
        else if (frame_tick) begin
            if (bend_q12 < bend_target) begin
                if ((bend_target - bend_q12) <= 9'd3)
                    bend_q12 <= bend_target;
                else
                    bend_q12 <= bend_q12 + 9'd3;
            end
            else if (bend_q12 > bend_target) begin
                if ((bend_q12 - bend_target) <= 9'd3)
                    bend_q12 <= bend_target;
                else
                    bend_q12 <= bend_q12 - 9'd3;
            end
        end
    end

    // =====================================================
    // 14. B5-C synthesizer
    // =====================================================

    poly_synth_core_32_dualtimbre #(
        .ATTACK_STEP       (15'd14),
        .DECAY_STEP        (15'd3),
        .SUSTAIN_LEVEL     (15'd19660),
        .RELEASE_STEP      (15'd2),
        .OUTPUT_SHIFT      (VOICE_OUTPUT_SHIFT),
        .SINE_INTERP_ENABLE(SINE_INTERP_ENABLE),
        .MIX_PROTECT_MODE  (MIX_PROTECT_MODE)
    ) u_poly_synth (
        .clk              (audio_clk),
        .rst_n            (audio_rst_n),
        .sample_en        (frame_tick),
        .event_valid      (event_valid),
        .event_on         (event_on),
        .event_note       (event_note),
        .event_fcw        (event_fcw),
        .timbre_sel       (timbre_sel),
        .bend_q12         (bend_q12),
        .mix_pcm          (mix_pcm),
        .gate_mask        (gate_mask),
        .assigned_mask    (assigned_mask),
        .active_mask      (active_mask),
        .alloc_fail_pulse (),
        .engine_busy      (engine_busy)
    );

    // =====================================================
    // 15. Tremolo LFO
    // =====================================================

    reg [23:0] lfo_phase;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n)
            lfo_phase <= 24'd0;
        else if (frame_tick)
            lfo_phase <= lfo_phase + 24'd2097;
    end

    wire [7:0] lfo_triangle =
        lfo_phase[23] ?
        ~lfo_phase[22:15] :
         lfo_phase[22:15];

    wire [15:0] modulation_product =
        fsr2_depth * lfo_triangle;

    wire [7:0] tremolo_gain =
        8'd255 - modulation_product[15:8];

    // =====================================================
    // 16. High-resolution volume and tremolo
    // =====================================================

    wire signed [16:0] volume_coeff_q8 =
        $signed({
            1'b0,
            volume_gain,
            gain_smooth_q16[15:8]
        });

    wire signed [8:0] tremolo_coeff =
        $signed({1'b0, tremolo_gain});

    reg signed [32:0] volume_product_q;
    reg signed [24:0] tremolo_product_q;

    wire signed [15:0] volume_pcm =
        volume_product_q >>> 16;

    always @(posedge audio_clk or negedge audio_rst_n) begin
        if (!audio_rst_n) begin
            volume_product_q <= 33'sd0;
            tremolo_product_q <= 25'sd0;
        end
        else begin
            volume_product_q <=
                mix_pcm * volume_coeff_q8;

            tremolo_product_q <=
                volume_pcm * tremolo_coeff;
        end
    end

    wire signed [15:0] pcm_after_tremolo =
        tremolo_product_q >>> 8;

    // =====================================================
    // 17. FSR4 echo
    // =====================================================

    wire [7:0] echo_wet_target =
        adc_stream_ok ? fsr4_echo_raw[7:0] : 8'd0;

    wire signed [15:0] pcm_to_dac;

    audio_echo #(
        .ADDR_BITS(13)
    ) u_audio_echo (
        .clk        (audio_clk),
        .rst_n      (audio_rst_n),
        .sample_en  (frame_tick),
        .dry_pcm    (pcm_after_tremolo),
        .wet_target (echo_wet_target),
        .pcm_out    (pcm_to_dac)
    );

    // =====================================================
    // 18. PT8211 + independent PCM5102A I2S dual output
    // =====================================================

    localparam integer PCM5102A_TEST_TONE = 0;
    wire i2s_diag_lrck;

    pt8211_tx_48m u_pt8211 (
        .clk_48m      (audio_clk),
        .rst_n        (audio_rst_n),

        .left_sample  (pcm_to_dac),
        .right_sample (pcm_to_dac),

        .pt_bck       (HP_BCK),
        .pt_ws        (HP_WS),
        .pt_din       (HP_DIN),

        // Legacy wrapper LRCK is unused by external PCM5102A.
        .i2s_lrck     (i2s_diag_lrck),

        .frame_tick   (frame_tick)
    );

    // B5-F: independent Philips I2S transmitter
    i2s_pcm5102a_tx_48m #(
        .TEST_TONE_ENABLE(PCM5102A_TEST_TONE)
    ) u_pcm5102a_i2s (
        .clk_48m      (audio_clk),
        .rst_n        (audio_rst_n),
        .left_sample  (pcm_to_dac),
        .right_sample (pcm_to_dac),
        .i2s_bck      (i2s_bck),
        .i2s_lrck     (i2s_lrck),
        .i2s_din      (i2s_din)
    );

    assign PA_EN = 1'b0;

    // =====================================================
    // 19. Diagnostic LEDs (active LOW)
    // =====================================================

    assign led_o[0] = ~scan_alive;
    assign led_o[1] = ~touch_any;
    assign led_o[2] = ~(|gate_mask);
    assign led_o[3] = adc_stream_ok;

// =====================================================
// 20. SSD1306 OLED status display
//
// Compatible with OLED module ports:
// current_note
// timbre_sel
// active_voices
//
// Does NOT modify the audio path.
// =====================================================


// -----------------------------------------------------
// 1. Remember the last played note
// -----------------------------------------------------

reg [6:0] oled_last_note;

always @(posedge audio_clk or negedge audio_rst_n) begin

    if (!audio_rst_n)
        oled_last_note <= 7'd60;   // C4

    else if (event_valid && event_on)
        oled_last_note <= event_note;

end


// -----------------------------------------------------
// 2. Count active synthesizer voices
// -----------------------------------------------------

function [2:0] oled_popcount4;

    input [3:0] bits;

    begin
        oled_popcount4 =
            {2'b00, bits[0]} +
            {2'b00, bits[1]} +
            {2'b00, bits[2]} +
            {2'b00, bits[3]};
    end

endfunction


wire [5:0] oled_voice_count =
    {3'b000, oled_popcount4(active_mask[3:0])} +
    {3'b000, oled_popcount4(active_mask[7:4])} +
    {3'b000, oled_popcount4(active_mask[11:8])} +
    {3'b000, oled_popcount4(active_mask[15:12])} +
    {3'b000, oled_popcount4(active_mask[19:16])} +
    {3'b000, oled_popcount4(active_mask[23:20])} +
    {3'b000, oled_popcount4(active_mask[27:24])} +
    {3'b000, oled_popcount4(active_mask[31:28])};


// -----------------------------------------------------
// 3. SSD1306 OLED instance
// -----------------------------------------------------

ssd1306_status_i2c #(
    .CLK_HZ(48000000),
    .I2C_HZ(100000)
) u_oled_status (

    .clk           (audio_clk),
    .rst_n         (audio_rst_n),

    .current_note  (oled_last_note),
    .timbre_sel    (timbre_sel),
    .active_voices (oled_voice_count),

    .oled_scl      (oled_scl),
    .oled_sda      (oled_sda)

);

endmodule