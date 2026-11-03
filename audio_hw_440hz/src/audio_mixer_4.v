module audio_mixer_4 (
    input  wire signed [15:0] voice0_pcm,
    input  wire signed [15:0] voice1_pcm,
    input  wire signed [15:0] voice2_pcm,
    input  wire signed [15:0] voice3_pcm,

    output reg  signed [15:0] mix_pcm
);

    // ------------------------------------------------------------
    // Four signed 16-bit values require an 18-bit accumulator.
    // ------------------------------------------------------------
    wire signed [17:0] voice0_ext;
    wire signed [17:0] voice1_ext;
    wire signed [17:0] voice2_ext;
    wire signed [17:0] voice3_ext;

    wire signed [17:0] mix_sum;


    // ============================================================
    // Sign extension
    // ============================================================
    assign voice0_ext = {
        {2{voice0_pcm[15]}},
        voice0_pcm
    };

    assign voice1_ext = {
        {2{voice1_pcm[15]}},
        voice1_pcm
    };

    assign voice2_ext = {
        {2{voice2_pcm[15]}},
        voice2_pcm
    };

    assign voice3_ext = {
        {2{voice3_pcm[15]}},
        voice3_pcm
    };


    // ============================================================
    // 4-voice summation
    // ============================================================
    assign mix_sum =
        voice0_ext +
        voice1_ext +
        voice2_ext +
        voice3_ext;


    // ============================================================
    // Signed 16-bit saturation
    // ============================================================
    always @(*) begin

        if (mix_sum > 18'sd32767) begin

            mix_pcm = 16'sh7FFF;

        end
        else if (mix_sum < -18'sd32768) begin

            mix_pcm = -16'sd32768;

        end
        else begin

            mix_pcm = mix_sum[15:0];

        end

    end

endmodule