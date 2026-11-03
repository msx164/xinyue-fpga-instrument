module i2s_tx_48m (
    input  wire               clk_48m,
    input  wire               rst_n,

    input  wire signed [15:0] left_sample,
    input  wire signed [15:0] right_sample,

    output reg                i2s_bck,
    output reg                i2s_lrck,
    output reg                i2s_din,

    output reg                frame_tick
);

    // ============================================================
    // Standard Philips I2S transmitter
    //
    // Master clock:     48 MHz
    // Sample rate:      48 kHz
    // BCK:              3.072 MHz
    // Stereo frame:     64 BCK periods
    // Left slot:        32 bits
    // Right slot:       32 bits
    // Audio samples:    signed 16-bit PCM
    //
    // I2S rule:
    // WS changes one BCK before the sample MSB.
    //
    // Outputs change at BCK falling edges.
    // Receiver samples at BCK rising edges.
    // ============================================================


    // ============================================================
    // 1. Fractional BCK divider
    //
    // Desired BCK half-period:
    //
    // 48 MHz / (2 * 3.072 MHz) = 7.8125 clocks
    //
    // 125 / 16 = 7.8125
    //
    // Every 125 input clocks generate 16 BCK edges.
    // ============================================================

    reg [6:0] divider_acc;


    // ============================================================
    // 2. Position within one stereo I2S frame
    //
    // bit_pos = 0..31  : LEFT
    // bit_pos = 32..63 : RIGHT
    //
    // bit_pos identifies the bit at the NEXT BCK
    // rising edge.
    // ============================================================

    reg [5:0] bit_pos;


    // ============================================================
    // 3. Latched PCM samples
    //
    // Samples are captured once per stereo frame.
    // A changed input will take effect on the next
    // frame boundary.
    // ============================================================

    reg [15:0] left_hold;
    reg [15:0] right_hold;


    // ============================================================
    // 4. BCK and I2S serial generation
    // ============================================================

    always @(posedge clk_48m or negedge rst_n) begin

        if (!rst_n) begin

            divider_acc <= 7'd0;

            // Start HIGH so the first generated
            // BCK edge is falling.
            i2s_bck  <= 1'b1;
            i2s_lrck <= 1'b1;
            i2s_din  <= 1'b0;

            bit_pos <= 6'd0;

            left_hold  <= 16'd0;
            right_hold <= 16'd0;

            frame_tick <= 1'b0;

        end
        else begin

            // Default: no new audio frame.
            frame_tick <= 1'b0;

            // ----------------------------------------------------
            // Fractional divider event
            // ----------------------------------------------------

            if (divider_acc >= 7'd109) begin

                divider_acc <=
                    divider_acc + 7'd16 - 7'd125;


                // ------------------------------------------------
                // Falling BCK edge:
                //
                // Update LRCK and DIN.
                //
                // Data is stable before the next
                // rising BCK edge.
                // ------------------------------------------------

                if (i2s_bck) begin

                    i2s_bck <= 1'b0;

                    // bit positions 0..31: LEFT
                    // bit positions 32..63: RIGHT

                    i2s_lrck <= (bit_pos >= 6'd32);


                    // Capture one stereo sample pair
                    // at the beginning of a new frame.

                    if (bit_pos == 6'd0) begin

                        left_hold  <= left_sample;
                        right_hold <= right_sample;

                        frame_tick <= 1'b1;

                    end


                    // Standard I2S:
                    //
                    // bit 0  : one-bit delay
                    // bit 1  : left MSB
                    // ...
                    // bit 16 : left LSB
                    //
                    // bit 32 : one-bit delay
                    // bit 33 : right MSB
                    // ...
                    // bit 48 : right LSB

                    if (bit_pos == 6'd0 ||
                        bit_pos == 6'd32) begin

                        i2s_din <= 1'b0;

                    end
                    else if (bit_pos >= 6'd1 &&
                             bit_pos <= 6'd16) begin

                        i2s_din <=
                            left_hold[16 - bit_pos];

                    end
                    else if (bit_pos >= 6'd33 &&
                             bit_pos <= 6'd48) begin

                        i2s_din <=
                            right_hold[48 - bit_pos];

                    end
                    else begin

                        // Pad unused slot bits with zero.
                        i2s_din <= 1'b0;

                    end

                end


                // ------------------------------------------------
                // Rising BCK edge:
                //
                // The receiver samples the previously
                // prepared WS and DIN.
                //
                // Advance to the next bit position.
                // ------------------------------------------------

                else begin

                    i2s_bck <= 1'b1;

                    if (bit_pos == 6'd63)
                        bit_pos <= 6'd0;
                    else
                        bit_pos <= bit_pos + 1'b1;

                end

            end
            else begin

                divider_acc <= divider_acc + 7'd16;

            end

        end

    end

endmodule