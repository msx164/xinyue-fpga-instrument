
`timescale 1ns/1ps

module pt8211_tx_48m (
    input  wire               clk_48m,
    input  wire               rst_n,

    input  wire signed [15:0] left_sample,
    input  wire signed [15:0] right_sample,

    // Existing PT8211 outputs
    output reg                pt_bck,
    output reg                pt_ws,
    output reg                pt_din,

    // New standard Philips I2S word select
    output reg                i2s_lrck,

    output reg                frame_tick
);

    // 48MHz to 1.536MHz BCK fractional divider.
    // 32 BCK cycles per stereo frame -> 48kHz.

    reg [7:0] frac_acc;
    reg [4:0] bit_index;

    reg signed [15:0] left_buf;
    reg signed [15:0] right_buf;

    reg started;

    // PT data order:
    //   bits  0..15 : Right[15:0]
    //   bits 16..31 : Left [15:0]
    //
    // PT8211:
    //   WS=0 Right, WS=1 Left
    //
    // Standard I2S:
    //   LRCK=0 Left, LRCK=1 Right
    //   LRCK changes one BCK cycle before MSB.
    //
    // Therefore, the original DIN stream can be reused,
    // provided LRCK is advanced relative to PT8211 WS.

    always @(posedge clk_48m or negedge rst_n) begin

        if (!rst_n) begin

            frac_acc  <= 8'd0;
            bit_index <= 5'd0;

            left_buf  <= 16'sd0;
            right_buf <= 16'sd0;

            pt_bck <= 1'b0;
            pt_ws  <= 1'b0;
            pt_din <= 1'b0;

            i2s_lrck <= 1'b1;

            frame_tick <= 1'b0;
            started    <= 1'b0;

        end
        else begin

            frame_tick <= 1'b0;

            // Accumulator overflow threshold:
            // each BCK transition takes approximately
            // 125/8 cycles of the 48MHz clock.

            if (frac_acc >= 8'd117) begin

                frac_acc <= frac_acc + 8'd8 - 8'd125;

                // ----------------------------------------
                // Startup: preload first Right MSB
                // ----------------------------------------

                if (!started) begin

                    started <= 1'b1;

                    pt_bck <= 1'b0;
                    pt_ws  <= 1'b0;

                    i2s_lrck <= 1'b1;

                    left_buf  <= left_sample;
                    right_buf <= right_sample;

                    pt_din <= right_sample[15];

                    bit_index <= 5'd0;
                    frame_tick <= 1'b1;

                end

                // ----------------------------------------
                // BCK rising edge:
                // DAC samples serial DIN
                // ----------------------------------------

                else if (pt_bck == 1'b0) begin

                    pt_bck <= 1'b1;

                end

                // ----------------------------------------
                // BCK falling edge:
                // prepare next serial data bit
                // ----------------------------------------

                else begin

                    pt_bck <= 1'b0;

                    // Last Left bit sampled:
                    // start the following stereo frame.

                    if (bit_index == 5'd31) begin

                        left_buf  <= left_sample;
                        right_buf <= right_sample;

                        pt_ws <= 1'b0;
                        pt_din <= right_sample[15];

                        bit_index <= 5'd0;
                        frame_tick <= 1'b1;

                        // i2s_lrck already HIGH,
                        // set during the previous Left LSB.

                    end

                    // Right[14] down to Right[0]

                    else if (bit_index < 5'd15) begin

                        bit_index <= bit_index + 1'b1;

                        pt_ws <= 1'b0;

                        pt_din <=
                            right_buf[14 - bit_index];

                        // Right[0] is about to be sent.
                        // Change I2S LRCK one bit
                        // before the next Left MSB.

                        if (bit_index == 5'd14)
                            i2s_lrck <= 1'b0;

                    end

                    // Right[0] sampled:
                    // prepare Left MSB.

                    else if (bit_index == 5'd15) begin

                        bit_index <= 5'd16;

                        pt_ws <= 1'b1;
                        pt_din <= left_buf[15];

                    end

                    // Left[14] down to Left[0]

                    else begin

                        bit_index <= bit_index + 1'b1;

                        pt_ws <= 1'b1;

                        pt_din <=
                            left_buf[30 - bit_index];

                        // Left[0] is about to be sent.
                        // Change I2S LRCK one bit
                        // before the next Right MSB.

                        if (bit_index == 5'd30)
                            i2s_lrck <= 1'b1;

                    end

                end

            end
            else begin

                frac_acc <= frac_acc + 8'd8;

            end

        end

    end

endmodule
