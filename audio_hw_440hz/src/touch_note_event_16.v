module touch_note_event_16 (
    input  wire        clk,
    input  wire        rst_n,

    // TTP229 decoded touch state.
    // Bit 0 = touch key 1
    // Bit15 = touch key16
    // 1 = pressed
    input  wire [15:0] touch_keys,

    // One-clock pulse when a new touch snapshot is ready.
    input  wire        touch_update,

    // Common Note Event output.
    output reg         event_valid,
    output reg         event_on,
    output reg  [6:0]  event_note,
    output reg  [31:0] event_fcw,

    // Debug outputs.
    output reg  [15:0] sent_keys,
    output wire        busy
);

    // ============================================================
    // Task 8.3-A
    //
    // TTP229 16-Key to Note Event
    //
    // MIDI mapping:
    // Touch 1  -> MIDI60 C4
    // Touch 2  -> MIDI61 C#4
    // ...
    // Touch16  -> MIDI75 D#5
    //
    // One event per clock.
    //
    // Note Off has priority over Note On.
    // ============================================================


    // ============================================================
    // 1. Latest touch snapshot
    // ============================================================

    reg [15:0] desired_keys;


    // ============================================================
    // 2. Pending changes
    //
    // sent_keys:
    // Last state already submitted as Note Events.
    //
    // desired_keys:
    // Latest state received from TTP229.
    // ============================================================

    wire [15:0] pending_off;
    wire [15:0] pending_on;

    assign pending_off =
        sent_keys & ~desired_keys;

    assign pending_on =
        desired_keys & ~sent_keys;


    assign busy =
        |pending_off | |pending_on;


    // ============================================================
    // 3. Priority encoder
    //
    // Priority:
    //
    // 1. Note Off
    // 2. Note On
    //
    // Within each type, lower key number first.
    // ============================================================

    reg       selected_valid;
    reg       selected_on;
    reg [3:0] selected_index;

    integer i;


    always @(*) begin

        selected_valid = 1'b0;
        selected_on    = 1'b0;
        selected_index = 4'd0;

        // --------------------------------------------------------
        // First choose a pending Note Off.
        // --------------------------------------------------------

        for (i = 0; i < 16; i = i + 1) begin

            if (
                !selected_valid &&
                pending_off[i]
            ) begin

                selected_valid = 1'b1;
                selected_on    = 1'b0;
                selected_index = i;

            end

        end


        // --------------------------------------------------------
        // If there is no Note Off, choose a Note On.
        // --------------------------------------------------------

        if (!selected_valid) begin

            for (i = 0; i < 16; i = i + 1) begin

                if (
                    !selected_valid &&
                    pending_on[i]
                ) begin

                    selected_valid = 1'b1;
                    selected_on    = 1'b1;
                    selected_index = i;

                end

            end

        end

    end


    // ============================================================
    // 4. MIDI note -> DDS frequency control word
    //
    // Phase accumulator: 32-bit
    // Sample rate:       48000 Hz
    //
    // FCW = round(freq * 2^32 / 48000)
    // ============================================================

    function [31:0] key_fcw;

        input [3:0] key_index;

        begin

            case (key_index)

                // C4
                4'd0:
                    key_fcw = 32'h016534C3;

                // C#4
                4'd1:
                    key_fcw = 32'h017A725A;

                // D4
                4'd2:
                    key_fcw = 32'h0190F347;

                // D#4
                4'd3:
                    key_fcw = 32'h01A8CAC3;

                // E4
                4'd4:
                    key_fcw = 32'h01C20D2F;

                // F4
                4'd5:
                    key_fcw = 32'h01DCD01D;

                // F#4
                4'd6:
                    key_fcw = 32'h01F92A6D;

                // G4
                4'd7:
                    key_fcw = 32'h02173456;

                // G#4
                4'd8:
                    key_fcw = 32'h02370783;

                // A4
                4'd9:
                    key_fcw = 32'h0258BF26;

                // A#4
                4'd10:
                    key_fcw = 32'h027C780B;

                // B4
                4'd11:
                    key_fcw = 32'h02A250BA;

                // C5
                4'd12:
                    key_fcw = 32'h02CA6987;

                // C#5
                4'd13:
                    key_fcw = 32'h02F4E4B4;

                // D5
                4'd14:
                    key_fcw = 32'h0321E68D;

                // D#5
                4'd15:
                    key_fcw = 32'h03519586;

                default:
                    key_fcw = 32'd0;

            endcase

        end

    endfunction


    // ============================================================
    // 5. Event generation
    //
    // A new touch snapshot is accepted on touch_update.
    //
    // Otherwise send at most one pending event.
    //
    // No event is generated when touch state is unchanged.
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            desired_keys <= 16'd0;
            sent_keys    <= 16'd0;

            event_valid  <= 1'b0;
            event_on     <= 1'b0;

            event_note   <= 7'd0;
            event_fcw    <= 32'd0;

        end
        else begin

            // Default: no event.
            event_valid <= 1'b0;

            // ----------------------------------------------------
            // Accept newest touch snapshot.
            //
            // Do not emit an event on the same clock as an update.
            // This prevents submitting an obsolete pending event.
            // ----------------------------------------------------

            if (touch_update) begin

                desired_keys <= touch_keys;

            end

            // ----------------------------------------------------
            // Emit one pending change.
            // ----------------------------------------------------

            else if (selected_valid) begin

                event_valid <= 1'b1;

                event_on <= selected_on;

                event_note <=
                    7'd60 + {3'd0, selected_index};


                if (selected_on) begin

                    event_fcw <=
                        key_fcw(selected_index);

                end
                else begin

                    // Note Off uses event_note to identify
                    // the note. FCW is not needed.
                    event_fcw <= 32'd0;

                end


                // Remember the state we just emitted.
                sent_keys[selected_index] <=
                    selected_on;

            end

        end

    end

endmodule