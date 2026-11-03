`timescale 1ns/1ps

module tb_polyphony_2voice;

    reg clk;
    reg rst_n;

    reg sample_en;

    reg gate0;
    reg gate1;


    wire signed [15:0] voice0_pcm;
    wire signed [15:0] voice1_pcm;

    wire signed [15:0] mix_pcm;


    wire voice0_active;
    wire voice1_active;


    integer file_handle;
    integer sample_count;


    localparam [31:0] FCW_A4 =
        32'h0258BF26;

    localparam [31:0] FCW_A5 =
        32'h04B17E4B;


    // ============================================================
    // Voice 0
    //
    // Fast ADSR values are used only for simulation.
    // ============================================================
    synth_voice #(
        .ATTACK_STEP   (15'd8192),
        .DECAY_STEP    (15'd4096),
        .SUSTAIN_LEVEL (15'd16384),
        .RELEASE_STEP  (15'd4096),

        .OUTPUT_SHIFT  (3)
    ) u_voice0 (
        .clk        (clk),
        .rst_n      (rst_n),

        .sample_en  (sample_en),
        .gate       (gate0),

        .fcw        (FCW_A4),

        .pcm_out    (voice0_pcm),
        .env_active (voice0_active)
    );


    // ============================================================
    // Voice 1
    // ============================================================
    synth_voice #(
        .ATTACK_STEP   (15'd8192),
        .DECAY_STEP    (15'd4096),
        .SUSTAIN_LEVEL (15'd16384),
        .RELEASE_STEP  (15'd4096),

        .OUTPUT_SHIFT  (3)
    ) u_voice1 (
        .clk        (clk),
        .rst_n      (rst_n),

        .sample_en  (sample_en),
        .gate       (gate1),

        .fcw        (FCW_A5),

        .pcm_out    (voice1_pcm),
        .env_active (voice1_active)
    );


    // ============================================================
    // Mixer
    // ============================================================
    audio_mixer_2 u_mixer (
        .voice0_pcm (voice0_pcm),
        .voice1_pcm (voice1_pcm),

        .mix_pcm    (mix_pcm)
    );


    // ============================================================
    // Simulation clock
    // ============================================================
    initial begin

        clk = 1'b0;

        forever #10.416667
            clk = ~clk;

    end


    // ============================================================
    // Test
    // ============================================================
    initial begin

        rst_n = 1'b0;

        sample_en = 1'b0;

        gate0 = 1'b0;
        gate1 = 1'b0;

        sample_count = 0;


        #200;

        rst_n = 1'b1;


        // --------------------------------------------------------
        // For fast simulation, every clock is treated as one
        // audio sample event.
        //
        // DDS frequency is determined by the sample sequence,
        // so the captured PCM can still be analyzed as 48 kHz.
        // --------------------------------------------------------
        @(negedge clk);

        sample_en = 1'b1;

        gate0 = 1'b1;
        gate1 = 1'b1;


        // --------------------------------------------------------
        // Allow ADSR to reach stable level.
        // --------------------------------------------------------
        repeat (20)
            @(posedge clk);


        // --------------------------------------------------------
        // Capture 4800 audio samples
        // --------------------------------------------------------
        file_handle =
            $fopen(
                "polyphony_2voice_pcm.txt",
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
            "POLYPHONY 2 VOICE RTL CAPTURE PASS"
        );

        $display(
            "================================"
        );


        $stop;

    end

endmodule