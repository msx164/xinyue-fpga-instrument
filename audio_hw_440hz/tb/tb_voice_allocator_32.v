`timescale 1ns/1ps

module tb_voice_allocator_32;

    reg clk;
    reg rst_n;


    // ============================================================
    // Note Event
    // ============================================================

    reg        event_valid;
    reg        event_on;

    reg [6:0]  event_note;
    reg [31:0] event_fcw;


    // ============================================================
    // Voice feedback
    // ============================================================

    reg [31:0] active_mask;


    // ============================================================
    // Allocator outputs
    // ============================================================

    wire [31:0] gate_mask;

    wire [1023:0] fcw_flat;

    wire [31:0] assigned_mask;

    wire alloc_fail_pulse;


    // ============================================================
    // Test status
    // ============================================================

    integer error_count;
    integer alloc_fail_count;

    integer test_i;


    // ============================================================
    // DUT
    // ============================================================

    voice_allocator_32 dut (
        .clk              (clk),
        .rst_n            (rst_n),

        .event_valid      (event_valid),
        .event_on         (event_on),

        .event_note       (event_note),
        .event_fcw        (event_fcw),

        .active_mask      (active_mask),

        .gate_mask        (gate_mask),
        .fcw_flat         (fcw_flat),

        .assigned_mask    (assigned_mask),

        .alloc_fail_pulse (alloc_fail_pulse)
    );


    // ============================================================
    // 48 MHz clock
    // ============================================================

    initial begin

        clk = 1'b0;

        forever #10.416667
            clk = ~clk;

    end


    // ============================================================
    // Failure pulse monitor
    // ============================================================

    always @(posedge clk) begin

        if (alloc_fail_pulse) begin

            alloc_fail_count =
                alloc_fail_count + 1;

        end

    end


    // ============================================================
    // Test FCW generator
    //
    // These FCWs do not need to correspond to musical notes.
    // This test only verifies allocation data integrity.
    // ============================================================

    function [31:0] make_test_fcw;

        input integer index;

        begin

            make_test_fcw =
                32'h01000000 +
                (
                    index *
                    32'h00010000
                );

        end

    endfunction


    // ============================================================
    // Send one Note Event
    // ============================================================

    task send_event;

        input        note_on;
        input [6:0]  note;
        input [31:0] fcw;

        begin

            @(negedge clk);

            event_on =
                note_on;

            event_note =
                note;

            event_fcw =
                fcw;

            event_valid =
                1'b1;


            @(negedge clk);

            event_valid =
                1'b0;


            @(posedge clk);

        end

    endtask


    // ============================================================
    // Main Test
    // ============================================================

    initial begin

        // --------------------------------------------------------
        // Initial state
        // --------------------------------------------------------

        rst_n =
            1'b0;

        event_valid =
            1'b0;

        event_on =
            1'b0;

        event_note =
            7'd0;

        event_fcw =
            32'd0;

        active_mask =
            32'd0;

        error_count =
            0;

        alloc_fail_count =
            0;


        #200;


        rst_n =
            1'b1;


        repeat (4)
            @(posedge clk);


        // ========================================================
        // TEST 1
        //
        // Fill all 32 Voices.
        //
        // Note numbers:
        //
        // 20 -> Voice0
        // 21 -> Voice1
        // ...
        // 51 -> Voice31
        // ========================================================

        $display("");
        $display(
            "--------------------------------"
        );

        $display(
            "TEST 1: Allocate 32 Voices"
        );

        $display(
            "--------------------------------"
        );


        for (
            test_i = 0;
            test_i < 32;
            test_i = test_i + 1
        ) begin

            send_event(
                1'b1,
                7'd20 + test_i,
                make_test_fcw(test_i)
            );


            // ----------------------------------------------------
            // Simulate that the allocated Voice has now become
            // active in the synthesizer.
            // ----------------------------------------------------

            active_mask[test_i] =
                1'b1;


            // ----------------------------------------------------
            // Verify allocation
            // ----------------------------------------------------

            if (
                assigned_mask[test_i] !==
                1'b1
            ) begin

                $display(
                    "VOICE %0d ASSIGN FAIL",
                    test_i
                );

                error_count =
                    error_count + 1;

            end


            if (
                gate_mask[test_i] !==
                1'b1
            ) begin

                $display(
                    "VOICE %0d GATE FAIL",
                    test_i
                );

                error_count =
                    error_count + 1;

            end


            if (
                fcw_flat[
                    test_i * 32 +:
                    32
                ] !==
                make_test_fcw(test_i)
            ) begin

                $display(
                    "VOICE %0d FCW FAIL",
                    test_i
                );

                error_count =
                    error_count + 1;

            end

        end


        if (
            assigned_mask ===
            32'hFFFFFFFF
        ) begin

            $display(
                "32 VOICES ASSIGNED PASS"
            );

        end
        else begin

            $display(
                "32 VOICES ASSIGNED FAIL: %h",
                assigned_mask
            );

            error_count =
                error_count + 1;

        end


        if (
            gate_mask ===
            32'hFFFFFFFF
        ) begin

            $display(
                "32 VOICES GATE PASS"
            );

        end
        else begin

            $display(
                "32 VOICES GATE FAIL: %h",
                gate_mask
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // TEST 2
        //
        // Try to allocate Voice33.
        //
        // All 32 Voices are occupied.
        // ========================================================

        $display("");
        $display(
            "--------------------------------"
        );

        $display(
            "TEST 2: Allocation Full"
        );

        $display(
            "--------------------------------"
        );


        send_event(
            1'b1,
            7'd60,
            32'h12345678
        );


        repeat (3)
            @(posedge clk);


        if (
            alloc_fail_count == 1
        ) begin

            $display(
                "32 VOICE FULL TEST PASS"
            );

        end
        else begin

            $display(
                "32 VOICE FULL TEST FAIL: count=%0d",
                alloc_fail_count
            );

            error_count =
                error_count + 1;

        end


        // ========================================================
        // TEST 3
        //
        // Release Note27.
        //
        // Notes start from 20:
        //
        // Note27 -> Voice7
        // ========================================================

        $display("");
        $display(
            "--------------------------------"
        );

        $display(
            "TEST 3: Note Off / Release Hold"
        );

        $display(
            "--------------------------------"
        );


        send_event(
            1'b0,
            7'd27,
            32'd0
        );


        // --------------------------------------------------------
        // Gate must turn OFF.
        // --------------------------------------------------------

        if (
            gate_mask[7] !==
            1'b0
        ) begin

            $display(
                "VOICE7 NOTE OFF FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "VOICE7 NOTE OFF PASS"
            );

        end


        // --------------------------------------------------------
        // Voice must remain assigned because ADSR is still active.
        // --------------------------------------------------------

        if (
            assigned_mask[7] !==
            1'b1
        ) begin

            $display(
                "VOICE7 RELEASE HOLD FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "VOICE7 RELEASE HOLD PASS"
            );

        end


        // ========================================================
        // TEST 4
        //
        // Simulate ADSR Release completion.
        // ========================================================

        $display("");
        $display(
            "--------------------------------"
        );

        $display(
            "TEST 4: Release Complete"
        );

        $display(
            "--------------------------------"
        );


        active_mask[7] =
            1'b0;


        repeat (3)
            @(posedge clk);


        if (
            assigned_mask[7] !==
            1'b0
        ) begin

            $display(
                "VOICE7 FREE FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "VOICE7 FREE PASS"
            );

        end


        // ========================================================
        // TEST 5
        //
        // New note must reuse Voice7 because it is now the first
        // free Voice.
        // ========================================================

        $display("");
        $display(
            "--------------------------------"
        );

        $display(
            "TEST 5: Voice Reuse"
        );

        $display(
            "--------------------------------"
        );


        send_event(
            1'b1,
            7'd60,
            32'h76543210
        );


        if (
            assigned_mask[7] !==
            1'b1
        ) begin

            $display(
                "VOICE7 REUSE ASSIGN FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "VOICE7 REUSE ASSIGN PASS"
            );

        end


        if (
            gate_mask[7] !==
            1'b1
        ) begin

            $display(
                "VOICE7 REUSE GATE FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "VOICE7 REUSE GATE PASS"
            );

        end


        if (
            fcw_flat[
                7 * 32 +:
                32
            ] !==
            32'h76543210
        ) begin

            $display(
                "VOICE7 REUSE FCW FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "VOICE7 REUSE FCW PASS"
            );

        end


        // ========================================================
        // Final result
        // ========================================================

        $display("");
        $display(
            "================================"
        );

        $display(
            "Errors : %0d",
            error_count
        );


        if (
            error_count == 0
        ) begin

            $display(
                "VOICE ALLOCATOR 32 TEST PASS"
            );

        end
        else begin

            $display(
                "VOICE ALLOCATOR 32 TEST FAIL"
            );

        end


        $display(
            "================================"
        );


        $stop;

    end

endmodule