`timescale 1ns/1ps

module tb_i2s_tx_48m;

    // ============================================================
    // 1. 48 MHz test clock
    // ============================================================

    reg clk_48m = 1'b0;

    always #10.416667 clk_48m = ~clk_48m;


    // ============================================================
    // 2. DUT signals
    // ============================================================

    reg rst_n;

    reg signed [15:0] left_sample;
    reg signed [15:0] right_sample;

    wire i2s_bck;
    wire i2s_lrck;
    wire i2s_din;
    wire frame_tick;


    i2s_tx_48m dut (
        .clk_48m      (clk_48m),
        .rst_n        (rst_n),

        .left_sample  (left_sample),
        .right_sample (right_sample),

        .i2s_bck      (i2s_bck),
        .i2s_lrck     (i2s_lrck),
        .i2s_din      (i2s_din),

        .frame_tick   (frame_tick)
    );


    // ============================================================
    // 3. Test patterns
    // ============================================================

    reg [15:0] test_left  [0:3];
    reg [15:0] test_right [0:3];

    reg [15:0] expected_left;
    reg [15:0] expected_right;

    reg expected_ws;
    reg expected_din;

    integer frame_index;
    integer bit_index;
    integer checked_bits;


    // ============================================================
    // 4. Frame timing measurement
    // ============================================================

    integer clock_cycles;
    integer previous_frame_cycle;

    always @(posedge clk_48m) begin

        if (!rst_n)
            clock_cycles <= 0;
        else
            clock_cycles <= clock_cycles + 1;

    end


    // ============================================================
    // 5. Test procedure
    // ============================================================

    initial begin

        rst_n = 1'b0;

        left_sample  = 16'hA55A;
        right_sample = 16'h5AA5;

        checked_bits = 0;
        previous_frame_cycle = 0;


        // Distinct left and right channel patterns.

        test_left[0]  = 16'hA55A;
        test_right[0] = 16'h5AA5;

        test_left[1]  = 16'h1234;
        test_right[1] = 16'hABCD;

        test_left[2]  = 16'hF00F;
        test_right[2] = 16'h0FF0;

        test_left[3]  = 16'h0001;
        test_right[3] = 16'h8000;


        repeat (10)
            @(negedge clk_48m);

        rst_n = 1'b1;


        // ========================================================
        // Validate four complete stereo frames
        // ========================================================

        for (frame_index = 0;
             frame_index < 4;
             frame_index = frame_index + 1) begin

            // Wait for start of next stereo frame.

            @(posedge frame_tick);


            // Expected stereo frame period:
            // 1000 input clocks.

            if (frame_index > 0) begin

                if (
                    clock_cycles -
                    previous_frame_cycle != 1000
                ) begin

                    $display(
                        "FAIL: Frame period=%0d clocks, expected 1000",
                        clock_cycles - previous_frame_cycle
                    );

                    $fatal(1);

                end

            end

            previous_frame_cycle = clock_cycles;


            expected_left  = test_left[frame_index];
            expected_right = test_right[frame_index];


            $display(
                "FRAME %0d: LEFT=%h RIGHT=%h",
                frame_index,
                expected_left,
                expected_right
            );


            // ====================================================
            // Check 64 I2S serial bits.
            // ====================================================

            for (bit_index = 0;
                 bit_index < 64;
                 bit_index = bit_index + 1) begin

                @(posedge i2s_bck);

                #1;


                // ------------------------------------------------
                // Expected WS:
                //
                // 0~31  -> left
                // 32~63 -> right
                // ------------------------------------------------

                expected_ws =
                    (bit_index >= 32);


                // ------------------------------------------------
                // Expected DIN:
                //
                // bit 0 / 32: dummy
                // bit 1..16: left PCM
                // bit 33..48: right PCM
                // other bits: zero
                // ------------------------------------------------

                if (bit_index == 0 ||
                    bit_index == 32) begin

                    expected_din = 1'b0;

                end
                else if (bit_index >= 1 &&
                         bit_index <= 16) begin

                    expected_din =
                        expected_left[16 - bit_index];

                end
                else if (bit_index >= 33 &&
                         bit_index <= 48) begin

                    expected_din =
                        expected_right[48 - bit_index];

                end
                else begin

                    expected_din = 1'b0;

                end


                // ------------------------------------------------
                // Check LRCK
                // ------------------------------------------------

                if (i2s_lrck !== expected_ws) begin

                    $display(
                        "FAIL: LRCK frame=%0d bit=%0d expected=%b actual=%b",
                        frame_index,
                        bit_index,
                        expected_ws,
                        i2s_lrck
                    );

                    $fatal(1);

                end


                // ------------------------------------------------
                // Check DIN
                // ------------------------------------------------

                if (i2s_din !== expected_din) begin

                    $display(
                        "FAIL: DIN frame=%0d bit=%0d expected=%b actual=%b",
                        frame_index,
                        bit_index,
                        expected_din,
                        i2s_din
                    );

                    $fatal(1);

                end


                checked_bits = checked_bits + 1;


                // ------------------------------------------------
                // Change the input samples MID-FRAME.
                //
                // The current frame must continue sending
                // its already captured samples.
                //
                // New samples must appear next frame.
                // ------------------------------------------------

                if (bit_index == 20 &&
                    frame_index < 3) begin

                    left_sample =
                        test_left[frame_index + 1];

                    right_sample =
                        test_right[frame_index + 1];

                end

            end


            $display(
                "FRAME %0d PASS: 64 serial bits",
                frame_index
            );

        end


        // ========================================================
        // Final results
        // ========================================================

        if (checked_bits != 256) begin

            $display(
                "FAIL: checked bits=%0d, expected 256",
                checked_bits
            );

            $fatal(1);

        end


        $display("");
        $display("==========================================");
        $display("I2S TX 48M TEST PASS");
        $display("Stereo frames checked: 4");
        $display("Serial bits checked: %0d", checked_bits);
        $display("Frame period: 1000 clocks");
        $display("==========================================");

        $finish;

    end

endmodule