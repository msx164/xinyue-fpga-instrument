`timescale 1ns/1ps

module tb_note_control_gate;

    // ------------------------------------------------------------
    // Key states
    // ------------------------------------------------------------
    reg key0_down;
    reg key1_down;


    // ------------------------------------------------------------
    // DUT outputs
    // ------------------------------------------------------------
    wire [31:0] fcw;
    wire        note_on;


    // ------------------------------------------------------------
    // Expected FCW values
    // ------------------------------------------------------------
    localparam [31:0] FCW_A4 =
        32'h0258BF26;

    localparam [31:0] FCW_A5 =
        32'h04B17E4B;


    // ------------------------------------------------------------
    // Statistics
    // ------------------------------------------------------------
    integer error_count;


    // ============================================================
    // DUT
    // ============================================================
    note_control dut (
        .key0_down (key0_down),
        .key1_down (key1_down),

        .fcw       (fcw),
        .note_on   (note_on)
    );


    // ============================================================
    // Test sequence
    // ============================================================
    initial begin

        key0_down = 1'b0;
        key1_down = 1'b0;

        error_count = 0;


        // ========================================================
        // Test 1:
        // No key -> silence
        // ========================================================
        #100;

        if (note_on !== 1'b0) begin

            $display(
                "NO KEY FAIL: note_on should be 0"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "NO KEY SILENCE PASS"
            );

        end


        // ========================================================
        // Test 2:
        // KEY0 -> A4 / 440 Hz
        // ========================================================
        key0_down = 1'b1;

        #100;

        if (
            note_on !== 1'b1 ||
            fcw     !== FCW_A4
        ) begin

            $display(
                "KEY0 A4 FAIL: note_on=%b fcw=0x%08h",
                note_on,
                fcw
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "KEY0 A4 PASS"
            );

        end


        // ========================================================
        // Test 3:
        // Release KEY0 -> silence
        // ========================================================
        key0_down = 1'b0;

        #100;

        if (note_on !== 1'b0) begin

            $display(
                "KEY0 RELEASE FAIL"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "KEY0 RELEASE SILENCE PASS"
            );

        end


        // ========================================================
        // Test 4:
        // KEY1 -> A5 / 880 Hz
        // ========================================================
        key1_down = 1'b1;

        #100;

        if (
            note_on !== 1'b1 ||
            fcw     !== FCW_A5
        ) begin

            $display(
                "KEY1 A5 FAIL: note_on=%b fcw=0x%08h",
                note_on,
                fcw
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "KEY1 A5 PASS"
            );

        end


        // ========================================================
        // Test 5:
        // Release KEY1 -> silence
        // ========================================================
        key1_down = 1'b0;

        #100;

        if (note_on !== 1'b0) begin

            $display(
                "KEY1 RELEASE FAIL"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "KEY1 RELEASE SILENCE PASS"
            );

        end


        // ========================================================
        // Test 6:
        // Both keys -> KEY1 has priority
        // ========================================================
        key0_down = 1'b1;
        key1_down = 1'b1;

        #100;

        if (
            note_on !== 1'b1 ||
            fcw     !== FCW_A5
        ) begin

            $display(
                "BOTH KEY PRIORITY FAIL"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "BOTH KEY PRIORITY PASS"
            );

        end


        // ========================================================
        // Test 7:
        // Release KEY1 while KEY0 remains pressed
        //
        // Should return to A4.
        // ========================================================
        key1_down = 1'b0;

        #100;

        if (
            note_on !== 1'b1 ||
            fcw     !== FCW_A4
        ) begin

            $display(
                "RETURN TO KEY0 FAIL"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "RETURN TO KEY0 PASS"
            );

        end


        // ========================================================
        // Test 8:
        // Release all keys
        // ========================================================
        key0_down = 1'b0;

        #100;

        if (note_on !== 1'b0) begin

            $display(
                "FINAL SILENCE FAIL"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "FINAL SILENCE PASS"
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


        if (error_count == 0) begin

            $display(
                "NOTE GATE TEST PASS"
            );

        end
        else begin

            $display(
                "NOTE GATE TEST FAIL"
            );

        end


        $display(
            "================================"
        );

        $stop;

    end

endmodule