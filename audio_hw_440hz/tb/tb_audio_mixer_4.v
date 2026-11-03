`timescale 1ns/1ps

module tb_audio_mixer_4;

    reg signed [15:0] voice0_pcm;
    reg signed [15:0] voice1_pcm;
    reg signed [15:0] voice2_pcm;
    reg signed [15:0] voice3_pcm;

    wire signed [15:0] mix_pcm;

    integer error_count;


    audio_mixer_4 dut (
        .voice0_pcm (voice0_pcm),
        .voice1_pcm (voice1_pcm),
        .voice2_pcm (voice2_pcm),
        .voice3_pcm (voice3_pcm),

        .mix_pcm    (mix_pcm)
    );


    initial begin

        error_count = 0;


        // ========================================================
        // Normal addition
        // ========================================================
        voice0_pcm = 16'sd1000;
        voice1_pcm = 16'sd2000;
        voice2_pcm = 16'sd3000;
        voice3_pcm = 16'sd4000;

        #100;

        if (mix_pcm !== 16'sd10000) begin

            $display(
                "NORMAL 4-VOICE MIX FAIL: %0d",
                mix_pcm
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "NORMAL 4-VOICE MIX PASS"
            );

        end


        // ========================================================
        // Signed addition
        // ========================================================
        voice0_pcm = 16'sd5000;
        voice1_pcm = -16'sd2000;
        voice2_pcm = 16'sd1000;
        voice3_pcm = -16'sd1000;

        #100;

        if (mix_pcm !== 16'sd3000) begin

            $display(
                "SIGNED 4-VOICE MIX FAIL: %0d",
                mix_pcm
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "SIGNED 4-VOICE MIX PASS"
            );

        end


        // ========================================================
        // Positive saturation
        // ========================================================
        voice0_pcm = 16'sd20000;
        voice1_pcm = 16'sd20000;
        voice2_pcm = 16'sd20000;
        voice3_pcm = 16'sd20000;

        #100;

        if (mix_pcm !== 16'sd32767) begin

            $display(
                "POSITIVE SATURATION FAIL: %0d",
                mix_pcm
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "POSITIVE SATURATION PASS"
            );

        end


        // ========================================================
        // Negative saturation
        // ========================================================
        voice0_pcm = -16'sd20000;
        voice1_pcm = -16'sd20000;
        voice2_pcm = -16'sd20000;
        voice3_pcm = -16'sd20000;

        #100;

        if (mix_pcm !== -16'sd32768) begin

            $display(
                "NEGATIVE SATURATION FAIL: %0d",
                mix_pcm
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "NEGATIVE SATURATION PASS"
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

        if (error_count == 0)
            $display(
                "AUDIO MIXER 4 TEST PASS"
            );
        else
            $display(
                "AUDIO MIXER 4 TEST FAIL"
            );

        $display(
            "================================"
        );

        $stop;

    end

endmodule