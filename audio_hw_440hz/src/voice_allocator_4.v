module voice_allocator_4 (
    input  wire        clk,
    input  wire        rst_n,

    // ------------------------------------------------------------
    // Note Event input
    // ------------------------------------------------------------
    input  wire        event_valid,
    input  wire        event_on,

    input  wire [6:0]  event_note,
    input  wire [31:0] event_fcw,

    // ------------------------------------------------------------
    // ADSR activity feedback
    // ------------------------------------------------------------
    input  wire        voice0_active,
    input  wire        voice1_active,
    input  wire        voice2_active,
    input  wire        voice3_active,

    // ------------------------------------------------------------
    // Voice control outputs
    // ------------------------------------------------------------
    output reg         gate0,
    output reg         gate1,
    output reg         gate2,
    output reg         gate3,

    output reg  [31:0] fcw0,
    output reg  [31:0] fcw1,
    output reg  [31:0] fcw2,
    output reg  [31:0] fcw3,

    // ------------------------------------------------------------
    // Debug
    // ------------------------------------------------------------
    output wire [3:0]  assigned_mask,

    output reg         alloc_fail_pulse
);

    // ------------------------------------------------------------
    // Voice allocation state
    // ------------------------------------------------------------
    reg assigned0;
    reg assigned1;
    reg assigned2;
    reg assigned3;


    // ------------------------------------------------------------
    // Note currently owned by each Voice
    // ------------------------------------------------------------
    reg [6:0] note0;
    reg [6:0] note1;
    reg [6:0] note2;
    reg [6:0] note3;


    assign assigned_mask = {
        assigned3,
        assigned2,
        assigned1,
        assigned0
    };


    // ============================================================
    // Voice allocator
    // ============================================================
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            assigned0 <= 1'b0;
            assigned1 <= 1'b0;
            assigned2 <= 1'b0;
            assigned3 <= 1'b0;

            gate0 <= 1'b0;
            gate1 <= 1'b0;
            gate2 <= 1'b0;
            gate3 <= 1'b0;

            fcw0 <= 32'd0;
            fcw1 <= 32'd0;
            fcw2 <= 32'd0;
            fcw3 <= 32'd0;

            note0 <= 7'd0;
            note1 <= 7'd0;
            note2 <= 7'd0;
            note3 <= 7'd0;

            alloc_fail_pulse <= 1'b0;

        end
        else begin

            alloc_fail_pulse <= 1'b0;


            // ====================================================
            // Free Voices only after ADSR Release is finished.
            // ====================================================

            if (
                assigned0 &&
                !gate0 &&
                !voice0_active
            ) begin

                assigned0 <= 1'b0;

                note0 <= 7'd0;
                fcw0  <= 32'd0;

            end


            if (
                assigned1 &&
                !gate1 &&
                !voice1_active
            ) begin

                assigned1 <= 1'b0;

                note1 <= 7'd0;
                fcw1  <= 32'd0;

            end


            if (
                assigned2 &&
                !gate2 &&
                !voice2_active
            ) begin

                assigned2 <= 1'b0;

                note2 <= 7'd0;
                fcw2  <= 32'd0;

            end


            if (
                assigned3 &&
                !gate3 &&
                !voice3_active
            ) begin

                assigned3 <= 1'b0;

                note3 <= 7'd0;
                fcw3  <= 32'd0;

            end


            // ====================================================
            // Handle Note Event
            // ====================================================
            if (event_valid) begin


                // =================================================
                // NOTE ON
                // =================================================
                if (event_on) begin


                    // ---------------------------------------------
                    // Ignore duplicated Note On if the same note
                    // is already being held.
                    //
                    // A note currently in Release is allowed to
                    // retrigger using another Voice.
                    // ---------------------------------------------
                    if (
                        (gate0 && note0 == event_note) ||
                        (gate1 && note1 == event_note) ||
                        (gate2 && note2 == event_note) ||
                        (gate3 && note3 == event_note)
                    ) begin

                        // No action.

                    end


                    // ---------------------------------------------
                    // Allocate first free Voice.
                    // ---------------------------------------------
                    else if (!assigned0) begin

                        assigned0 <= 1'b1;

                        gate0 <= 1'b1;

                        note0 <= event_note;
                        fcw0  <= event_fcw;

                    end
                    else if (!assigned1) begin

                        assigned1 <= 1'b1;

                        gate1 <= 1'b1;

                        note1 <= event_note;
                        fcw1  <= event_fcw;

                    end
                    else if (!assigned2) begin

                        assigned2 <= 1'b1;

                        gate2 <= 1'b1;

                        note2 <= event_note;
                        fcw2  <= event_fcw;

                    end
                    else if (!assigned3) begin

                        assigned3 <= 1'b1;

                        gate3 <= 1'b1;

                        note3 <= event_note;
                        fcw3  <= event_fcw;

                    end


                    // ---------------------------------------------
                    // All Voices are occupied.
                    // ---------------------------------------------
                    else begin

                        alloc_fail_pulse <= 1'b1;

                    end

                end


                // =================================================
                // NOTE OFF
                // =================================================
                else begin

                    if (
                        gate0 &&
                        note0 == event_note
                    ) begin

                        gate0 <= 1'b0;

                    end
                    else if (
                        gate1 &&
                        note1 == event_note
                    ) begin

                        gate1 <= 1'b0;

                    end
                    else if (
                        gate2 &&
                        note2 == event_note
                    ) begin

                        gate2 <= 1'b0;

                    end
                    else if (
                        gate3 &&
                        note3 == event_note
                    ) begin

                        gate3 <= 1'b0;

                    end

                end

            end

        end

    end

endmodule