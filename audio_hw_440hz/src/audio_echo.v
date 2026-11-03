`timescale 1ns/1ps

module audio_echo #(
    parameter integer ADDR_BITS = 13
)(
    input  wire clk,
    input  wire rst_n,
    input  wire sample_en,

    input  wire signed [15:0] dry_pcm,
    input  wire [7:0] wet_target,

    output reg signed [15:0] pcm_out
);

    // =====================================================
    // Task 10.5-C
    //
    // 8192 samples at 48 kHz:
    // Delay = 8192 / 48000 = 170.67 ms
    //
    // wet_target: 0..160
    // Feedback gain: 3/8 = 37.5%
    //
    // Output:
    // dry + wet * delayed / 256
    //
    // Delay buffer:
    // dry + 3/8 * delayed
    // =====================================================

    localparam integer DEPTH = (1 << ADDR_BITS);

    // =====================================================
    // 1. Block RAM delay memory
    //
    // Do NOT reset the RAM itself.
    // Startup validity is controlled by fill_count.
    // =====================================================

    (* syn_ramstyle = "block_ram" *)
    reg signed [15:0] delay_mem [0:DEPTH-1];

    reg [ADDR_BITS-1:0] write_ptr;
    reg [ADDR_BITS-1:0] write_addr_q;

    reg signed [15:0] ram_read_q;

    reg [ADDR_BITS:0] fill_count;

    reg tap_valid_q;

    // =====================================================
    // 2. Audio frame pipeline
    // =====================================================

    reg stage1_valid;
    reg stage2_valid;

    reg signed [15:0] dry_q;
    reg [7:0] wet_q;

    // =====================================================
    // 3. Wet-gain smoothing
    //
    // Maximum change: 1/256 per audio frame.
    // Full-scale 160-step transition:
    // approximately 3.33 ms at 48 kHz.
    // =====================================================

    reg [7:0] wet_gain;

    // =====================================================
    // 4. Delayed sample, masked during startup
    // =====================================================

    wire signed [15:0] delayed_pcm =
        tap_valid_q ? ram_read_q : 16'sd0;

    wire signed [16:0] delayed_ext =
        {delayed_pcm[15], delayed_pcm};

    // =====================================================
    // 5. Feedback coefficient = 3/8
    //
    // Shift/add instead of a separate multiplier.
    // =====================================================

    wire signed [16:0] feedback_next =
        (delayed_ext >>> 2) +
        (delayed_ext >>> 3);

    // =====================================================
    // 6. Wet multiplication
    // =====================================================

    wire signed [8:0] wet_coeff =
        $signed({1'b0, wet_q});

    wire signed [24:0] wet_product =
        delayed_pcm * wet_coeff;

    reg signed [24:0] wet_product_q;
    reg signed [16:0] feedback_q;

    wire signed [16:0] wet_scaled =
        wet_product_q >>> 8;

    // =====================================================
    // 7. Saturating audio addition
    // =====================================================

    wire signed [17:0] dry_ext =
        {{2{dry_q[15]}}, dry_q};

    wire signed [17:0] wet_ext =
        {wet_scaled[16], wet_scaled};

    wire signed [17:0] feedback_ext =
        {feedback_q[16], feedback_q};

    wire signed [17:0] output_sum =
        dry_ext + wet_ext;

    wire signed [17:0] buffer_sum =
        dry_ext + feedback_ext;

    function signed [15:0] sat16;
        input signed [17:0] value;
        begin
            if (value > 18'sd32767)
                sat16 = 16'sh7FFF;
            else if (value < -18'sd32768)
                sat16 = 16'sh8000;
            else
                sat16 = value[15:0];
        end
    endfunction

    wire signed [15:0] buffer_write_data =
        sat16(buffer_sum);

    // =====================================================
    // 8. Synchronous block RAM
    //
    // Frame tick: read old sample at write_ptr.
    // Two clocks later: write new feedback sample.
    //
    // Read and write use the same circular slot,
    // but never happen on the same clock edge.
    // =====================================================

    always @(posedge clk) begin

        if (rst_n && sample_en)
            ram_read_q <= delay_mem[write_ptr];

        if (rst_n && stage2_valid)
            delay_mem[write_addr_q] <=
                buffer_write_data;

    end

    // =====================================================
    // 9. Main controller
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            write_ptr <= {ADDR_BITS{1'b0}};
            write_addr_q <= {ADDR_BITS{1'b0}};

            fill_count <= {(ADDR_BITS+1){1'b0}};
            tap_valid_q <= 1'b0;

            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;

            dry_q <= 16'sd0;
            wet_q <= 8'd0;
            wet_gain <= 8'd0;

            wet_product_q <= 25'sd0;
            feedback_q <= 17'sd0;

            pcm_out <= 16'sd0;

        end
        else begin

            stage1_valid <= sample_en;
            stage2_valid <= stage1_valid;

            // ---------------------------------------------
            // Stage 0: capture one audio frame
            // ---------------------------------------------

            if (sample_en) begin

                dry_q <= dry_pcm;
                wet_q <= wet_gain;

                write_addr_q <= write_ptr;
                write_ptr <= write_ptr + 1'b1;

                tap_valid_q <= fill_count[ADDR_BITS];

                if (!fill_count[ADDR_BITS])
                    fill_count <= fill_count + 1'b1;

                // Smooth wet gain toward target.
                if (wet_gain < wet_target)
                    wet_gain <= wet_gain + 1'b1;
                else if (wet_gain > wet_target)
                    wet_gain <= wet_gain - 1'b1;

            end

            // ---------------------------------------------
            // Stage 1: calculate wet and feedback
            // ---------------------------------------------

            if (stage1_valid) begin

                wet_product_q <= wet_product;
                feedback_q <= feedback_next;

            end

            // ---------------------------------------------
            // Stage 2: publish output sample
            //
            // Block RAM write occurs in the separate
            // synchronous RAM process above.
            // ---------------------------------------------

            if (stage2_valid) begin

                pcm_out <= sat16(output_sum);

            end

        end

    end

endmodule