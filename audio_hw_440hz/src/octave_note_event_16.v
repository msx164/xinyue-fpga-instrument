module octave_note_event_16 #(
    parameter integer DEBOUNCE_CYCLES = 960000
)(
    input  wire        clk,
    input  wire        rst_n,

    // FPGA physical buttons, active-low.
    input  wire        key0_n,
    input  wire        key1_n,

    // TTP229 decoded touch state.
    input  wire [15:0] touch_keys,
    input  wire        touch_update,

    // Transposed Note Events.
    output wire        event_valid,
    output wire        event_on,
    output wire [6:0]  event_note,
    output wire [31:0] event_fcw,

    // Octave:
    // 0 = -1 octave
    // 1 = normal octave
    // 2 = +1 octave
    output reg  [1:0]  octave_mode,

    // Debug outputs.
    output wire [15:0] sent_keys,
    output wire        busy
);

    // ============================================================
    // Task 8.4-A
    //
    // TTP229 16-Key Octave Note Event Generator
    //
    // Includes:
    //   1. KEY0 / KEY1 synchronization
    //   2. Button debouncing
    //   3. Octave mode control
    //   4. Existing Note Event module
    //   5. MIDI / FCW transposition
    //
    // All logic runs in one clock domain.
    // ============================================================


    // ============================================================
    // 1. Synchronize physical keys
    // ============================================================

    reg [1:0] key0_sync;
    reg [1:0] key1_sync;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            key0_sync <= 2'b11;
            key1_sync <= 2'b11;

        end
        else begin

            key0_sync <= {
                key0_sync[0],
                key0_n
            };

            key1_sync <= {
                key1_sync[0],
                key1_n
            };

        end

    end


    // ============================================================
    // 2. Button debounce
    //
    // DEBOUNCE_CYCLES = 960000:
    // 960000 / 48 MHz = 20 ms
    //
    // A press event occurs only once per stable press.
    // ============================================================

    reg key0_stable;
    reg key1_stable;

    reg [31:0] key0_counter;
    reg [31:0] key1_counter;

    wire key0_press;
    wire key1_press;

    assign key0_press =
        key0_stable &&
        !key0_sync[1] &&
        (key0_counter == DEBOUNCE_CYCLES - 1);

    assign key1_press =
        key1_stable &&
        !key1_sync[1] &&
        (key1_counter == DEBOUNCE_CYCLES - 1);


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            key0_stable  <= 1'b1;
            key1_stable  <= 1'b1;

            key0_counter <= 32'd0;
            key1_counter <= 32'd0;

        end
        else begin

            // KEY0 debounce.
            if (key0_sync[1] == key0_stable) begin

                key0_counter <= 32'd0;

            end
            else if (
                key0_counter == DEBOUNCE_CYCLES - 1
            ) begin

                key0_stable  <= key0_sync[1];
                key0_counter <= 32'd0;

            end
            else begin

                key0_counter <=
                    key0_counter + 1'b1;

            end


            // KEY1 debounce.
            if (key1_sync[1] == key1_stable) begin

                key1_counter <= 32'd0;

            end
            else if (
                key1_counter == DEBOUNCE_CYCLES - 1
            ) begin

                key1_stable  <= key1_sync[1];
                key1_counter <= 32'd0;

            end
            else begin

                key1_counter <=
                    key1_counter + 1'b1;

            end

        end

    end


    // ============================================================
    // 3. Original 16-Key Note Event Generator
    //
    // This module was already verified:
    // 11 cases / 56 events PASS.
    //
    // Its original MIDI range is 60~75.
    // ============================================================

    wire        base_event_valid;
    wire        base_event_on;

    wire [6:0]  base_event_note;
    wire [31:0] base_event_fcw;

    wire        base_busy;

    touch_note_event_16 u_base_events (
        .clk          (clk),
        .rst_n        (rst_n),

        .touch_keys   (touch_keys),
        .touch_update (touch_update),

        .event_valid  (base_event_valid),
        .event_on     (base_event_on),

        .event_note   (base_event_note),
        .event_fcw    (base_event_fcw),

        .sent_keys    (sent_keys),
        .busy         (base_busy)
    );


    assign busy = base_busy;


    // ============================================================
    // 4. Octave switching permission
    //
    // Allow switching only if:
    //
    // - No touch key is currently pressed.
    // - All previous touch states were released.
    // - No pending event exists.
    // - No Note Event is currently valid.
    //
    // An ignored key press will NOT be queued.
    // The user must release and press the key again.
    // ============================================================

    wire octave_change_allowed;

    assign octave_change_allowed =
        (touch_keys == 16'd0) &&
        (sent_keys  == 16'd0) &&
        !base_busy &&
        !base_event_valid;


    // ============================================================
    // 5. Octave controller
    //
    // 0 = down one octave
    // 1 = normal
    // 2 = up one octave
    //
    // KEY0 -> down
    // KEY1 -> up
    //
    // Simultaneous presses do not change octave.
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            octave_mode <= 2'd1;

        end
        else if (octave_change_allowed) begin

            if (
                key0_press &&
                !key1_press &&
                key1_stable
            ) begin

                if (octave_mode > 2'd0) begin

                    octave_mode <=
                        octave_mode - 1'b1;

                end

            end
            else if (
                key1_press &&
                !key0_press &&
                key0_stable
            ) begin

                if (octave_mode < 2'd2) begin

                    octave_mode <=
                        octave_mode + 1'b1;

                end

            end

        end

    end


    // ============================================================
    // 6. MIDI transpose
    //
    // Base range: MIDI 60~75
    //
    // octave_mode = 0 -> MIDI 48~63
    // octave_mode = 1 -> MIDI 60~75
    // octave_mode = 2 -> MIDI 72~87
    // ============================================================

    assign event_valid = base_event_valid;

    assign event_on = base_event_on;

    assign event_note =
        (octave_mode == 2'd0)
        ? (base_event_note - 7'd12)
        :
        (octave_mode == 2'd2)
        ? (base_event_note + 7'd12)
        : base_event_note;


    // ============================================================
    // 7. DDS FCW transpose
    //
    // Octave down: FCW / 2
    // Normal:      FCW
    // Octave up:   FCW * 2
    //
    // Note Off FCW is always zero.
    // ============================================================

    assign event_fcw =
        !base_event_on
        ? 32'd0
        :
        (octave_mode == 2'd0)
        ? (base_event_fcw >> 1)
        :
        (octave_mode == 2'd2)
        ? (base_event_fcw << 1)
        : base_event_fcw;

endmodule