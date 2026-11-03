module voice_allocator_32 (
    input  wire          clk,
    input  wire          rst_n,

    // ============================================================
    // Note Event input
    // ============================================================

    input  wire          event_valid,
    input  wire          event_on,

    input  wire [6:0]    event_note,
    input  wire [31:0]   event_fcw,


    // ============================================================
    // Voice activity feedback
    //
    // From synth_engine_tdm_32.
    //
    // active_mask[N] = 1:
    // Voice N ADSR is still active.
    // ============================================================

    input  wire [31:0]   active_mask,


    // ============================================================
    // Voice control outputs
    // ============================================================

    output reg  [31:0]   gate_mask,

    // 32 Voices × 32-bit FCW
    output reg  [1023:0] fcw_flat,


    // ============================================================
    // Allocator status
    // ============================================================

    output reg  [31:0]   assigned_mask,

    output reg           alloc_fail_pulse
);


    // ============================================================
    // Note number owned by each Voice
    // ============================================================

    reg [6:0] note_mem [0:31];


    // ============================================================
    // Allocation search logic
    // ============================================================

    reg       duplicate_held;

    reg       free_found;
    reg [4:0] free_index;

    reg       noteoff_found;
    reg [4:0] noteoff_index;


    integer scan_i;


    // ============================================================
    // Search current allocator state
    // ============================================================

    always @(*) begin

        // --------------------------------------------------------
        // Default
        // --------------------------------------------------------

        duplicate_held = 1'b0;

        free_found =
            1'b0;

        free_index =
            5'd0;

        noteoff_found =
            1'b0;

        noteoff_index =
            5'd0;


        // ========================================================
        // Scan all 32 Voices
        // ========================================================

        for (
            scan_i = 0;
            scan_i < 32;
            scan_i = scan_i + 1
        ) begin


            // ----------------------------------------------------
            // Is the same note currently being held?
            //
            // Only gate=1 counts as held.
            //
            // A note in Release has gate=0 and may therefore
            // be retriggered on another free Voice.
            // ----------------------------------------------------

            if (
                assigned_mask[scan_i] &&
                gate_mask[scan_i] &&
                (
                    note_mem[scan_i] ==
                    event_note
                )
            ) begin

                duplicate_held =
                    1'b1;

            end


            // ----------------------------------------------------
            // Find first free Voice
            // ----------------------------------------------------

            if (
                !free_found &&
                !assigned_mask[scan_i]
            ) begin

                free_found =
                    1'b1;

                free_index =
                    scan_i[4:0];

            end


            // ----------------------------------------------------
            // Find currently held Voice for Note Off
            // ----------------------------------------------------

            if (
                !noteoff_found &&
                assigned_mask[scan_i] &&
                gate_mask[scan_i] &&
                (
                    note_mem[scan_i] ==
                    event_note
                )
            ) begin

                noteoff_found =
                    1'b1;

                noteoff_index =
                    scan_i[4:0];

            end

        end

    end


    // ============================================================
    // Allocator state machine
    // ============================================================

    integer reset_i;
    integer free_i;


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            gate_mask <=
                32'd0;

            assigned_mask <=
                32'd0;

            fcw_flat <=
                1024'd0;

            alloc_fail_pulse <=
                1'b0;


            // ----------------------------------------------------
            // Reset Note memories
            // ----------------------------------------------------

            for (
                reset_i = 0;
                reset_i < 32;
                reset_i = reset_i + 1
            ) begin

                note_mem[reset_i] <=
                    7'd0;

            end

        end
        else begin

            // ----------------------------------------------------
            // Allocation failure pulse lasts one clock only.
            // ----------------------------------------------------

            alloc_fail_pulse <=
                1'b0;


            // ====================================================
            // Release completed:
            //
            // gate = 0
            // AND
            // active = 0
            //
            // means Voice can finally become free.
            // ====================================================

            for (
                free_i = 0;
                free_i < 32;
                free_i = free_i + 1
            ) begin

                if (
                    assigned_mask[free_i] &&
                    !gate_mask[free_i] &&
                    !active_mask[free_i]
                ) begin

                    assigned_mask[free_i] <=
                        1'b0;

                    note_mem[free_i] <=
                        7'd0;

                    fcw_flat[
                        free_i * 32 +:
                        32
                    ] <=
                        32'd0;

                end

            end


            // ====================================================
            // Process one Note Event
            // ====================================================

            if (event_valid) begin


                // =================================================
                // NOTE ON
                // =================================================

                if (event_on) begin


                    // ---------------------------------------------
                    // Ignore duplicate Note On while the note is
                    // still physically held.
                    // ---------------------------------------------

                    if (duplicate_held) begin

                        // No action.

                    end


                    // ---------------------------------------------
                    // Allocate first available Voice.
                    // ---------------------------------------------

                    else if (free_found) begin

                        assigned_mask[
                            free_index
                        ] <=
                            1'b1;


                        gate_mask[
                            free_index
                        ] <=
                            1'b1;


                        note_mem[
                            free_index
                        ] <=
                            event_note;


                        fcw_flat[
                            free_index * 32 +:
                            32
                        ] <=
                            event_fcw;

                    end


                    // ---------------------------------------------
                    // All 32 Voices occupied.
                    // ---------------------------------------------

                    else begin

                        alloc_fail_pulse <=
                            1'b1;

                    end

                end


                // =================================================
                // NOTE OFF
                // =================================================

                else begin

                    if (noteoff_found) begin

                        gate_mask[
                            noteoff_index
                        ] <=
                            1'b0;

                    end

                end

            end

        end

    end

endmodule