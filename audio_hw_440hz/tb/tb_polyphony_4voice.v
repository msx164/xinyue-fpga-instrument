`timescale 1ns/1ps

module tb_polyphony_4voice;

    reg clk;
    reg rst_n;

    reg sample_en;

    reg gate0;
    reg gate1;
    reg gate2;
    reg gate3;


    wire signed [15:0] mix_pcm;

    wire voice0_active;
    wire voice1_active;
    wire voice2_active;
    wire voice3_active;


    integer file_handle;
    integer sample_count;


    // A4 = 440 Hz
    localparam [31:0] FCW_A4 =
        32'h0258BF26;

    // C5 = 523.251 Hz
    localparam [31:0] FCW_C5 =
        32'h02CA6987;

    // E5 = 659.255 Hz
    localparam [31:0] FCW_E5 =
        32'h03841A5D;

    // G5 = 783.991 Hz
    localparam [31:0] FCW_G5 =
        32'h042E68AC;


    // ============================================================
    // DUT
    // ============================================================
    synth_engine_4 dut (
        .clk           (clk),
        .rst_n         (rst_n),

        .sample_en     (sample_en),

        .gate0         (gate0),
        .gate1         (gate1),
        .gate2         (gate2),
        .gate3         (gate3),

        .fcw0          (FCW_A4),
        .fcw1          (FCW_C5),
        .fcw2          (FCW_E5),
        .fcw3          (FCW_G5),

        .mix_pcm       (mix_pcm),

        .voice0_active (voice0_active),
        .voice1_active (voice1_active),
        .voice2_active (voice2_active),
        .voice3_active (voice3_active)
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
    // Simulation
    // ============================================================
    initial begin

        rst_n = 1'b0;

        sample_en = 1'b0;

        gate0 = 1'b0;
        gate1 = 1'b0;
        gate2 = 1'b0;
        gate3 = 1'b0;

        sample_count = 0;


        #200;

        rst_n = 1'b1;


        // --------------------------------------------------------
        // Accelerated simulation:
        // every clock cycle acts as one audio sample event.
        // --------------------------------------------------------
        @(negedge clk);

        sample_en = 1'b1;

        gate0 = 1'b1;
        gate1 = 1'b1;
        gate2 = 1'b1;
        gate3 = 1'b1;


        // --------------------------------------------------------
        // Wait for envelopes to settle.
        // --------------------------------------------------------
        repeat (15000)
            @(posedge clk);


        // --------------------------------------------------------
        // Capture 4800 samples.
        // --------------------------------------------------------
        file_handle =
            $fopen(
                "polyphony_4voice_pcm.txt",
                "w"
            );


        repeat (4800) begin

            @(posedge clk);

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
            "POLYPHONY 4 VOICE RTL CAPTURE PASS"
        );

        $display(
            "================================"
        );

        $stop;

    end

endmodule