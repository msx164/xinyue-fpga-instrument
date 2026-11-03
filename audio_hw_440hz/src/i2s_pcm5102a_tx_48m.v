
`timescale 1ns/1ps

// B5-F diagnostic / independent Philips I2S transmitter.
// 48 MHz input -> 48 kHz stereo frames, 64 BCK per frame (32 per slot).
// 16-bit signed PCM, MSB first; remaining 16 bits in each slot are zero.
// LRCK LOW = left channel; HIGH = right channel.
// LRCK toggles one BCK ahead of the following channel MSB.
// DIN is prepared on BCK falling edges, sampled on BCK rising edges.
//
// TEST_TONE_ENABLE=1: independent 1 kHz, +/-8192 16-bit diagnostic square tone
// on both channels (no TTP229 / FSR / synth input required).
// TEST_TONE_ENABLE=0: send supplied left/right PCM samples.
//
// Only connects to the external DAC pins. The original PT8211 transmitter
// and its frame_tick remain unchanged.
module i2s_pcm5102a_tx_48m #(
    parameter integer TEST_TONE_ENABLE = 1
)(
    input  wire               clk_48m,
    input  wire               rst_n,
    input  wire signed [15:0] left_sample,
    input  wire signed [15:0] right_sample,
    output reg                i2s_bck,
    output reg                i2s_lrck,
    output reg                i2s_din
);

    // f_BCK = 48 MHz / (2 * (125/16)) = 3.072 MHz = 64 * 48 kHz.
    // Fractional half-period length: 7 or 8 clk_48m ticks.
    reg [6:0] div_acc;
    reg [5:0] bit_index;  // Bit most recently sampled, 0..63.

    reg signed [15:0] left_buf;
    reg signed [15:0] right_buf;
    reg [5:0] tone_frame; // 0..47 at 48 kHz = 1 kHz cycle.

    wire signed [15:0] test_pcm =
        (tone_frame < 6'd24) ? 16'sd8192 : -16'sd8192;

    wire signed [15:0] selected_left =
        (TEST_TONE_ENABLE != 0) ? test_pcm : left_sample;
    wire signed [15:0] selected_right =
        (TEST_TONE_ENABLE != 0) ? test_pcm : right_sample;

    wire [5:0] next_index = bit_index + 6'd1;

    always @(posedge clk_48m or negedge rst_n) begin
        if (!rst_n) begin
            div_acc    <= 7'd0;
            bit_index  <= 6'd0;
            left_buf   <= 16'sd0;
            right_buf  <= 16'sd0;
            tone_frame <= 6'd0;
            i2s_bck    <= 1'b0;
            i2s_lrck   <= 1'b0;
            i2s_din    <= 1'b0;
        end else if (div_acc >= 7'd109) begin
            // 125-modulus fractional frequency divider (step 16).
            div_acc <= div_acc + 7'd16 - 7'd125;

            if (!i2s_bck) begin
                // Rising BCK edge: receiver samples existing DIN.
                i2s_bck <= 1'b1;
            end else begin
                // Falling BCK edge: prepare the NEXT serial bit.
                i2s_bck   <= 1'b0;
                bit_index <= next_index;

                // WS advances by one BCK period relative to the next MSB:
                // left bit31 is under HIGH LRCK (right channel upcoming);
                // right bit63 is under LOW LRCK (left channel upcoming).
                i2s_lrck <= (next_index >= 6'd31) &&
                            (next_index <= 6'd62);

                if (next_index == 6'd0) begin
                    // First bit of a new 48 kHz stereo frame.
                    left_buf  <= selected_left;
                    right_buf <= selected_right;
                    i2s_din  <= selected_left[15];

                    if (tone_frame == 6'd47)
                        tone_frame <= 6'd0;
                    else
                        tone_frame <= tone_frame + 6'd1;
                end else if (next_index <= 6'd15) begin
                    // Left, data bit 15..0.
                    i2s_din <= left_buf[6'd15 - next_index];
                end else if (next_index >= 6'd32 &&
                             next_index <= 6'd47) begin
                    // Right, data bit 15..0.
                    i2s_din <= right_buf[6'd47 - next_index];
                end else begin
                    // 16 zero-padding bits at the end of each 32-bit slot.
                    i2s_din <= 1'b0;
                end
            end
        end else begin
            div_acc <= div_acc + 7'd16;
        end
    end
endmodule
