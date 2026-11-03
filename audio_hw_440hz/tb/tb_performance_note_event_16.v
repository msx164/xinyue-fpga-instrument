`timescale 1ns/1ps

module tb_performance_note_event_16;

    reg clk = 1'b0;
    always #10 clk = ~clk;

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

    performance_note_event_16 #(
        .DEBOUNCE_CYCLES(3),
        .SCALE_HOLD_CYCLES(12)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .key0_n(key0_n),
        .key1_n(key1_n),
        .touch_keys(touch_keys),
        .touch_update(touch_update),
        .event_valid(event_valid),
        .event_on(event_on),
        .event_note(event_note),
        .event_fcw(event_fcw),
        .octave_mode(octave_mode),
        .scale_mode(scale_mode),
        .sent_keys(sent_keys),
        .busy(busy)
    );

    reg exp_on [0:127];
    reg [6:0] exp_note [0:127];
    reg [31:0] exp_fcw [0:127];

    integer expected_count;
    integer received_count;

    task expect_event;
        input note_on;
        input [6:0] midi;
        input [31:0] fcw;
        begin
            exp_on[expected_count] = note_on;
            exp_note[expected_count] = midi;
            exp_fcw[expected_count] = fcw;
            expected_count = expected_count + 1;
        end
    endtask

    // Scoreboard: checks every outgoing Note Event.
    always @(posedge clk) begin
        #1;
        if (rst_n && event_valid) begin

            if (received_count >= expected_count) begin
                $display("FAIL: Unexpected event");
                $fatal(1);
            end

            if (event_on !== exp_on[received_count] ||
                event_note !== exp_note[received_count] ||
                event_fcw !== exp_fcw[received_count]) begin

                $display("FAIL: Event %0d", received_count);
                $display("Expected ON=%b MIDI=%0d FCW=%h",
                    exp_on[received_count],
                    exp_note[received_count],
                    exp_fcw[received_count]);

                $display("Actual   ON=%b MIDI=%0d FCW=%h",
                    event_on, event_note, event_fcw);

                $fatal(1);
            end

            $display("EVENT %0d: %s MIDI=%0d FCW=%h",
                received_count,
                event_on ? "ON " : "OFF",
                event_note,
                event_fcw);

            received_count = received_count + 1;
        end
    end

    task apply_touch;
        input [15:0] value;
        begin
            @(negedge clk);
            touch_keys = value;
            touch_update = 1'b1;

            @(negedge clk);
            touch_update = 1'b0;
        end
    endtask

    task check_drain;
        input [15:0] expected_keys;
        begin
            repeat (24) @(negedge clk);

            if (received_count != expected_count ||
                sent_keys !== expected_keys ||
                busy !== 1'b0) begin

                $display(
                    "FAIL: Drain. Expected count=%0d, Got=%0d",
                    expected_count, received_count
                );
                $display(
                    "Expected keys=%h, Got=%h, Busy=%b",
                    expected_keys, sent_keys, busy
                );
                $fatal(1);
            end
        end
    endtask

    task check_modes;
        input [1:0] expected_octave;
        input expected_scale;
        begin
            if (octave_mode !== expected_octave ||
                scale_mode !== expected_scale) begin

                $display("FAIL: Mode mismatch");
                $display("Expected octave=%0d scale=%b",
                    expected_octave, expected_scale);
                $display("Actual   octave=%0d scale=%b",
                    octave_mode, scale_mode);
                $fatal(1);
            end
        end
    endtask

    task tap_down;
        begin
            @(negedge clk);
            key0_n = 1'b0;
            repeat (10) @(negedge clk);
            key0_n = 1'b1;
            repeat (10) @(negedge clk);
        end
    endtask

    task tap_up;
        begin
            @(negedge clk);
            key1_n = 1'b0;
            repeat (10) @(negedge clk);
            key1_n = 1'b1;
            repeat (10) @(negedge clk);
        end
    endtask

    task both_short;
        begin
            @(negedge clk);
            key0_n = 1'b0;
            key1_n = 1'b0;

            repeat (10) @(negedge clk);

            key0_n = 1'b1;
            key1_n = 1'b1;

            repeat (10) @(negedge clk);
        end
    endtask

    task both_long;
        begin
            @(negedge clk);
            key0_n = 1'b0;
            key1_n = 1'b0;

            repeat (24) @(negedge clk);

            key0_n = 1'b1;
            key1_n = 1'b1;

            repeat (10) @(negedge clk);
        end
    endtask

    initial begin

        rst_n = 1'b0;
        key0_n = 1'b1;
        key1_n = 1'b1;
        touch_keys = 16'd0;
        touch_update = 1'b0;

        expected_count = 0;
        received_count = 0;

        repeat (5) @(negedge clk);
        rst_n = 1'b1;
        repeat (5) @(negedge clk);


        // ========================================================
        // CASE 1: Default mode
        // ========================================================

        $display("\nCASE 1: Default Chromatic Normal");

        check_modes(2'd1, 1'b0);
        $display("CASE 1 PASS");


        // ========================================================
        // CASE 2: Chromatic first/last key
        // ========================================================

        $display("\nCASE 2: Chromatic Chord");

        expect_event(1'b1, 7'd60, 32'h016534C3);
        expect_event(1'b1, 7'd75, 32'h03519586);

        apply_touch(16'h8001);
        check_drain(16'h8001);

        expect_event(1'b0, 7'd60, 32'd0);
        expect_event(1'b0, 7'd75, 32'd0);

        apply_touch(16'h0000);
        check_drain(16'h0000);

        $display("CASE 2 PASS");


        // ========================================================
        // CASE 3: Octave Up / Upper boundary
        // ========================================================

        $display("\nCASE 3: Octave Up");

        tap_up();
        check_modes(2'd2, 1'b0);

        tap_up();
        check_modes(2'd2, 1'b0);

        expect_event(1'b1, 7'd72, 32'h02CA6986);

        apply_touch(16'h0001);
        check_drain(16'h0001);

        expect_event(1'b0, 7'd72, 32'd0);

        apply_touch(16'h0000);
        check_drain(16'h0000);

        $display("CASE 3 PASS");


        // ========================================================
        // CASE 4: Octave Down / Lower boundary
        // ========================================================

        $display("\nCASE 4: Octave Down");

        tap_down();
        check_modes(2'd1, 1'b0);

        tap_down();
        check_modes(2'd0, 1'b0);

        tap_down();
        check_modes(2'd0, 1'b0);

        // Touch10 -> A3, MIDI57
        expect_event(1'b1, 7'd57, 32'h012C5F93);

        apply_touch(16'h0200);
        check_drain(16'h0200);

        expect_event(1'b0, 7'd57, 32'd0);

        apply_touch(16'h0000);
        check_drain(16'h0000);

        $display("CASE 4 PASS");


        // ========================================================
        // CASE 5: Switch to C Major
        // ========================================================

        $display("\nCASE 5: C Major Mode");

        tap_up();
        check_modes(2'd1, 1'b0);

        both_long();
        check_modes(2'd1, 1'b1);

        // Major keys 1, 2, 16:
        // C4, D4, D6
        expect_event(1'b1, 7'd60, 32'h016534C3);
        expect_event(1'b1, 7'd62, 32'h0190F347);
        expect_event(1'b1, 7'd86, 32'h0643CD1B);

        apply_touch(16'h8003);
        check_drain(16'h8003);

        // Ignore KEY1 while chord is held.
        tap_up();
        check_modes(2'd1, 1'b1);

        expect_event(1'b0, 7'd60, 32'd0);
        expect_event(1'b0, 7'd62, 32'd0);
        expect_event(1'b0, 7'd86, 32'd0);

        apply_touch(16'h0000);
        check_drain(16'h0000);

        $display("CASE 5 PASS");


        // ========================================================
        // CASE 6: C Major, octave up
        // ========================================================

        $display("\nCASE 6: C Major Upper Octave");

        tap_up();
        check_modes(2'd2, 1'b1);

        // Major key16 -> D7, MIDI98
        expect_event(1'b1, 7'd98, 32'h0C879A36);

        apply_touch(16'h8000);
        check_drain(16'h8000);

        expect_event(1'b0, 7'd98, 32'd0);

        apply_touch(16'h0000);
        check_drain(16'h0000);

        $display("CASE 6 PASS");


        // ========================================================
        // CASE 7: Short chord ignored, long chord toggles back
        // ========================================================

        $display("\nCASE 7: Scale Gesture");

        both_short();
        check_modes(2'd2, 1'b1);

        both_long();
        check_modes(2'd2, 1'b0);

        // Chromatic key16 -> D#6, MIDI87
        expect_event(1'b1, 7'd87, 32'h06A32B0C);

        apply_touch(16'h8000);
        check_drain(16'h8000);

        expect_event(1'b0, 7'd87, 32'd0);

        apply_touch(16'h0000);
        check_drain(16'h0000);

        $display("CASE 7 PASS");


        // ========================================================
        // CASE 8: Debounce and playing lock
        // ========================================================

        $display("\nCASE 8: Debounce and Playing Lock");

        // One-clock glitch must be ignored.
        @(negedge clk);
        key0_n = 1'b0;

        @(negedge clk);
        key0_n = 1'b1;

        repeat (12) @(negedge clk);
        check_modes(2'd2, 1'b0);

        expect_event(1'b1, 7'd72, 32'h02CA6986);

        apply_touch(16'h0001);
        check_drain(16'h0001);

        // Octave down while playing is ignored.
        tap_down();
        check_modes(2'd2, 1'b0);

        expect_event(1'b0, 7'd72, 32'd0);

        apply_touch(16'h0000);
        check_drain(16'h0000);

        // Long single KEY0 press:
        // one octave change on release, not repeatedly.
        @(negedge clk);
        key0_n = 1'b0;

        repeat (25) @(negedge clk);
        check_modes(2'd2, 1'b0);

        key0_n = 1'b1;
        repeat (10) @(negedge clk);

        check_modes(2'd1, 1'b0);

        $display("CASE 8 PASS");


        // ========================================================
        // Final result
        // ========================================================

        check_drain(16'h0000);

        if (received_count !== 20) begin
            $display("FAIL: Expected 20 total events");
            $fatal(1);
        end

        $display("");
        $display("==========================================");
        $display("PERFORMANCE NOTE EVENT 16 TEST PASS");
        $display("Total validated events: %0d", received_count);
        $display("==========================================");

        $finish;

    end

endmodule