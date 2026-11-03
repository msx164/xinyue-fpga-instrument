`timescale 1ns/1ps

module tb_audio_echo;

    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg rst_n = 1'b0;
    reg sample_en = 1'b0;

    reg signed [15:0] dry_pcm = 16'sd0;
    reg [7:0] wet_target = 8'd160;

    wire signed [15:0] pcm_out;

    // Shorten delay to 16 samples for simulation.
    audio_echo #(
        .ADDR_BITS(4)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_en(sample_en),
        .dry_pcm(dry_pcm),
        .wet_target(wet_target),
        .pcm_out(pcm_out)
    );

    integer n;

    initial begin

        repeat (5) @(negedge clk);
        rst_n = 1'b1;

        // The first 220 samples establish
        // RAM validity and wet-gain settling.
        for (n = 0; n < 290; n = n + 1) begin

            @(negedge clk);

            sample_en = 1'b1;

            // One 8000-amplitude impulse.
            dry_pcm =
                (n == 220) ? 16'sd8000 : 16'sd0;

            @(negedge clk);
            sample_en = 1'b0;
            dry_pcm = 16'sd0;

            // Allow all processing stages to finish.
            repeat (5) @(negedge clk);

            if (
                n == 220 ||
                n == 236 ||
                n == 252 ||
                n == 268
            ) begin

                $display(
                    "sample=%0d, pcm_out=%0d",
                    n, $signed(pcm_out)
                );

            end

        end

        $finish;
    end

endmodule