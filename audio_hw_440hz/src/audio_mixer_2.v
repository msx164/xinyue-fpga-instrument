module audio_mixer_2 (
    input  wire signed [15:0] voice0_pcm,
    input  wire signed [15:0] voice1_pcm,

    output reg  signed [15:0] mix_pcm
);

    // ------------------------------------------------------------
    // 17-bit extended signals
    // ------------------------------------------------------------
    wire signed [16:0] voice0_ext;
    wire signed [16:0] voice1_ext;

    wire signed [16:0] mix_sum;


    // ============================================================
    // Sign extension
    // ============================================================
    assign voice0_ext = {
        voice0_pcm[15],
        voice0_pcm
    };


    assign voice1_ext = {
        voice1_pcm[15],
        voice1_pcm
    };


    // ============================================================
    // Sum
    // ============================================================
    assign mix_sum =
        voice0_ext +
        voice1_ext;


    // ============================================================
    // Saturation
    //
    // Prevent signed 16-bit overflow.
    // ============================================================
    always @(*) begin

        if (mix_sum > 17'sd32767) begin

            mix_pcm = 16'sh7FFF;

        end
        else if (mix_sum < -17'sd32768) begin

            mix_pcm = -16'sd32768;

        end
        else begin

            mix_pcm = mix_sum[15:0];

        end

    end

endmodule