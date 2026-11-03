
`timescale 1ns/1ps

module tb_note_event_stability;

    reg clk;
    reg rst_n;

    reg key0_n;
    reg key1_n;

    reg [15:0] touch_keys;
    reg touch_update;

    wire event_valid;
    wire event_on;

    wire [6:0] event_note;
    wire [31:0] event_fcw;

    wire [1:0] octave_mode;
    wire scale_mode;

    wire [15:0] sent_keys;
    wire busy;

    integer on_count;
    integer off_count;
    integer errors;

    // ------------------------------------------------------------
    // 48 MHz is approximated here using a 20 ns clock period.
    // The event logic is tested by cycle count, not wall time.
    // ------------------------------------------------------------

    initial clk = 1'b0;

    always #10 clk = ~clk;


    // ------------------------------------------------------------
    // DUT: Original Performance Note Event
    // ------------------------------------------------------------

    performance_note_event_16 #(
        .DEBOUNCE_CYCLES  (4),
        .SCALE_HOLD_CYCLES (20)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),

        .key0_n       (key0_n),
        .key1_n       (key1_n),

        .touch_keys   (touch_keys),
        .touch_update (touch_update),

        .event_valid  (event_valid),
        .event_on     (event_on),

        .event_note   (event_note),
        .event_fcw    (event_fcw),

        .octave_mode  (octave_mode),
        .scale_mode   (scale_mode),

        .sent_keys    (sent_keys),
        .busy         (busy)
    );


    // ------------------------------------------------------------
    // Count all event_valid clock cycles.
    //
    // Expected:
    //   One event = one valid clock cycle.
    //
    // A stuck event_valid is therefore detected too.
    // ------------------------------------------------------------

    always @(posedge clk) begin

        if (!rst_n) begin

            on_count  = 0;
            off_count = 0;

        end
        else if (event_valid) begin

            if (event_on)
                on_count = on_count + 1;
            else
                off_count = off_count + 1;

            $display(
                "[EVENT] time=%0t on=%b note=%0d sent=%h",
                $time,
                event_on,
                event_note,
                sent_keys
            );

        end

    end


    // ------------------------------------------------------------
    // Generate one TTP229 scan-valid pulse
    // ------------------------------------------------------------

    task scan_once;
    begin

        @(negedge clk);
        touch_update = 1'b1;

        @(negedge clk);
        touch_update = 1'b0;

        repeat (120)
            @(negedge clk);

    end
    endtask


    // ------------------------------------------------------------
    // Repeat unchanged touch data
    // ------------------------------------------------------------

    task scan_repeat;
        input integer count;
        integer i;
    begin

        for (i = 0; i < count; i = i + 1)
            scan_once;

    end
    endtask


    // ------------------------------------------------------------
    // Test
    // ------------------------------------------------------------

    initial begin

        rst_n        = 1'b0;

        key0_n       = 1'b1;
        key1_n       = 1'b1;

        touch_keys   = 16'h0000;
        touch_update = 1'b0;

        errors = 0;

        repeat (10)
            @(negedge clk);

        rst_n = 1'b1;

        // ========================================================
        // CASE 1: Initial idle state
        // ========================================================

        scan_repeat(5);

        if (
            on_count == 0 &&
            off_count == 0 &&
            sent_keys == 16'h0000
        )
            $display("CASE1 IDLE PASS");
        else begin
            $display("CASE1 IDLE FAIL");
            errors = errors + 1;
        end


        // ========================================================
        // CASE 2: Four keys pressed
        //
        // Expect 4 Note On events.
        // ========================================================

        @(negedge clk);
        touch_keys = 16'h8421;

        scan_repeat(10);

        if (
            on_count == 4 &&
            off_count == 0 &&
            sent_keys == 16'h8421 &&
            !busy &&
            !event_valid
        )
            $display("CASE2 FOUR NOTE ON PASS");
        else begin
            $display(
                "CASE2 FAIL on=%0d off=%0d sent=%h busy=%b",
                on_count,
                off_count,
                sent_keys,
                busy
            );
            errors = errors + 1;
        end


        // ========================================================
        // CASE 3: Keep same four keys held
        //
        // Simulate 50 repeated scans.
        //
        // Expect:
        //   No additional Note On
        //   No Note Off
        // ========================================================

        scan_repeat(50);

        if (
            on_count == 4 &&
            off_count == 0 &&
            sent_keys == 16'h8421
        )
            $display("CASE3 HOLD STABILITY PASS");
        else begin
            $display(
                "CASE3 HOLD STABILITY FAIL on=%0d off=%0d sent=%h",
                on_count,
                off_count,
                sent_keys
            );
            errors = errors + 1;
        end


        // ========================================================
        // CASE 4: Release all four keys
        //
        // Expect exactly 4 Note Off events.
        // ========================================================

        @(negedge clk);
        touch_keys = 16'h0000;

        scan_repeat(10);

        if (
            on_count == 4 &&
            off_count == 4 &&
            sent_keys == 16'h0000 &&
            !busy &&
            !event_valid
        )
            $display("CASE4 FOUR NOTE OFF PASS");
        else begin
            $display(
                "CASE4 FOUR NOTE OFF FAIL on=%0d off=%0d sent=%h",
                on_count,
                off_count,
                sent_keys
            );
            errors = errors + 1;
        end


        // ========================================================
        // CASE 5: Remain released
        //
        // Expect no more events.
        // ========================================================

        scan_repeat(20);

        if (
            on_count == 4 &&
            off_count == 4 &&
            sent_keys == 16'h0000
        )
            $display("CASE5 RELEASE STABILITY PASS");
        else begin
            $display("CASE5 RELEASE STABILITY FAIL");
            errors = errors + 1;
        end


        // ========================================================
        // Final result
        // ========================================================

        if (errors == 0)
            $display(
                "TASK 9.2-F NOTE EVENT STABILITY PASS"
            );
        else
            $display(
                "TASK 9.2-F FAIL ERRORS=%0d",
                errors
            );

        $finish;

    end

endmodule
