`timescale 1ns/1ps

module tb_audio_mixer_2;

    reg signed [15:0] voice0_pcm;
    reg signed [15:0] voice1_pcm;

    wire signed [15:0] mix_pcm;

    integer error_count;


    audio_mixer_2 dut (
        .voice0_pcm (voice0_pcm),
        .voice1_pcm (voice1_pcm),

        .mix_pcm    (mix_pcm)
    );


    initial begin

        error_count = 0;


        // ========================================================
        // Test 1
        // Normal positive addition
        // ========================================================
        voice0_pcm = 16'sd1000;
        voice1_pcm = 16'sd2000;

        #100;

        if (mix_pcm !== 16'sd3000) begin

            $display(
                "NORMAL POSITIVE MIX FAIL"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "NORMAL POSITIVE MIX PASS"
            );

        end


        // ========================================================
        // Test 2
        // Positive + negative
        // ========================================================
        voice0_pcm = 16'sd3000;
        voice1_pcm = -16'sd1000;

        #100;

        if (mix_pcm !== 16'sd2000) begin

            $display(
                "SIGNED MIX FAIL"
            );

            error_count = error_count + 1;

        end
        else begin

            $display(
                "SIGNED MIX PASS"
            );

        end


        // ========================================================
        // Test 3
        // Positive saturation
        // ========================================================
        voice0_pcm = 16'sd30000;
        voice1_pcm = 16'sd30000;

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
        // Test 4
        // Negative saturation
        // ========================================================
        voice0_pcm = -16'sd30000;
        voice1_pcm = -16'sd30000;

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
                "AUDIO MIXER 2 TEST PASS"
            );
        else
            $display(
                "AUDIO MIXER 2 TEST FAIL"
            );


        $display(
            "================================"
        );

        $stop;

    end

endmodule