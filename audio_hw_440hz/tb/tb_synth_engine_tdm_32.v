`timescale 1ns/1ps

module tb_synth_engine_tdm_32;

    reg clk;
    reg rst_n;

    reg sample_en;

    reg [31:0] gate_mask;

    reg [1023:0] fcw_flat;


    wire signed [15:0] mix_pcm;

    wire [31:0] active_mask;

    wire engine_busy;


    integer file_handle;
    integer sample_count;


    localparam [31:0] FCW_A4 =
        32'h0258BF26;

    localparam [31:0] FCW_C5 =
        32'h02CA6987;

    localparam [31:0] FCW_E5 =
        32'h03841A5D;

    localparam [31:0] FCW_G5 =
        32'h042E68AC;


    // ============================================================
    // DUT
    // ============================================================

    synth_engine_tdm_32 #(
        // Fast ADSR for simulation
        .ATTACK_STEP   (15'd8192),
        .DECAY_STEP    (15'd4096),
        .SUSTAIN_LEVEL (15'd16384),
        .RELEASE_STEP  (15'd4096),

        // Increase simulation volume because only four Voices
        // are currently active.
        .OUTPUT_SHIFT  (3)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),

        .sample_en   (sample_en),

        .gate_mask   (gate_mask),
        .fcw_flat    (fcw_flat),

        .mix_pcm     (mix_pcm),

        .active_mask (active_mask),

        .engine_busy (engine_busy)
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
    // Generate one audio sample request.
    //
    // Wait until the TDM Engine has completed all 32 Voices.
    // ============================================================

    task generate_sample;

        begin

            @(negedge clk);

            sample_en = 1'b1;


            @(negedge clk);

            sample_en = 1'b0;


            wait (
                engine_busy == 1'b1
            );


            wait (
                engine_busy == 1'b0
            );

        end

    endtask


    // ============================================================
    // Test
    // ============================================================

    initial begin

        rst_n = 1'b0;

        sample_en = 1'b0;

        gate_mask = 32'd0;

        fcw_flat = 1024'd0;

        sample_count = 0;


        // --------------------------------------------------------
        // Voice0 = A4
        // --------------------------------------------------------

        fcw_flat[
            0 * 32 +:
            32
        ] = FCW_A4;


        // --------------------------------------------------------
        // Voice1 = C5
        // --------------------------------------------------------

        fcw_flat[
            1 * 32 +:
            32
        ] = FCW_C5;


        // --------------------------------------------------------
        // Voice2 = E5
        // --------------------------------------------------------

        fcw_flat[
            2 * 32 +:
            32
        ] = FCW_E5;


        // --------------------------------------------------------
        // Voice3 = G5
        // --------------------------------------------------------

        fcw_flat[
            3 * 32 +:
            32
        ] = FCW_G5;


        #200;

        rst_n = 1'b1;


        // --------------------------------------------------------
        // Enable first four Voices.
        // --------------------------------------------------------

        gate_mask[3:0] =
            4'b1111;


        // --------------------------------------------------------
        // Let ADSR reach stable region.
        // --------------------------------------------------------

        repeat (20) begin

            generate_sample;

        end


        // --------------------------------------------------------
        // Open PCM file.
        // --------------------------------------------------------

        file_handle =
            $fopen(
                "tdm32_4voice_pcm.txt",
                "w"
            );


        // --------------------------------------------------------
        // Capture 4800 audio samples.
        // --------------------------------------------------------

        repeat (4800) begin

            generate_sample;


            $fwrite(
                file_handle,
                "%0d\n",
                $signed(mix_pcm)
            );


            sample_count =
                sample_count + 1;

        end


        $fclose(file_handle);


        $display("");
        $display(
            "================================"
        );

        $display(
            "Captured samples : %0d",
            sample_count
        );

        $display(
            "Active mask      : %h",
            active_mask
        );

        $display(
            "TDM32 4-VOICE RTL CAPTURE PASS"
        );

        $display(
            "================================"
        );


        $stop;

    end

endmodule