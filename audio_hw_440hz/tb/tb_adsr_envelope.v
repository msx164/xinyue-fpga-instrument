`timescale 1ns/1ps

module tb_adsr_envelope;

    reg clk;
    reg rst_n;

    reg sample_en;
    reg gate;

    wire [14:0] env_level;
    wire        env_active;

    integer error_count;


    // ============================================================
    // DUT
    //
    // Use much larger steps for fast simulation.
    // ============================================================
    adsr_envelope #(
        .ATTACK_STEP   (15'd8192),
        .DECAY_STEP    (15'd4096),
        .SUSTAIN_LEVEL (15'd16384),
        .RELEASE_STEP  (15'd4096)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),

        .sample_en  (sample_en),
        .gate       (gate),

        .env_level  (env_level),
        .env_active (env_active)
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
    // Generate one audio sample enable pulse
    // ============================================================
    task do_sample;

        begin

            @(negedge clk);

            sample_en = 1'b1;

            @(negedge clk);

            sample_en = 1'b0;

        end

    endtask


    // ============================================================
    // Test sequence
    // ============================================================
    initial begin

        rst_n      = 1'b0;
        sample_en  = 1'b0;
        gate       = 1'b0;

        error_count = 0;


        // --------------------------------------------------------
        // Reset
        // --------------------------------------------------------
        #200;

        rst_n = 1'b1;

        #100;


        // ========================================================
        // Test IDLE
        // ========================================================
        if (
            env_level !== 15'd0 ||
            env_active !== 1'b0
        ) begin

            $display(
                "IDLE TEST FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "IDLE TEST PASS"
            );

        end


        // ========================================================
        // Gate ON
        // ========================================================
        gate = 1'b1;


        // First sample enters ATTACK state.
        do_sample;


        // Generate Attack samples.
        repeat (5) begin

            do_sample;

        end


        if (env_level == 15'd0) begin

            $display(
                "ATTACK TEST FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "ATTACK TEST PASS"
            );

        end


        // ========================================================
        // Allow Decay to reach Sustain
        // ========================================================
        repeat (6) begin

            do_sample;

        end


        if (env_level !== 15'd16384) begin

            $display(
                "SUSTAIN LEVEL FAIL: %0d",
                env_level
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "SUSTAIN LEVEL PASS"
            );

        end


        // ========================================================
        // Hold sustain
        // ========================================================
        repeat (5) begin

            do_sample;

        end


        if (env_level !== 15'd16384) begin

            $display(
                "SUSTAIN HOLD FAIL"
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "SUSTAIN HOLD PASS"
            );

        end


        // ========================================================
        // Gate OFF
        // ========================================================
        gate = 1'b0;


        // Enter Release state.
        do_sample;


        // Release toward zero.
        repeat (6) begin

            do_sample;

        end


        if (env_level !== 15'd0) begin

            $display(
                "RELEASE TEST FAIL: %0d",
                env_level
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "RELEASE TEST PASS"
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
                "ADSR ENVELOPE TEST PASS"
            );

        end
        else begin

            $display(
                "ADSR ENVELOPE TEST FAIL"
            );

        end


        $display(
            "================================"
        );

        $stop;

    end

endmodule