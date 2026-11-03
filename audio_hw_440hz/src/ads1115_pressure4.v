
`timescale 1ns/1ps

module ads1115_pressure4 (
    input  wire clk,
    input  wire rst_n,

    inout  wire scl,
    inout  wire sda,
    input  wire alrt_n,   // ADS1015 ALERT/RDY, 3.3V open-drain (active low)

    output reg [15:0] value0,
    output reg [15:0] value1,
    output reg [15:0] value2,
    output reg [15:0] value3,

    output reg sample_valid,
    output reg ack_error,        // Sticky: historical I2C NACK
    output reg rdy_timeout_seen  // Sticky: any READY timeout since reset
);

    // ====================================================
    // B4-D-31 ADS1015 four-channel event-driven input
    // 48 MHz fabric, ~200 kHz I2C; ADS1015 ADDR=GND (0x48).
    // 12-bit ADC, 3300 SPS, single-shot; MUX AIN0..AIN3.
    // PGA +/-4.096V. The 12-bit conversion result is LEFT ALIGNED
    // in the 16-bit register; low four bits are hardwired zero.
    // Keep value0..value3 as raw 16-bit LEFT-ALIGNED words so the
    // already-calibrated FSR voltage mapping remains unchanged.
    // 0. INIT: Lo_thresh=0x0000 and Hi_thresh=0x8000
    // 1. START conversion using Config OS=1, COMP_QUE=00
    // 2. Wait for RDY high THEN newly asserted low
    // 3. Read Conversion register, publish correct channel
    // 4. Next channel. Timeout/NACK retry without stale data.
    // This is still a SINGLE multiplexed ADC, not parallel ADC.
    // ALERT/RDY is open-drain: use module pull-up, or 4.7k..10k to 3V3.
    // Never connect ALRT to a GPIO still configured as an OUTPUT.
    // No clock stretching/multi-master support (like prior driver).
    // ====================================================

    // ====================================================
    // 1. Open-drain I2C
    // ====================================================

    reg scl_low;
    reg sda_low;

    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;


    // ====================================================
    // 2. Timing tick
    //
    // 48 MHz / 80 = 600 kHz state tick
    // One tick = 1.6667 us; 3 ticks per data bit (~200 kHz SCL)
    // ====================================================

    reg [7:0] divider;

    wire tick = (divider == 8'd79);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            divider <= 8'd0;
        else if (tick)
            divider <= 8'd0;
        else
            divider <= divider + 1'b1;
    end


    // Hardware ALERT/RDY is asynchronous to the 48MHz FPGA clock.
    (* ASYNC_REG = "TRUE" *) reg [2:0] alrt_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) alrt_sync <= 3'b111;
        else        alrt_sync <= {alrt_sync[1:0], alrt_n};
    end

    // ====================================================
    // 3. I2C state definitions
    // ====================================================

    localparam [4:0]
        S_WAIT        = 5'd0,
        S_START       = 5'd1,
        S_START_HOLD  = 5'd2,

        S_TX_LOW      = 5'd3,
        S_TX_RISE     = 5'd4,
        S_TX_END      = 5'd5,

        S_ACK_LOW     = 5'd6,
        S_ACK_RISE    = 5'd7,
        S_ACK_SAMPLE  = 5'd8,

        S_RX_LOW      = 5'd9,
        S_RX_RISE     = 5'd10,
        S_RX_SAMPLE   = 5'd11,

        S_RXACK_LOW   = 5'd12,
        S_RXACK_RISE  = 5'd13,
        S_RXACK_DONE  = 5'd14,

        S_STOP_LOW    = 5'd15,
        S_STOP_HIGH   = 5'd16,
        S_STOP_END    = 5'd17,
        S_RDY_WAIT    = 5'd18;


    // ====================================================
    // 4. Registers
    // ====================================================

    reg [4:0] state;

    // Transaction sequencing:
    // 0: write Lo_thresh = 0x0000 (once at startup)
    // 1: write Hi_thresh = 0x8000 (once at startup)
    // 2: write CONFIG register; starts single-shot conversion
    // 3: select conversion register after RDY
    // 4: read conversion register

    reg [2:0] sequence;
    reg [1:0] channel;

    reg [2:0] byte_index;
    reg [2:0] bit_index;

    reg rx_byte_index;

    reg [7:0] tx_byte;
    reg [15:0] rx_shift;

    reg [15:0] wait_ticks;
    // A NACK must not advance the channel or read stale conversion data.
    reg transaction_error;

    // Timeout is in 1.667us I2C engine ticks. 1800 ticks = 3ms.
    localparam [11:0] RDY_TIMEOUT_TICKS = 12'd1800;
    reg [11:0] rdy_ticks;
    reg rdy_seen_high;  // Reject prior conversion's asserted LOW.
    reg [1:0] rdy_fail_streak; // Reinitialize thresholds after 3 fails.



    // ====================================================
    // 5. I2C transmit data
    // ====================================================

    function [7:0] tx_data;
        input [2:0] seq;
        input [2:0] idx;
        input [1:0] ch;
        begin
            tx_data = 8'h00;
            case (seq)
                3'd0: begin // Lo_thresh register (pointer=0x02), 0x0000
                    case (idx)
                        3'd0: tx_data = 8'h90;
                        3'd1: tx_data = 8'h02;
                        3'd2: tx_data = 8'h00;
                        3'd3: tx_data = 8'h00;
                        default: tx_data = 8'h00;
                    endcase
                end
                3'd1: begin // Hi_thresh register (pointer=0x03), 0x8000
                    case (idx)
                        3'd0: tx_data = 8'h90;
                        3'd1: tx_data = 8'h03;
                        3'd2: tx_data = 8'h80;
                        3'd3: tx_data = 8'h00;
                        default: tx_data = 8'h00;
                    endcase
                end
                3'd2: begin // ADS1015 config: OS=1, 3300SPS, MUX channel
                    case (idx)
                        3'd0: tx_data = 8'h90;
                        3'd1: tx_data = 8'h01;
                        3'd2: tx_data = 8'hC3 | {2'b00, ch, 4'b0000};
                        // Low=E0: MODE=single-shot, DR=111=3300SPS,
                        // COMP_MODE=traditional, COMP_POL=0,
                        // COMP_QUE=00 => ALERT/RDY enabled, active LOW.
                        3'd3: tx_data = 8'hE0;
                        default: tx_data = 8'h00;
                    endcase
                end
                3'd3: begin // Pointer selection for conversion register
                    case (idx)
                        3'd0: tx_data = 8'h90;
                        3'd1: tx_data = 8'h00;
                        default: tx_data = 8'h00;
                    endcase
                end
                3'd4: tx_data = 8'h91; // Read 2-byte conversion result
                default: tx_data = 8'h00;
            endcase
        end
    endfunction


    // ====================================================
    // 6. Main I2C state machine
    // ====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            // --------------------------------------------
            // Reset
            // --------------------------------------------

            state <= S_WAIT;

            sequence <= 3'd0;
            channel <= 2'd0;

            byte_index <= 3'd0;
            bit_index <= 3'd7;

            rx_byte_index <= 1'b0;

            tx_byte <= 8'd0;
            rx_shift <= 16'd0;

            // Initial delay: 1200 * (80/48MHz) = 2 ms
            wait_ticks <= 16'd1200;
            transaction_error <= 1'b0;
            rdy_timeout_seen <= 1'b0;
            rdy_ticks <= 12'd0;
            rdy_seen_high <= 1'b0;
            rdy_fail_streak <= 2'd0;

            // Release I2C bus
            scl_low <= 1'b0;
            sda_low <= 1'b0;

            value0 <= 16'd0;
            value1 <= 16'd0;
            value2 <= 16'd0;
            value3 <= 16'd0;

            sample_valid <= 1'b0;
            ack_error <= 1'b0;

        end

        else begin

            sample_valid <= 1'b0;

            if (tick) begin

                case (state)

                    // ====================================
                    // IDLE / WAIT
                    // ====================================

                    S_WAIT: begin

                        scl_low <= 1'b0;
                        sda_low <= 1'b0;

                        if (wait_ticks != 16'd0) begin

                            wait_ticks <= wait_ticks - 1'b1;

                        end

                        else begin

                            byte_index <= 3'd0;
                            bit_index <= 3'd7;

                            tx_byte <= tx_data(
                                sequence,
                                3'd0,
                                channel
                            );

                            state <= S_START;

                        end

                    end


                    // ====================================
                    // I2C START
                    // ====================================

                    S_START: begin

                        scl_low <= 1'b0;
                        sda_low <= 1'b1;

                        state <= S_START_HOLD;

                    end


                    S_START_HOLD: begin

                        scl_low <= 1'b1;
                        sda_low <= 1'b1;

                        state <= S_TX_LOW;

                    end


                    // ====================================
                    // Transmit one byte, MSB first
                    // ====================================

                    S_TX_LOW: begin

                        scl_low <= 1'b1;

                        sda_low <= ~tx_byte[bit_index];

                        state <= S_TX_RISE;

                    end


                    S_TX_RISE: begin

                        scl_low <= 1'b0;

                        state <= S_TX_END;

                    end


                    S_TX_END: begin

                        scl_low <= 1'b1;

                        if (bit_index == 3'd0) begin

                            state <= S_ACK_LOW;

                        end

                        else begin

                            bit_index <= bit_index - 1'b1;

                            state <= S_TX_LOW;

                        end

                    end


                    // ====================================
                    // Receive ACK after transmitted byte
                    // ====================================

                    S_ACK_LOW: begin

                        scl_low <= 1'b1;

                        // Release SDA for ADS1015 ACK
                        sda_low <= 1'b0;

                        state <= S_ACK_RISE;

                    end


                    S_ACK_RISE: begin

                        scl_low <= 1'b0;

                        state <= S_ACK_SAMPLE;

                    end


                    S_ACK_SAMPLE: begin

                        scl_low <= 1'b1;

                        // --------------------------------
                        // NACK detected
                        // --------------------------------

                        if (sda != 1'b0) begin

                            ack_error <= 1'b1;
                            transaction_error <= 1'b1;

                            state <= S_STOP_LOW;

                        end


                        // --------------------------------
                        // Read transaction:
                        // Address ACK received
                        // --------------------------------

                        else if (sequence == 3'd4) begin

                            bit_index <= 3'd7;

                            rx_byte_index <= 1'b0;

                            rx_shift <= 16'd0;

                            state <= S_RX_LOW;

                        end


                        // --------------------------------
                        // More bytes to transmit
                        // --------------------------------

                        else if (
                            ((sequence == 3'd0 ||
                              sequence == 3'd1 ||
                              sequence == 3'd2) &&
                             byte_index < 3'd3) ||

                            (sequence == 3'd3 &&
                             byte_index < 3'd1)
                        ) begin

                            byte_index <= byte_index + 1'b1;

                            bit_index <= 3'd7;

                            tx_byte <= tx_data(
                                sequence,
                                byte_index + 1'b1,
                                channel
                            );

                            state <= S_TX_LOW;

                        end


                        // --------------------------------
                        // Transmission completed
                        // --------------------------------

                        else begin

                            state <= S_STOP_LOW;

                        end

                    end


                    // ====================================
                    // Receive ADC data bits
                    // ====================================

                    S_RX_LOW: begin

                        scl_low <= 1'b1;

                        // Release SDA for receiving
                        sda_low <= 1'b0;

                        state <= S_RX_RISE;

                    end


                    S_RX_RISE: begin

                        scl_low <= 1'b0;

                        state <= S_RX_SAMPLE;

                    end


                    S_RX_SAMPLE: begin

                        rx_shift <= {
                            rx_shift[14:0],
                            sda
                        };

                        scl_low <= 1'b1;

                        if (bit_index == 3'd0) begin

                            state <= S_RXACK_LOW;

                        end

                        else begin

                            bit_index <= bit_index - 1'b1;

                            state <= S_RX_LOW;

                        end

                    end


                    // ====================================
                    // ACK first byte, NACK second byte
                    // ====================================

                    S_RXACK_LOW: begin

                        scl_low <= 1'b1;

                        // First byte: ACK
                        // Second byte: NACK
                        sda_low <= !rx_byte_index;

                        state <= S_RXACK_RISE;

                    end


                    S_RXACK_RISE: begin

                        scl_low <= 1'b0;

                        state <= S_RXACK_DONE;

                    end


                    S_RXACK_DONE: begin

                        scl_low <= 1'b1;

                        if (!rx_byte_index) begin

                            // Receive second data byte
                            rx_byte_index <= 1'b1;

                            bit_index <= 3'd7;

                            state <= S_RX_LOW;

                        end

                        else begin

                            // --------------------------------
                            // Store ADS1015 result (12-bit left-aligned).
                            // IMPORTANT: do not shift right by 4 here!
                            // Existing top.v calibration assumes 16-bit
                            // left-aligned output, e.g. 1V ~= 8000.
                            // --------------------------------

                            case (channel)

                                2'd0: begin
                                    value0 <= rx_shift;
                                end

                                2'd1: value1 <= rx_shift;

                                2'd2: value2 <= rx_shift;

                                2'd3: value3 <= rx_shift;

                            endcase

                            sample_valid <= 1'b1;

                            state <= S_STOP_LOW;

                        end

                    end


                    // ====================================
                    // I2C STOP
                    // ====================================

                    S_STOP_LOW: begin

                        scl_low <= 1'b1;
                        sda_low <= 1'b1;

                        state <= S_STOP_HIGH;

                    end


                    S_STOP_HIGH: begin

                        scl_low <= 1'b0;
                        sda_low <= 1'b1;

                        state <= S_STOP_END;

                    end


                    S_STOP_END: begin
                        scl_low <= 1'b0;
                        sda_low <= 1'b0;

                        if (transaction_error) begin
                            // Transaction NACK. Retry same channel, never
                            // publish a failed or stale conversion.
                            transaction_error <= 1'b0;
                            if (sequence <= 3'd1)
                                sequence <= 3'd0; // Retry initialization
                            else
                                sequence <= 3'd2; // Retry same input
                            wait_ticks <= 16'd120; // 200us backoff
                            state <= S_WAIT;
                        end
                        else if (sequence == 3'd0) begin
                            sequence <= 3'd1; // set Hi_thresh
                            wait_ticks <= 16'd0;
                            state <= S_WAIT;
                        end
                        else if (sequence == 3'd1) begin
                            sequence <= 3'd2; // start channel 0 conversion
                            wait_ticks <= 16'd0;
                            state <= S_WAIT;
                        end
                        else if (sequence == 3'd2) begin
                            // CONFIG write starts the conversion. Do not
                            // trust a LOW already left over from a prior
                            // channel. First observe HIGH then new LOW.
                            rdy_seen_high <= 1'b0;
                            rdy_ticks <= 12'd0;
                            sequence <= 3'd3;
                            state <= S_RDY_WAIT;
                        end
                        else if (sequence == 3'd3) begin
                            sequence <= 3'd4; // now read conversion value
                            wait_ticks <= 16'd0;
                            state <= S_WAIT;
                        end
                        else begin // sequence=4 completed: next channel
                            sequence <= 3'd2;
                            channel <= channel + 1'b1;
                            rdy_fail_streak <= 2'd0;
                            wait_ticks <= 16'd0;
                            state <= S_WAIT;
                        end
                    end

                    // New conversion-ready handshake. ADS1015 SINGLE-SHOT:
                    // ALERT/RDY is driven low when conversion completes.
                    // Timer bounds a broken/disconnected ALERT wire.
                    S_RDY_WAIT: begin
                        scl_low <= 1'b0;
                        sda_low <= 1'b0;
                        if (alrt_sync[2] == 1'b1)
                            rdy_seen_high <= 1'b1;

                        if (rdy_seen_high && alrt_sync[2] == 1'b0) begin
                            wait_ticks <= 16'd0;
                            state <= S_WAIT; // sequence=3: set pointer
                        end
                        else if (rdy_ticks >= RDY_TIMEOUT_TICKS) begin
                            rdy_timeout_seen <= 1'b1;
                            // Re-initialize thresholds if RDY is missing
                            // repeatedly (e.g. ADC was power cycled).
                            if (rdy_fail_streak == 2'd2) begin
                                sequence <= 3'd0;
                                rdy_fail_streak <= 2'd0;
                            end
                            else begin
                                sequence <= 3'd2; // same channel retry
                                rdy_fail_streak <= rdy_fail_streak + 1'b1;
                            end
                            wait_ticks <= 16'd120; // 200us recovery
                            state <= S_WAIT;
                        end
                        else begin
                            rdy_ticks <= rdy_ticks + 1'b1;
                        end
                    end

                    // ====================================
                    // Default recovery
                    // ====================================

                    default: begin

                        state <= S_WAIT;

                        scl_low <= 1'b0;
                        sda_low <= 1'b0;

                    end

                endcase

            end

        end

    end

endmodule
