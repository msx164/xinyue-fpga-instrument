module note_control (
    input  wire        key0_down,
    input  wire        key1_down,

    output reg  [31:0] fcw,
    output reg         note_on
);

    // ------------------------------------------------------------
    // DDS frequency control words
    //
    // Sample rate:
    // 48 kHz
    //
    // Phase accumulator:
    // 32 bit
    // ------------------------------------------------------------

    // A4 = 440 Hz
    localparam [31:0] FCW_A4 =
        32'h0258BF26;

    // A5 = 880 Hz
    localparam [31:0] FCW_A5 =
        32'h04B17E4B;


    // ============================================================
    // Monophonic note control
    //
    // No key:
    // note_on = 0
    //
    // KEY0:
    // A4 = 440 Hz
    //
    // KEY1:
    // A5 = 880 Hz
    //
    // If both keys are held:
    // KEY1 has higher priority.
    // ============================================================
    always @(*) begin

        // Default state:
        // silence, A4 is used as the default FCW value.
        fcw     = FCW_A4;
        note_on = 1'b0;


        // KEY1 has higher priority.
        if (key1_down) begin

            fcw     = FCW_A5;
            note_on = 1'b1;

        end
        else if (key0_down) begin

            fcw     = FCW_A4;
            note_on = 1'b1;

        end

    end

endmodule