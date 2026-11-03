`timescale 1ns/1ps

module tb_octave_note_event_16;

    reg clk = 1'b0;

    always #10 clk = ~clk;

    reg rst_n;

    reg key0_n;
    reg key1_n;

    reg [15:0] touch_keys;
    reg        touch_update;

    wire       event_valid;
    wire       event_on;
    wire [6:0] event_note;
    wire [31:0] event_fcw;

    wire [1:0]  octave_mode;
    wire [15:0] sent_keys;
    wire        busy;


    // ============================================================
    // DUT
    //
    // Short debounce duration for simulation.
    // Hardware uses 960000 cycles.
    // ============================================================

    octave_note_event_16 #(
        .DEBOUNCE_CYCLES(4)
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
        .sent_keys    (sent_keys),
        .busy         (busy)
    );


    // ============================================================
    // Expected-event scoreboard
    // ============================================================

    reg        exp_on   [0:127];
    reg [6:0]  exp_note [0:127];
    reg [31:0] exp_fcw  [0:127];

    integer expected_count;
    integer received_count;


    task push_expected;

        input        note_on;
        input [6:0]  midi;
        input [31:0] fcw;

        begin

            exp_on[expected_count]   = note_on;
            exp_note[expected_count] = midi;
            exp_fcw[expected_count]  = fcw;

            expected_count = expected_count + 1;

        end

    endtask


    always @(posedge clk) begin

        #1;

        if (rst_n && event_valid) begin

            if (received_count >= expected_count) begin

                $display(
                    "FAIL: Unexpected event: ON=%b MIDI=%0d",
                    event_on, event_note
                );

                $fatal(1);

            end

            if (
                event_on !== exp_on[received_count] ||
                event_note !== exp_note[received_count] ||
                event_fcw !== exp_fcw[received_count]
            ) begin

                $display(
                    "FAIL EVENT %0d",
                    received_count
                );

                $display(
                    "Expected: ON=%b MIDI=%0d FCW=%h",
                    exp_on[received_count],
                    exp_note[received_count],
                    exp_fcw[received_count]
                );

                $display(
                    "Actual:   ON=%b MIDI=%0d FCW=%h",
                    event_on,
                    event_note,
                    event_fcw
                );

                $fatal(1);

            end

            $display(
                "EVENT %0d: %s MIDI=%0d FCW=%h",
                received_count,
                event_on ? "ON " : "OFF",
                event_note,
                event_fcw
            );

            received_count = received_count + 1;

        end

    end


    // ============================================================
    // Touch snapshot
    // ============================================================

    task apply_touch;

        input [15:0] value;

        begin

            @(negedge clk);

            touch_keys   = value;
            touch_update = 1'b1;

            @(negedge clk);

            touch_update = 1'b0;

        end

    endtask


    // ============================================================
    // FPGA button presses
    // ============================================================

    task tap_down;

        begin

            @(negedge clk);
            key0_n = 1'b0;

            repeat (10)
                @(negedge clk);

            key0_n = 1'b1;

            repeat (10)
                @(negedge clk);

        end

    endtask


    task tap_up;

        begin

            @(negedge clk);
            key1_n = 1'b0;

            repeat (10)
                @(negedge clk);

            key1_n = 1'b1;

            repeat (10)
                @(negedge clk);

        end

    endtask


    task tap_both;

        begin

            @(negedge clk);

            key0_n = 1'b0;
            key1_n = 1'b0;

            repeat (10)
                @(negedge clk);

            key0_n = 1'b1;
            key1_n = 1'b1;

            repeat (10)
                @(negedge clk);

        end

    endtask


    // ============================================================
    // Assertions
    // ============================================================

    task check_octave;

        input [1:0] expected_mode;

        begin

            if (octave_mode !== expected_mode) begin

                $display(
                    "FAIL: octave expected=%0d actual=%0d",
                    expected_mode, octave_mode
                );

                $fatal(1);

            end

        end

    endtask


    task check_events;

        input [15:0] expected_keys;

        begin

            repeat (25)
                @(negedge clk);

            if (received_count != expected_count) begin

                $display(
                    "FAIL: event count expected=%0d actual=%0d",
                    expected_count,
                    received_count
                );

                $fatal(1);

            end

            if (sent_keys !== expected_keys) begin

                $display(
                    "FAIL: sent_keys expected=%h actual=%h",
                    expected_keys, sent_keys
                );

                $fatal(1);

            end

            if (busy !== 1'b0) begin

                $display(
                    "FAIL: pending events remain"
                );

                $fatal(1);

            end

        end

    endtask


    // ============================================================
    // Simulation
    // ============================================================

    initial begin

        rst_n = 1'b0;

        key0_n = 1'b1;
        key1_n = 1'b1;

        touch_keys   = 16'd0;
        touch_update = 1'b0;

        expected_count = 0;
        received_count = 0;


        repeat (5)
            @(negedge clk);

        rst_n = 1'b1;

        repeat (5)
            @(negedge clk);


        // ========================================================
        // CASE 1: Default octave
        // ========================================================

        $display("\nCASE 1: Default Octave");

        check_octave(2'd1);

        $display("CASE 1 PASS");


        // ========================================================
        // CASE 2: Octave Up / Upper Limit
        // ========================================================

        $display("\nCASE 2: Octave Up");

        tap_up();
        check_octave(2'd2);

        // Cannot go above +1 octave.
        tap_up();
        check_octave(2'd2);

        $display("CASE 2 PASS");


        // ========================================================
        // CASE 3: Upper octave, two simultaneous keys
        //
        // Key1:  C5  MIDI72
        // Key16: D#6 MIDI87
        // ========================================================

        $display("\nCASE 3: Upper Octave Chord");

        push_expected(
            1'b1, 7'd72, 32'h02CA6986
        );

        push_expected(
            1'b1, 7'd87, 32'h06A32B0C
        );

        apply_touch(16'h8001);
        check_events(16'h8001);

        // Octave change while pressed must be ignored.
        tap_down();
        check_octave(2'd2);

        push_expected(
            1'b0, 7'd72, 32'd0
        );

        push_expected(
            1'b0, 7'd87, 32'd0
        );

        apply_touch(16'h0000);
        check_events(16'h0000);

        $display("CASE 3 PASS");


        // ========================================================
        // CASE 4: Down to normal, then lower octave
        // ========================================================

        $display("\nCASE 4: Octave Down");

        tap_down();
        check_octave(2'd1);

        tap_down();
        check_octave(2'd0);

        // Lower limit.
        tap_down();
        check_octave(2'd0);

        $display("CASE 4 PASS");


        // ========================================================
        // CASE 5: Lower octave A3
        //
        // Touch10:
        // Original A4 MIDI69
        // Transposed A3 MIDI57
        // ========================================================

        $display("\nCASE 5: Lower Octave A3");

        push_expected(
            1'b1, 7'd57, 32'h012C5F93
        );

        apply_touch(16'h0200);
        check_events(16'h0200);

        // Ignore octave switching while key is held.
        tap_up();
        check_octave(2'd0);

        push_expected(
            1'b0, 7'd57, 32'd0
        );

        apply_touch(16'h0000);
        check_events(16'h0000);

        $display("CASE 5 PASS");


        // ========================================================
        // CASE 6: Return to normal octave
        // ========================================================

        $display("\nCASE 6: Return To Normal");

        tap_up();
        check_octave(2'd1);

        $display("CASE 6 PASS");


        // ========================================================
        // CASE 7: Normal octave, four-key chord
        //
        // Keys 1, 5, 8, 13
        //
        // MIDI 60, 64, 67, 72
        // ========================================================

        $display("\nCASE 7: Normal Octave Chord");

        push_expected(
            1'b1, 7'd60, 32'h016534C3
        );

        push_expected(
            1'b1, 7'd64, 32'h01C20D2F
        );

        push_expected(
            1'b1, 7'd67, 32'h02173456
        );

        push_expected(
            1'b1, 7'd72, 32'h02CA6987
        );

        apply_touch(16'h1091);
        check_events(16'h1091);

        // Same snapshot must not repeat Note On.
        apply_touch(16'h1091);
        check_events(16'h1091);

        push_expected(
            1'b0, 7'd60, 32'd0
        );

        push_expected(
            1'b0, 7'd64, 32'd0
        );

        push_expected(
            1'b0, 7'd67, 32'd0
        );

        push_expected(
            1'b0, 7'd72, 32'd0
        );

        apply_touch(16'h0000);
        check_events(16'h0000);

        $display("CASE 7 PASS");


        // ========================================================
        // CASE 8: Simultaneous physical buttons
        // ========================================================

        $display("\nCASE 8: Both Buttons");

        tap_both();
        check_octave(2'd1);

        $display("CASE 8 PASS");


        // ========================================================
        // CASE 9: Short button glitch
        //
        // 2-cycle pulse is shorter than debounce threshold.
        // ========================================================

        $display("\nCASE 9: Debounce Glitch");

        @(negedge clk);
        key1_n = 1'b0;

        repeat (2)
            @(negedge clk);

        key1_n = 1'b1;

        repeat (10)
            @(negedge clk);

        check_octave(2'd1);

        $display("CASE 9 PASS");


        // ========================================================
        // Final checks
        // ========================================================

        check_events(16'h0000);
        check_octave(2'd1);

        $display("");
        $display("==========================================");
        $display("OCTAVE NOTE EVENT 16 TEST PASS");
        $display("Total validated events: %0d", received_count);
        $display("==========================================");

        $finish;

    end

endmodule