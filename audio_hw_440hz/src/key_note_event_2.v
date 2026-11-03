module key_note_event_2 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        key0_press_pulse,
    input  wire        key0_release_pulse,

    input  wire        key1_press_pulse,
    input  wire        key1_release_pulse,

    output reg         event_valid,
    output reg         event_on,
    output reg  [6:0]  event_note,
    output reg  [31:0] event_fcw
);

    // ------------------------------------------------------------
    // Note definitions
    // ------------------------------------------------------------

    // A4 = MIDI Note 69 = 440 Hz
    localparam [6:0] NOTE_A4 =
        7'd69;

    localparam [31:0] FCW_A4 =
        32'h0258BF26;


    // E5 = MIDI Note 76 = 659.255 Hz
    localparam [6:0] NOTE_E5 =
        7'd76;

    localparam [31:0] FCW_E5 =
        32'h03841A5D;


    // ------------------------------------------------------------
    // Pending event flags
    //
    // These prevent simultaneous key events from being lost.
    // ------------------------------------------------------------
    reg pending_key0_on;
    reg pending_key0_off;

    reg pending_key1_on;
    reg pending_key1_off;


    // ============================================================
    // Note Event Generator
    // ============================================================
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            pending_key0_on  <= 1'b0;
            pending_key0_off <= 1'b0;

            pending_key1_on  <= 1'b0;
            pending_key1_off <= 1'b0;

            event_valid <= 1'b0;
            event_on    <= 1'b0;

            event_note  <= 7'd0;
            event_fcw   <= 32'd0;

        end
        else begin

            // ----------------------------------------------------
            // Default:
            // no event in the current cycle.
            // ----------------------------------------------------
            event_valid <= 1'b0;


            // ----------------------------------------------------
            // Capture physical key events.
            // ----------------------------------------------------
            if (key0_press_pulse)
                pending_key0_on <= 1'b1;

            if (key0_release_pulse)
                pending_key0_off <= 1'b1;

            if (key1_press_pulse)
                pending_key1_on <= 1'b1;

            if (key1_release_pulse)
                pending_key1_off <= 1'b1;


            // ====================================================
            // Send one pending event per clock cycle.
            // ====================================================

            // ----------------------------------------------------
            // KEY0 Note On
            // ----------------------------------------------------
            if (pending_key0_on) begin

                pending_key0_on <= 1'b0;

                event_valid <= 1'b1;
                event_on    <= 1'b1;

                event_note <= NOTE_A4;
                event_fcw  <= FCW_A4;

            end


            // ----------------------------------------------------
            // KEY1 Note On
            // ----------------------------------------------------
            else if (pending_key1_on) begin

                pending_key1_on <= 1'b0;

                event_valid <= 1'b1;
                event_on    <= 1'b1;

                event_note <= NOTE_E5;
                event_fcw  <= FCW_E5;

            end


            // ----------------------------------------------------
            // KEY0 Note Off
            // ----------------------------------------------------
            else if (pending_key0_off) begin

                pending_key0_off <= 1'b0;

                event_valid <= 1'b1;
                event_on    <= 1'b0;

                event_note <= NOTE_A4;
                event_fcw  <= 32'd0;

            end


            // ----------------------------------------------------
            // KEY1 Note Off
            // ----------------------------------------------------
            else if (pending_key1_off) begin

                pending_key1_off <= 1'b0;

                event_valid <= 1'b1;
                event_on    <= 1'b0;

                event_note <= NOTE_E5;
                event_fcw  <= 32'd0;

            end

        end

    end

endmodule