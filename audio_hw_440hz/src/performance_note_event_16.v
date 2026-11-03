
`timescale 1ns/1ps

module performance_note_event_16 #(
    parameter integer DEBOUNCE_CYCLES   = 960000,
    parameter integer SCALE_HOLD_CYCLES = 24000000
)(
    input  wire        clk,
    input  wire        rst_n,

    // FPGA buttons, active LOW
    input  wire        key0_n,
    input  wire        key1_n,

    // TTP229
    input  wire [15:0] touch_keys,
    input  wire        touch_update,

    // Registered Note Event output (B5-E-1)
    output reg         event_valid,
    output reg         event_on,
    output reg  [6:0]  event_note,
    output reg  [31:0] event_fcw,

    // Mode status
    output reg  [1:0]  octave_mode,
    output reg         scale_mode,

    // Debug
    output wire [15:0] sent_keys,
    output wire        busy
);

    // =====================================================
    // 1. Button synchronizers
    // =====================================================

    reg [1:0] key0_sync;
    reg [1:0] key1_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key0_sync <= 2'b11;
            key1_sync <= 2'b11;
        end
        else begin
            key0_sync <= {key0_sync[0], key0_n};
            key1_sync <= {key1_sync[0], key1_n};
        end
    end

    // =====================================================
    // 2. Button debounce
    // =====================================================

    reg key0_stable;
    reg key1_stable;

    reg [31:0] key0_count;
    reg [31:0] key1_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key0_stable <= 1'b1;
            key1_stable <= 1'b1;
            key0_count  <= 32'd0;
            key1_count  <= 32'd0;
        end
        else begin
            if (key0_sync[1] == key0_stable) begin
                key0_count <= 32'd0;
            end
            else if (key0_count == DEBOUNCE_CYCLES-1) begin
                key0_stable <= key0_sync[1];
                key0_count  <= 32'd0;
            end
            else begin
                key0_count <= key0_count + 1'b1;
            end

            if (key1_sync[1] == key1_stable) begin
                key1_count <= 32'd0;
            end
            else if (key1_count == DEBOUNCE_CYCLES-1) begin
                key1_stable <= key1_sync[1];
                key1_count  <= 32'd0;
            end
            else begin
                key1_count <= key1_count + 1'b1;
            end
        end
    end

    // =====================================================
    // 3. Original TTP229 Note Event Generator
    // =====================================================

    wire       base_valid;
    wire       base_on;
    wire [6:0] base_note;
    wire       base_busy;

    touch_note_event_16 u_base_events (
        .clk          (clk),
        .rst_n        (rst_n),

        .touch_keys   (touch_keys),
        .touch_update (touch_update),

        .event_valid  (base_valid),
        .event_on     (base_on),
        .event_note   (base_note),
        .event_fcw    (),

        .sent_keys    (sent_keys),
        .busy         (base_busy)
    );

    // =====================================================
    // 4. B5-E-1: Busy includes the new pipeline stage
    // =====================================================

    assign busy =
        base_busy |
        base_valid |
        event_valid;

    wire safe_idle;

    assign safe_idle =
        (touch_keys == 16'd0) &&
        (sent_keys  == 16'd0) &&
        !base_busy &&
        !base_valid &&
        !event_valid &&
        !(touch_update && (touch_keys != 16'd0));

    // =====================================================
    // 5. Button gesture control
    //
    // KEY0 tap      : Octave Down
    // KEY1 tap      : Octave Up
    // Both long hold: Toggle Scale
    // =====================================================

    reg session_active;
    reg seen0;
    reg seen1;
    reg blocked;
    reg long_en;

    reg [31:0] hold_count;

    wire down0;
    wire down1;

    assign down0 = ~key0_stable;
    assign down1 = ~key1_stable;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            octave_mode    <= 2'd1;
            scale_mode     <= 1'b0;

            session_active <= 1'b0;
            seen0          <= 1'b0;
            seen1          <= 1'b0;
            blocked        <= 1'b0;
            long_en        <= 1'b0;
            hold_count     <= 32'd0;
        end
        else begin

            // At least one physical button is pressed
            if (down0 || down1) begin

                session_active <= 1'b1;

                if (down0)
                    seen0 <= 1'b1;

                if (down1)
                    seen1 <= 1'b1;

                if (!safe_idle)
                    blocked <= 1'b1;

                // Both buttons held
                if (down0 && down1) begin

                    if (hold_count < SCALE_HOLD_CYCLES)
                        hold_count <= hold_count + 1'b1;

                    if (hold_count >= SCALE_HOLD_CYCLES-1)
                        long_en <= 1'b1;
                end
                else begin
                    hold_count <= 32'd0;
                end
            end

            // Both buttons released
            else if (session_active) begin

                if (!blocked && safe_idle) begin

                    // Both buttons participated
                    if (seen0 && seen1) begin

                        if (long_en)
                            scale_mode <= ~scale_mode;
                    end

                    // KEY0 only: octave down
                    else if (seen0) begin

                        if (octave_mode > 2'd0)
                            octave_mode <= octave_mode - 1'b1;
                    end

                    // KEY1 only: octave up
                    else if (seen1) begin

                        if (octave_mode < 2'd2)
                            octave_mode <= octave_mode + 1'b1;
                    end
                end

                // End gesture session
                session_active <= 1'b0;
                seen0          <= 1'b0;
                seen1          <= 1'b0;
                blocked        <= 1'b0;
                long_en        <= 1'b0;
                hold_count     <= 32'd0;
            end
        end
    end

    // =====================================================
    // 6. Recover physical key index
    //
    // Touch 1  -> MIDI 60
    // Touch 16 -> MIDI 75
    // =====================================================

    wire [6:0] key_offset;
    wire [3:0] key_index;

    assign key_offset = base_note - 7'd60;
    assign key_index  = key_offset[3:0];

    // =====================================================
    // 7. Scale and FCW mapping
    // =====================================================

    wire [6:0]  mapped_note;
    wire [31:0] mapped_fcw;

    scale_map_16 u_scale_map (
        .key_index   (key_index),
        .octave_mode (octave_mode),
        .scale_mode  (scale_mode),

        .midi_note   (mapped_note),
        .note_fcw    (mapped_fcw)
    );

    // =====================================================
    // 8. B5-E-1: Registered Note Event Pipeline
    //
    // Register the entire event packet:
    //   valid, on/off, note number, FCW
    //
    // This cuts the combinational path between:
    //   scale_map_16 and voice_allocator_32
    //
    // Latency: one additional 48 MHz clock cycle.
    // Back-to-back valid events remain supported.
    // =====================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            event_valid <= 1'b0;
            event_on    <= 1'b0;
            event_note  <= 7'd0;
            event_fcw   <= 32'd0;
        end
        else begin

            // Pipeline valid flag every cycle
            event_valid <= base_valid;

            // Capture payload only when valid
            if (base_valid) begin
                event_on   <= base_on;
                event_note <= mapped_note;

                // Note Off only needs the MIDI note
                event_fcw <= base_on ?
                             mapped_fcw :
                             32'd0;
            end
        end
    end

endmodule
