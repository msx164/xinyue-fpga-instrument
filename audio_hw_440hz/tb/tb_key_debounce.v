`timescale 1ns/1ps

module tb_key_debounce;

    // ------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------
    reg clk;
    reg rst_n;


    // ------------------------------------------------------------
    // Raw key input
    //
    // Active low
    // ------------------------------------------------------------
    reg key_in_n;


    // ------------------------------------------------------------
    // DUT outputs
    // ------------------------------------------------------------
    wire key_down;
    wire key_press_pulse;
    wire key_release_pulse;


    // ------------------------------------------------------------
    // Statistics
    // ------------------------------------------------------------
    integer press_pulse_count;
    integer release_pulse_count;
    integer error_count;


    // ============================================================
    // DUT
    //
    // Use only 8 cycles in simulation to make the test fast.
    //
    // Real hardware uses 480000 cycles.
    // ============================================================
    key_debounce #(
        .DEBOUNCE_COUNT(8)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),

        .key_in_n          (key_in_n),

        .key_down          (key_down),
        .key_press_pulse   (key_press_pulse),
        .key_release_pulse (key_release_pulse)
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
    // Pulse monitor
    // ============================================================
    always @(posedge clk) begin

        if (key_press_pulse)
            press_pulse_count =
                press_pulse_count + 1;

        if (key_release_pulse)
            release_pulse_count =
                release_pulse_count + 1;

    end


    // ============================================================
    // Test sequence
    // ============================================================
    initial begin

        rst_n = 1'b0;

        key_in_n = 1'b1;

        press_pulse_count   = 0;
        release_pulse_count = 0;
        error_count         = 0;


        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------
        #200;

        rst_n = 1'b1;


        repeat (5)
            @(posedge clk);


        // ========================================================
        // Simulate key press bouncing
        // ========================================================

        key_in_n = 1'b0;

        repeat (2)
            @(posedge clk);


        key_in_n = 1'b1;

        repeat (2)
            @(posedge clk);


        key_in_n = 1'b0;

        repeat (2)
            @(posedge clk);


        key_in_n = 1'b1;

        repeat (2)
            @(posedge clk);


        // --------------------------------------------------------
        // Final stable press
        // --------------------------------------------------------
        key_in_n = 1'b0;

        repeat (12)
            @(posedge clk);


        // --------------------------------------------------------
        // Check pressed state
        // --------------------------------------------------------
        if (key_down !== 1'b1) begin

            $display(
                "KEY PRESS FAIL: key_down should be 1"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "KEY PRESS STATE PASS"
            );

        end


        // ========================================================
        // Simulate key release bouncing
        // ========================================================

        key_in_n = 1'b1;

        repeat (2)
            @(posedge clk);


        key_in_n = 1'b0;

        repeat (2)
            @(posedge clk);


        key_in_n = 1'b1;

        repeat (2)
            @(posedge clk);


        key_in_n = 1'b0;

        repeat (2)
            @(posedge clk);


        // --------------------------------------------------------
        // Final stable release
        // --------------------------------------------------------
        key_in_n = 1'b1;

        repeat (12)
            @(posedge clk);


        // --------------------------------------------------------
        // Check released state
        // --------------------------------------------------------
        if (key_down !== 1'b0) begin

            $display(
                "KEY RELEASE FAIL: key_down should be 0"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "KEY RELEASE STATE PASS"
            );

        end


        // --------------------------------------------------------
        // Check pulses
        // --------------------------------------------------------
        if (press_pulse_count != 1) begin

            $display(
                "PRESS PULSE FAIL: count = %0d",
                press_pulse_count
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "PRESS PULSE PASS"
            );

        end


        if (release_pulse_count != 1) begin

            $display(
                "RELEASE PULSE FAIL: count = %0d",
                release_pulse_count
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "RELEASE PULSE PASS"
            );

        end


        // --------------------------------------------------------
        // Final result
        // --------------------------------------------------------
        $display("");
        $display(
            "================================"
        );

        $display(
            "Press pulses   : %0d",
            press_pulse_count
        );

        $display(
            "Release pulses : %0d",
            release_pulse_count
        );

        $display(
            "Errors         : %0d",
            error_count
        );


        if (error_count == 0)
            $display(
                "KEY DEBOUNCE TEST PASS"
            );
        else
            $display(
                "KEY DEBOUNCE TEST FAIL"
            );


        $display(
            "================================"
        );

        $stop;

    end

endmodule