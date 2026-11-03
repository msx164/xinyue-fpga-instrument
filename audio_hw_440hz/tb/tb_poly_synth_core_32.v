`timescale 1ns/1ps

module tb_poly_synth_core_32;

    // ============================================================
    // Clock / reset
    // ============================================================

    reg clk;
    reg rst_n;


    // ============================================================
    // Audio sample request
    // ============================================================

    reg sample_en;


    // ============================================================
    // Note Event
    // ============================================================

    reg        event_valid;
    reg        event_on;

    reg [6:0]  event_note;
    reg [31:0] event_fcw;


    // ============================================================
    // DUT outputs
    // ============================================================

    wire signed [15:0] mix_pcm;

    wire [31:0] gate_mask;
    wire [31:0] assigned_mask;
    wire [31:0] active_mask;

    wire alloc_fail_pulse;
    wire engine_busy;


    // ============================================================
    // Test variables
    // ============================================================

    integer error_count;

    integer test_i;

    integer file_8;
    integer file_16;
    integer file_32;


    // ============================================================
    // DUT
    //
    // Use fast ADSR parameters for simulation.
    // ============================================================

    poly_synth_core_32 #(
        .ATTACK_STEP   (15'd8192),
        .DECAY_STEP    (15'd4096),
        .SUSTAIN_LEVEL (15'd16384),
        .RELEASE_STEP  (15'd4096),

        // Final 32-Voice headroom:
        // every Voice approximately 1/32 full scale.
        .OUTPUT_SHIFT  (5)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),

        .sample_en        (sample_en),

        .event_valid      (event_valid),
        .event_on         (event_on),

        .event_note       (event_note),
        .event_fcw        (event_fcw),

        .mix_pcm          (mix_pcm),

        .gate_mask        (gate_mask),
        .assigned_mask    (assigned_mask),
        .active_mask      (active_mask),

        .alloc_fail_pulse (alloc_fail_pulse),
        .engine_busy      (engine_busy)
    );


    // ============================================================
    // 48 MHz system clock
    // ============================================================

    initial begin

        clk = 1'b0;

        forever #10.416667
            clk = ~clk;

    end


    // ============================================================
    // MIDI Note -> DDS FCW lookup
    //
    // Fs = 48 kHz
    // DDS phase accumulator = 32 bit
    //
    // FCW =
    //
    // round(
    //     frequency *
    //     2^32 /
    //     48000
    // )
    //
    // Notes 48 ~ 79
    // ============================================================

    function [31:0] midi_fcw;

        input [6:0] note;

        begin

            case (note)

                7'd48: midi_fcw = 32'h00B29A62;
                7'd49: midi_fcw = 32'h00BD392D;
                7'd50: midi_fcw = 32'h00C879A3;
                7'd51: midi_fcw = 32'h00D46562;

                7'd52: midi_fcw = 32'h00E10697;
                7'd53: midi_fcw = 32'h00EE680F;
                7'd54: midi_fcw = 32'h00FC9536;
                7'd55: midi_fcw = 32'h010B9A2B;

                7'd56: midi_fcw = 32'h011B83C2;
                7'd57: midi_fcw = 32'h012C5F93;
                7'd58: midi_fcw = 32'h013E3C06;
                7'd59: midi_fcw = 32'h0151285D;

                7'd60: midi_fcw = 32'h016534C3;
                7'd61: midi_fcw = 32'h017A725A;
                7'd62: midi_fcw = 32'h0190F347;
                7'd63: midi_fcw = 32'h01A8CAC3;

                7'd64: midi_fcw = 32'h01C20D2F;
                7'd65: midi_fcw = 32'h01DCD01D;
                7'd66: midi_fcw = 32'h01F92A6D;
                7'd67: midi_fcw = 32'h02173456;

                7'd68: midi_fcw = 32'h02370783;
                7'd69: midi_fcw = 32'h0258BF26;
                7'd70: midi_fcw = 32'h027C780B;
                7'd71: midi_fcw = 32'h02A250BA;

                7'd72: midi_fcw = 32'h02CA6987;
                7'd73: midi_fcw = 32'h02F4E4B4;
                7'd74: midi_fcw = 32'h0321E68D;
                7'd75: midi_fcw = 32'h03519586;

                7'd76: midi_fcw = 32'h03841A5D;
                7'd77: midi_fcw = 32'h03B9A03A;
                7'd78: midi_fcw = 32'h03F254D9;
                7'd79: midi_fcw = 32'h042E68AC;

                default:
                    midi_fcw = 32'd0;

            endcase

        end

    endfunction


    // ============================================================
    // Reset DUT
    // ============================================================

    task reset_dut;

        begin

            rst_n =
                1'b0;

            sample_en =
                1'b0;

            event_valid =
                1'b0;

            event_on =
                1'b0;

            event_note =
                7'd0;

            event_fcw =
                32'd0;


            repeat (5)
                @(posedge clk);


            rst_n =
                1'b1;


            repeat (5)
                @(posedge clk);

        end

    endtask


    // ============================================================
    // Send one Note Event
    // ============================================================

    task send_event;

        input        note_on;
        input [6:0]  note;
        input [31:0] fcw;

        begin

            @(negedge clk);

            event_on =
                note_on;

            event_note =
                note;

            event_fcw =
                fcw;

            event_valid =
                1'b1;


            @(negedge clk);

            event_valid =
                1'b0;


            @(posedge clk);

        end

    endtask


    // ============================================================
    // Generate one audio sample
    //
    // The real FPGA receives one sample_en every 20.833 us.
    //
    // In simulation we trigger the calculation manually and wait
    // for all 32 Voices to finish.
    // ============================================================

    task generate_sample;

        begin

            @(negedge clk);

            sample_en =
                1'b1;


            @(negedge clk);

            sample_en =
                1'b0;


            // Wait until TDM engine starts.
            wait (
                engine_busy ==
                1'b1
            );


            // Wait until all 32 Voices finish.
            wait (
                engine_busy ==
                1'b0
            );

        end

    endtask


    // ============================================================
    // Capture PCM samples
    // ============================================================

    task capture_pcm;

        input integer file_handle;
        input integer sample_total;

        integer capture_i;

        begin

            for (
                capture_i = 0;
                capture_i < sample_total;
                capture_i = capture_i + 1
            ) begin

                generate_sample;


                $fwrite(
                    file_handle,
                    "%0d\n",
                    $signed(mix_pcm)
                );

            end

        end

    endtask


    // ============================================================
    // Allocate N consecutive MIDI Notes
    //
    // MIDI 48 is always the first note.
    // ============================================================

    task allocate_notes;

        input integer voice_count;

        integer alloc_i;

        begin

            for (
                alloc_i = 0;
                alloc_i < voice_count;
                alloc_i = alloc_i + 1
            ) begin

                send_event(
                    1'b1,

                    7'd48 +
                    alloc_i,

                    midi_fcw(
                        7'd48 +
                        alloc_i
                    )
                );

            end

        end

    endtask


    // ============================================================
    // Main test
    // ============================================================

    initial begin

        error_count =
            0;


        // ========================================================
        // TEST 1
        //
        // 8 Voices
        // ========================================================

        $display("");
        $display(
            "================================"
        );

        $display(
            "TEST 1: 8 VOICES"
        );

        $display(
            "================================"
        );


        reset_dut;


        allocate_notes(
            8
        );


        if (
            assigned_mask !==
            32'h000000FF
        ) begin

            $display(
                "8 VOICE ASSIGNED MASK FAIL: %h",
                assigned_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "8 VOICE ASSIGNED MASK PASS"
            );

        end


        if (
            gate_mask !==
            32'h000000FF
        ) begin

            $display(
                "8 VOICE GATE MASK FAIL: %h",
                gate_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "8 VOICE GATE MASK PASS"
            );

        end


        // Fast ADSR settling.
        repeat (20)
            generate_sample;


        if (
            active_mask[7:0] !==
            8'hFF
        ) begin

            $display(
                "8 VOICE ACTIVE MASK FAIL: %h",
                active_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "8 VOICE ACTIVE MASK PASS"
            );

        end


        file_8 =
            $fopen(
                "poly32_8voice_pcm.txt",
                "w"
            );


        capture_pcm(
            file_8,
            48000
        );


        $fclose(
            file_8
        );


        $display(
            "8 VOICE PCM CAPTURE PASS"
        );


        // ========================================================
        // TEST 2
        //
        // 16 Voices
        // ========================================================

        $display("");
        $display(
            "================================"
        );

        $display(
            "TEST 2: 16 VOICES"
        );

        $display(
            "================================"
        );


        reset_dut;


        allocate_notes(
            16
        );


        if (
            assigned_mask !==
            32'h0000FFFF
        ) begin

            $display(
                "16 VOICE ASSIGNED MASK FAIL: %h",
                assigned_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "16 VOICE ASSIGNED MASK PASS"
            );

        end


        if (
            gate_mask !==
            32'h0000FFFF
        ) begin

            $display(
                "16 VOICE GATE MASK FAIL: %h",
                gate_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "16 VOICE GATE MASK PASS"
            );

        end


        repeat (20)
            generate_sample;


        if (
            active_mask[15:0] !==
            16'hFFFF
        ) begin

            $display(
                "16 VOICE ACTIVE MASK FAIL: %h",
                active_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "16 VOICE ACTIVE MASK PASS"
            );

        end


        file_16 =
            $fopen(
                "poly32_16voice_pcm.txt",
                "w"
            );


        capture_pcm(
            file_16,
            48000
        );


        $fclose(
            file_16
        );


        $display(
            "16 VOICE PCM CAPTURE PASS"
        );


        // ========================================================
        // TEST 3
        //
        // Full 32 Voices
        // ========================================================

        $display("");
        $display(
            "================================"
        );

        $display(
            "TEST 3: 32 VOICES"
        );

        $display(
            "================================"
        );


        reset_dut;


        allocate_notes(
            32
        );


        if (
            assigned_mask !==
            32'hFFFFFFFF
        ) begin

            $display(
                "32 VOICE ASSIGNED MASK FAIL: %h",
                assigned_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "32 VOICE ASSIGNED MASK PASS"
            );

        end


        if (
            gate_mask !==
            32'hFFFFFFFF
        ) begin

            $display(
                "32 VOICE GATE MASK FAIL: %h",
                gate_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "32 VOICE GATE MASK PASS"
            );

        end


        repeat (20)
            generate_sample;


        if (
            active_mask !==
            32'hFFFFFFFF
        ) begin

            $display(
                "32 VOICE ACTIVE MASK FAIL: %h",
                active_mask
            );

            error_count =
                error_count + 1;

        end
        else begin

            $display(
                "32 VOICE ACTIVE MASK PASS"
            );

        end


        file_32 =
            $fopen(
                "poly32_32voice_pcm.txt",
                "w"
            );


        capture_pcm(
            file_32,
            48000
        );


        $fclose(
            file_32
        );


        $display(
            "32 VOICE PCM CAPTURE PASS"
        );


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


        if (
            error_count ==
            0
        ) begin

            $display(
                "POLY SYNTH CORE 32 RTL TEST PASS"
            );

        end
        else begin

            $display(
                "POLY SYNTH CORE 32 RTL TEST FAIL"
            );

        end


        $display(
            "================================"
        );


        $stop;

    end

endmodule