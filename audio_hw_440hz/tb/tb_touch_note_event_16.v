`timescale 1ns/1ps

module tb_touch_note_event_16;

    // ============================================================
    // Clock
    // ============================================================

    reg clk;

    initial clk = 1'b0;

    always #10 clk = ~clk;


    // ============================================================
    // Inputs
    // ============================================================

    reg        rst_n;
    reg [15:0] touch_keys;
    reg        touch_update;


    // ============================================================
    // Outputs
    // ============================================================

    wire        event_valid;
    wire        event_on;

    wire [6:0]  event_note;
    wire [31:0] event_fcw;

    wire [15:0] sent_keys;
    wire        busy;


    // ============================================================
    // DUT
    // ============================================================

    touch_note_event_16 dut (
        .clk          (clk),
        .rst_n        (rst_n),

        .touch_keys   (touch_keys),
        .touch_update (touch_update),

        .event_valid  (event_valid),
        .event_on     (event_on),
        .event_note   (event_note),
        .event_fcw    (event_fcw),

        .sent_keys    (sent_keys),
        .busy         (busy)
    );


    // ============================================================
    // Expected event queue
    // ============================================================

    reg       expected_on   [0:127];
    reg [6:0] expected_note [0:127];

    integer expected_count;
    integer received_count;
    integer k;


    // ============================================================
    // Independent expected FCW lookup
    // ============================================================

    function [31:0] expected_fcw;

        input [6:0] midi_note;

        begin

            case (midi_note)

                7'd60: expected_fcw = 32'h016534C3;
                7'd61: expected_fcw = 32'h017A725A;
                7'd62: expected_fcw = 32'h0190F347;
                7'd63: expected_fcw = 32'h01A8CAC3;

                7'd64: expected_fcw = 32'h01C20D2F;
                7'd65: expected_fcw = 32'h01DCD01D;
                7'd66: expected_fcw = 32'h01F92A6D;
                7'd67: expected_fcw = 32'h02173456;

                7'd68: expected_fcw = 32'h02370783;
                7'd69: expected_fcw = 32'h0258BF26;
                7'd70: expected_fcw = 32'h027C780B;
                7'd71: expected_fcw = 32'h02A250BA;

                7'd72: expected_fcw = 32'h02CA6987;
                7'd73: expected_fcw = 32'h02F4E4B4;
                7'd74: expected_fcw = 32'h0321E68D;
                7'd75: expected_fcw = 32'h03519586;

                default:
                    expected_fcw = 32'd0;

            endcase

        end

    endfunction


    // ============================================================
    // Queue an expected event
    // ============================================================

    task expect_event;

        input       note_on;
        input [6:0] midi_note;

        begin

            expected_on[expected_count] =
                note_on;

            expected_note[expected_count] =
                midi_note;

            expected_count =
                expected_count + 1;

        end

    endtask


    // ============================================================
    // Apply one TTP229 scan snapshot
    // ============================================================

    task apply_touch;

        input [15:0] next_keys;

        begin

            @(negedge clk);

            touch_keys   = next_keys;
            touch_update = 1'b1;

            @(negedge clk);

            touch_update = 1'b0;

        end

    endtask


    // ============================================================
    // Check all scheduled events have appeared.
    //
    // Maximum 16 events per snapshot.
    // 25 cycles is sufficient, with additional margin.
    // ============================================================

    task check_case;

        input [15:0] wanted_state;

        begin

            repeat (25)
                @(negedge clk);

            if (received_count != expected_count) begin

                $display(
                    "ERROR: event count mismatch. Expected=%0d Received=%0d",
                    expected_count,
                    received_count
                );

                $fatal(1);

            end


            if (sent_keys !== wanted_state) begin

                $display(
                    "ERROR: sent_keys mismatch. Expected=%h Actual=%h",
                    wanted_state,
                    sent_keys
                );

                $fatal(1);

            end


            if (busy !== 1'b0) begin

                $display(
                    "ERROR: busy should be LOW after processing"
                );

                $fatal(1);

            end


            $display(
                "CASE PASS: sent_keys=%h, total_events=%0d",
                sent_keys,
                received_count
            );

        end

    endtask


    // ============================================================
    // Event scoreboard
    // ============================================================

    always @(posedge clk) begin

        #1;

        if (rst_n && event_valid) begin

            if (received_count >= expected_count) begin

                $display(
                    "ERROR: unexpected event! on=%b note=%0d",
                    event_on,
                    event_note
                );

                $fatal(1);

            end


            if (
                event_on !==
                expected_on[received_count]
            ) begin

                $display(
                    "ERROR: event_on mismatch at event %0d",
                    received_count
                );

                $fatal(1);

            end


            if (
                event_note !==
                expected_note[received_count]
            ) begin

                $display(
                    "ERROR: note mismatch at event %0d. Expected=%0d Got=%0d",
                    received_count,
                    expected_note[received_count],
                    event_note
                );

                $fatal(1);

            end


            if (event_on) begin

                if (
                    event_fcw !==
                    expected_fcw(event_note)
                ) begin

                    $display(
                        "ERROR: FCW mismatch for MIDI %0d. Got=%h",
                        event_note,
                        event_fcw
                    );

                    $fatal(1);

                end

            end
            else begin

                if (event_fcw !== 32'd0) begin

                    $display(
                        "ERROR: Note Off FCW must be zero"
                    );

                    $fatal(1);

                end

            end


            $display(
                "EVENT %0d: %s MIDI=%0d FCW=%h",
                received_count,
                event_on ? "ON " : "OFF",
                event_note,
                event_fcw
            );


            received_count =
                received_count + 1;

        end

    end


    // ============================================================
    // Test sequence
    // ============================================================

    initial begin

        rst_n       = 1'b0;
        touch_keys  = 16'd0;
        touch_update = 1'b0;

        expected_count = 0;
        received_count = 0;


        repeat (5)
            @(negedge clk);

        rst_n = 1'b1;

        repeat (5)
            @(negedge clk);


        // ========================================================
        // CASE 1
        // Press Touch Key 1 -> C4 MIDI60
        // ========================================================

        $display("\nCASE 1: Single Key Press");

        expect_event(1'b1, 7'd60);

        apply_touch(16'h0001);

        check_case(16'h0001);


        // ========================================================
        // CASE 2
        // Hold Key1 and press Key5 + Key10.
        //
        // 0x0211 = bits 0,4,9
        // ========================================================

        $display("\nCASE 2: Three-Key Chord");

        expect_event(1'b1, 7'd64);
        expect_event(1'b1, 7'd69);

        apply_touch(16'h0211);

        check_case(16'h0211);


        // ========================================================
        // CASE 3
        // Release Key1 and Key10.
        // Keep Key5.
        // Press Key13.
        //
        // Old = 0x0211
        // New = 0x1010
        //
        // OFF 60
        // OFF 69
        // ON  72
        // ========================================================

        $display("\nCASE 3: Mixed Note Off / Note On");

        expect_event(1'b0, 7'd60);
        expect_event(1'b0, 7'd69);
        expect_event(1'b1, 7'd72);

        apply_touch(16'h1010);

        check_case(16'h1010);


        // ========================================================
        // CASE 4
        // Release all remaining notes.
        // ========================================================

        $display("\nCASE 4: Release All");

        expect_event(1'b0, 7'd64);
        expect_event(1'b0, 7'd72);

        apply_touch(16'h0000);

        check_case(16'h0000);


        // ========================================================
        // CASE 5
        // Press all 16 keys at the same time.
        // ========================================================

        $display("\nCASE 5: All 16 Keys Note On");

        for (k = 0; k < 16; k = k + 1) begin

            expect_event(
                1'b1,
                7'd60 + k
            );

        end

        apply_touch(16'hFFFF);

        check_case(16'hFFFF);


        // ========================================================
        // CASE 6
        // Release all 16 keys at the same time.
        // ========================================================

        $display("\nCASE 6: All 16 Keys Note Off");

        for (k = 0; k < 16; k = k + 1) begin

            expect_event(
                1'b0,
                7'd60 + k
            );

        end

        apply_touch(16'h0000);

        check_case(16'h0000);


        // ========================================================
        // CASE 7
        // Retrigger the same key.
        // ========================================================

        $display("\nCASE 7: Repeated Note Retrigger");

        expect_event(1'b1, 7'd60);
        apply_touch(16'h0001);
        check_case(16'h0001);

        expect_event(1'b0, 7'd60);
        apply_touch(16'h0000);
        check_case(16'h0000);

        expect_event(1'b1, 7'd60);
        apply_touch(16'h0001);
        check_case(16'h0001);

        expect_event(1'b0, 7'd60);
        apply_touch(16'h0000);
        check_case(16'h0000);


        // ========================================================
        // CASE 8
        // Unchanged touch state must produce no new events.
        // ========================================================

        $display("\nCASE 8: No Duplicate Events");

        apply_touch(16'h0000);

        check_case(16'h0000);


        // ========================================================
        // CASE 9
        // Four-key chord:
        // Touch1, Touch5, Touch8, Touch13
        // ========================================================

        $display("\nCASE 9: Four-Key Chord");

        expect_event(1'b1, 7'd60);
        expect_event(1'b1, 7'd64);
        expect_event(1'b1, 7'd67);
        expect_event(1'b1, 7'd72);

        apply_touch(16'h1091);

        check_case(16'h1091);


        // ========================================================
        // CASE 10
        // Mixed chord change:
        //
        // Release 1,5,13.
        // Keep 8.
        // Press 2,11.
        //
        // New state:
        // Bit1 + Bit7 + Bit10 = 0x0482
        // ========================================================

        $display("\nCASE 10: Chord Change");

        expect_event(1'b0, 7'd60);
        expect_event(1'b0, 7'd64);
        expect_event(1'b0, 7'd72);

        expect_event(1'b1, 7'd61);
        expect_event(1'b1, 7'd70);

        apply_touch(16'h0482);

        check_case(16'h0482);


        // ========================================================
        // CASE 11
        // Final release.
        // ========================================================

        $display("\nCASE 11: Final Release");

        expect_event(1'b0, 7'd61);
        expect_event(1'b0, 7'd67);
        expect_event(1'b0, 7'd70);

        apply_touch(16'h0000);

        check_case(16'h0000);


        // ========================================================
        // Final result
        // ========================================================

        $display("");
        $display("==========================================");
        $display("TOUCH NOTE EVENT 16 TEST PASS");
        $display("Total validated events: %0d", received_count);
        $display("==========================================");

        $finish;

    end

endmodule