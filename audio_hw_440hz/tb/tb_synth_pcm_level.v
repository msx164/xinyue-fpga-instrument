`timescale 1ns/1ps

module tb_synth_pcm_level;

    // ============================================================
    // Task 9.1-B
    // 32-Voice Synth PCM Amplitude Diagnosis
    //
    // Compare OUTPUT_SHIFT = 0 and OUTPUT_SHIFT = 4
    //
    // Both engines use:
    // - Voice 0 only
    // - A4 / 440 Hz
    // - Original ADSR parameters
    // - Original sine_1024.mem
    //
    // The sample enable interval is shortened to 40 clocks
    // for faster functional simulation.
    //
    // This does NOT change the virtual audio sample rate
    // used for the DDS FCW calculation.
    // ============================================================

    reg clk;
    reg rst_n;

    initial clk = 1'b0;

    always #10 clk = ~clk;


    // ============================================================
    // 1. Accelerated sample enable
    //
    // 32 voices need 32 clocks.
    // 40 clocks is sufficient for one TDM calculation.
    // ============================================================

    reg [5:0] tick_div;
    reg sample_en;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            tick_div <= 6'd0;
            sample_en <= 1'b0;

        end
        else if (tick_div == 6'd39) begin

            tick_div <= 6'd0;
            sample_en <= 1'b1;

        end
        else begin

            tick_div <= tick_div + 1'b1;
            sample_en <= 1'b0;

        end

    end


    // ============================================================
    // 2. Voice input
    // ============================================================

    reg [31:0] gate_mask;

    // Only Voice0 receives an FCW.
    //
    // FCW = round(440 * 2^32 / 48000)
    //
    // Other voices remain at FCW = 0.

    wire [1023:0] fcw_flat;

    assign fcw_flat = {
        {31{32'd0}},
        32'd39370534
    };


    // ============================================================
    // 3. Two synthesizers
    // ============================================================

    wire signed [15:0] pcm_shift0;
    wire signed [15:0] pcm_shift4;

    wire [31:0] active0;
    wire [31:0] active4;

    wire busy0;
    wire busy4;


    // ------------------------------------------------------------
    // Engine A: No attenuation
    // ------------------------------------------------------------

    synth_engine_tdm_32 #(
        .ATTACK_STEP   (15'd14),
        .DECAY_STEP    (15'd3),
        .SUSTAIN_LEVEL (15'd19660),
        .RELEASE_STEP  (15'd2),
        .OUTPUT_SHIFT  (0)
    ) u_shift0 (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_en   (sample_en),

        .gate_mask   (gate_mask),
        .fcw_flat    (fcw_flat),

        .mix_pcm     (pcm_shift0),
        .active_mask (active0),
        .engine_busy (busy0)
    );


    // ------------------------------------------------------------
    // Engine B: Divide voice amplitude by 16
    // ------------------------------------------------------------

    synth_engine_tdm_32 #(
        .ATTACK_STEP   (15'd14),
        .DECAY_STEP    (15'd3),
        .SUSTAIN_LEVEL (15'd19660),
        .RELEASE_STEP  (15'd2),
        .OUTPUT_SHIFT  (4)
    ) u_shift4 (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_en   (sample_en),

        .gate_mask   (gate_mask),
        .fcw_flat    (fcw_flat),

        .mix_pcm     (pcm_shift4),
        .active_mask (active4),
        .engine_busy (busy4)
    );


    // ============================================================
    // 4. Measurement registers
    // ============================================================

    integer frame_number;

    integer max0;
    integer min0;

    integer max4;
    integer min4;

    integer value0;
    integer value4;

    integer crossing_count;

    integer previous_pcm;
    reg previous_valid;

    integer total_cases;


    // ============================================================
    // 5. Sample monitor
    //
    // Collect 1000 samples after ADSR has reached
    // its sustain region.
    //
    // ATTACK:
    //   32767 / 14 ~= 2341 samples
    //
    // DECAY:
    //   (32767 - 19660) / 3 ~= 4369 samples
    //
    // Sustain starts after approximately 6710 samples.
    //
    // Voice is enabled after the first 120 frames.
    // We measure between frames 7200 and 8200.
    // ============================================================

    always @(negedge clk) begin

        if (!rst_n) begin

            frame_number = 0;

            max0 = -32768;
            min0 =  32767;

            max4 = -32768;
            min4 =  32767;

            crossing_count = 0;
            previous_pcm = 0;
            previous_valid = 1'b0;

        end

        else if (sample_en) begin

            frame_number = frame_number + 1;


            // --------------------------------------------
            // Measurement interval
            // --------------------------------------------

            if (
                frame_number >= 7200 &&
                frame_number < 8200
            ) begin

                value0 = $signed(pcm_shift0);
                value4 = $signed(pcm_shift4);


                if (value0 > max0)
                    max0 = value0;

                if (value0 < min0)
                    min0 = value0;

                if (value4 > max4)
                    max4 = value4;

                if (value4 < min4)
                    min4 = value4;


                // Count positive-going zero crossings.
                //
                // Expected:
                // 440 / 48000 * 1000 ~= 9.17 cycles.

                if (previous_valid) begin

                    if (
                        previous_pcm <= 0 &&
                        value0 > 0
                    ) begin

                        crossing_count =
                            crossing_count + 1;

                    end

                end

                previous_pcm = value0;
                previous_valid = 1'b1;

            end

        end

    end


    // ============================================================
    // 6. Main tests
    // ============================================================

    initial begin

        rst_n = 1'b0;
        gate_mask = 32'd0;

        total_cases = 0;

        repeat (10)
            @(posedge clk);

        #1;
        rst_n = 1'b1;


        // ========================================================
        // CASE 1: ROM initialization
        // ========================================================

        $display("");
        $display("CASE 1: Sine ROM initialization");

        #100;

        if (
            u_shift0.sine_rom[0] !== 16'h0000 ||
            u_shift0.sine_rom[256] !== 16'h7FFF
        ) begin

            $display("FAIL: Sine ROM initialization");
            $display(
                "ROM[0]=%h ROM[256]=%h",
                u_shift0.sine_rom[0],
                u_shift0.sine_rom[256]
            );

            $fatal(1);

        end

        if (
            $signed(u_shift0.sine_rom[768]) >
            -16'sd30000
        ) begin

            $display("FAIL: Negative sine ROM peak");
            $fatal(1);

        end

        total_cases = total_cases + 1;
        $display("CASE 1 PASS");


        // ========================================================
        // CASE 2: All voices idle
        // ========================================================

        $display("");
        $display("CASE 2: Silence with all gates OFF");

        wait (frame_number >= 120);

        @(posedge clk);
        #1;

        if (
            pcm_shift0 !== 16'sd0 ||
            pcm_shift4 !== 16'sd0
        ) begin

            $display("FAIL: Nonzero PCM during silence");
            $fatal(1);

        end

        total_cases = total_cases + 1;
        $display("CASE 2 PASS");


        // ========================================================
        // CASE 3: Start Voice0
        // ========================================================

        $display("");
        $display("CASE 3: Enable Voice0");

        gate_mask = 32'h00000001;

        wait (frame_number >= 150);

        @(posedge clk);
        #1;

        if (
            active0[0] !== 1'b1 ||
            active4[0] !== 1'b1
        ) begin

            $display("FAIL: Voice0 did not activate");
            $fatal(1);

        end

        total_cases = total_cases + 1;
        $display("CASE 3 PASS");


        // ========================================================
        // CASE 4: Engine scheduler
        // ========================================================

        $display("");
        $display("CASE 4: TDM scheduler");

        wait (frame_number >= 500);

        @(posedge clk);
        #1;

        if (
            busy0 !== 1'b0 ||
            busy4 !== 1'b0
        ) begin

            // At this point we are not guaranteed to be
            // exactly outside the 32-clock processing window,
            // so wait until both are idle.

            wait (
                busy0 == 1'b0 &&
                busy4 == 1'b0
            );

        end

        if (
            active0[31:1] !== 31'd0 ||
            active4[31:1] !== 31'd0
        ) begin

            $display("FAIL: Unexpected active voice");
            $fatal(1);

        end

        total_cases = total_cases + 1;
        $display("CASE 4 PASS");


        // ========================================================
        // Wait until the end of amplitude collection.
        // ========================================================

        $display("");
        $display("Waiting for sustain amplitude window...");

        wait (frame_number >= 8200);

        @(posedge clk);
        #1;


        // ========================================================
        // CASE 5: SHIFT=0 amplitude
        // ========================================================

        $display("");
        $display("CASE 5: OUTPUT_SHIFT=0 amplitude");

        $display(
            "SHIFT0: MAX=%0d MIN=%0d",
            max0,
            min0
        );

        if (
            max0 < 17000 ||
            max0 > 21500 ||
            min0 > -17000 ||
            min0 < -21500
        ) begin

            $display("FAIL: SHIFT=0 PCM amplitude");
            $fatal(1);

        end

        total_cases = total_cases + 1;
        $display("CASE 5 PASS");


        // ========================================================
        // CASE 6: SHIFT=4 amplitude
        // ========================================================

        $display("");
        $display("CASE 6: OUTPUT_SHIFT=4 amplitude");

        $display(
            "SHIFT4: MAX=%0d MIN=%0d",
            max4,
            min4
        );

        if (
            max4 < 950 ||
            max4 > 1400 ||
            min4 > -950 ||
            min4 < -1400
        ) begin

            $display("FAIL: SHIFT=4 PCM amplitude");
            $fatal(1);

        end

        total_cases = total_cases + 1;
        $display("CASE 6 PASS");


        // ========================================================
        // CASE 7: Amplitude ratio
        // ========================================================

        $display("");
        $display("CASE 7: SHIFT0 / SHIFT4 ratio");

        if (
            max0 < (max4 * 14) ||
            max0 > (max4 * 18)
        ) begin

            $display("FAIL: Incorrect shift ratio");
            $fatal(1);

        end

        $display(
            "Approximate ratio = %0d",
            max0 / max4
        );

        total_cases = total_cases + 1;
        $display("CASE 7 PASS");


        // ========================================================
        // CASE 8: DDS waveform frequency
        // ========================================================

        $display("");
        $display("CASE 8: DDS pitch verification");

        $display(
            "Positive zero crossings = %0d",
            crossing_count
        );

        if (
            crossing_count < 7 ||
            crossing_count > 11
        ) begin

            $display("FAIL: Incorrect DDS frequency");
            $fatal(1);

        end

        total_cases = total_cases + 1;
        $display("CASE 8 PASS");


        // ========================================================
        // Final report
        // ========================================================

        if (total_cases !== 8) begin

            $display("FAIL: Test count mismatch");
            $fatal(1);

        end

        $display("");
        $display("======================================");
        $display("TASK 9.1-B PCM LEVEL TEST PASS");
        $display("TOTAL CASES: %0d", total_cases);
        $display("======================================");

        $finish;

    end


    // ============================================================
    // Timeout
    // ============================================================

    initial begin

        #10000000;

        $display("FAIL: Simulation timeout");
        $fatal(1);

    end

endmodule