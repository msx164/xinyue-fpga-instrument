`timescale 1ns/1ps

module tb_scale_map_16;

    reg  [3:0]  key_index;
    reg  [1:0]  octave_mode;
    reg         scale_mode;

    wire [6:0]  midi_note;
    wire [31:0] note_fcw;

    integer sc;
    integer oct;
    integer k;

    integer offset;
    integer expected_midi;

    reg [31:0] expected_fcw;

    integer passed;


    // ============================================================
    // DUT
    // ============================================================

    scale_map_16 dut (
        .key_index   (key_index),
        .octave_mode (octave_mode),
        .scale_mode  (scale_mode),

        .midi_note   (midi_note),
        .note_fcw    (note_fcw)
    );


    // ============================================================
    // Reference mapping
    // ============================================================

    function integer reference_offset;

        input integer scale;
        input integer key;

        begin

            if (scale == 0) begin

                reference_offset = key;

            end
            else begin

                case (key)

                    0:  reference_offset = 0;
                    1:  reference_offset = 2;
                    2:  reference_offset = 4;
                    3:  reference_offset = 5;

                    4:  reference_offset = 7;
                    5:  reference_offset = 9;
                    6:  reference_offset = 11;
                    7:  reference_offset = 12;

                    8:  reference_offset = 14;
                    9:  reference_offset = 16;
                    10: reference_offset = 17;
                    11: reference_offset = 19;

                    12: reference_offset = 21;
                    13: reference_offset = 23;
                    14: reference_offset = 24;
                    15: reference_offset = 26;

                    default:
                        reference_offset = 0;

                endcase

            end

        end

    endfunction


    // ============================================================
    // Reference FCW table:
    // MIDI60 ~ MIDI86
    // ============================================================

    function [31:0] reference_fcw;

        input integer semitone_offset;

        begin

            case (semitone_offset)

                0:  reference_fcw = 32'h016534C3;
                1:  reference_fcw = 32'h017A725A;
                2:  reference_fcw = 32'h0190F347;
                3:  reference_fcw = 32'h01A8CAC3;

                4:  reference_fcw = 32'h01C20D2F;
                5:  reference_fcw = 32'h01DCD01D;
                6:  reference_fcw = 32'h01F92A6D;
                7:  reference_fcw = 32'h02173456;

                8:  reference_fcw = 32'h02370783;
                9:  reference_fcw = 32'h0258BF26;
                10: reference_fcw = 32'h027C780B;
                11: reference_fcw = 32'h02A250BA;

                12: reference_fcw = 32'h02CA6987;
                13: reference_fcw = 32'h02F4E4B4;
                14: reference_fcw = 32'h0321E68D;
                15: reference_fcw = 32'h03519586;

                16: reference_fcw = 32'h03841A5D;
                17: reference_fcw = 32'h03B9A03A;
                18: reference_fcw = 32'h03F254D9;
                19: reference_fcw = 32'h042E68AC;

                20: reference_fcw = 32'h046E0F07;
                21: reference_fcw = 32'h04B17E4B;
                22: reference_fcw = 32'h04F8F017;
                23: reference_fcw = 32'h0544A173;

                24: reference_fcw = 32'h0594D30D;
                25: reference_fcw = 32'h05E9C968;
                26: reference_fcw = 32'h0643CD1B;

                default:
                    reference_fcw = 32'd0;

            endcase

        end

    endfunction


    // ============================================================
    // Check one mapping
    // ============================================================

    task check_mapping;

        input integer scale;
        input integer octave;
        input integer key;

        begin

            scale_mode  = scale;
            octave_mode = octave;
            key_index   = key;

            #10;

            offset = reference_offset(scale, key);

            case (octave)

                0: expected_midi = 48 + offset;
                1: expected_midi = 60 + offset;
                2: expected_midi = 72 + offset;

                default:
                    expected_midi = 60 + offset;

            endcase

            expected_fcw = reference_fcw(offset);

            case (octave)

                0: expected_fcw = expected_fcw >> 1;
                1: expected_fcw = expected_fcw;
                2: expected_fcw = expected_fcw << 1;

                default:
                    expected_fcw = expected_fcw;

            endcase


            if (
                midi_note !== expected_midi[6:0] ||
                note_fcw  !== expected_fcw
            ) begin

                $display("");
                $display("ERROR: SCALE MAPPING MISMATCH");

                $display(
                    "Scale=%0d Octave=%0d Key=%0d",
                    scale, octave, key + 1
                );

                $display(
                    "Expected: MIDI=%0d FCW=%h",
                    expected_midi, expected_fcw
                );

                $display(
                    "Actual:   MIDI=%0d FCW=%h",
                    midi_note, note_fcw
                );

                $fatal(1);

            end

            passed = passed + 1;

        end

    endtask


    // ============================================================
    // Main test
    // ============================================================

    initial begin

        key_index   = 4'd0;
        octave_mode = 2'd1;
        scale_mode  = 1'b0;

        passed = 0;

        #20;


        // ========================================================
        // Test both scales, all octaves and all 16 keys
        //
        // Total:
        // 2 * 3 * 16 = 96 cases
        // ========================================================

        for (sc = 0; sc < 2; sc = sc + 1) begin

            for (oct = 0; oct < 3; oct = oct + 1) begin

                $display("");
                $display(
                    "TEST: Scale=%0d Octave=%0d",
                    sc, oct
                );

                for (k = 0; k < 16; k = k + 1) begin

                    check_mapping(sc, oct, k);

                end

                $display(
                    "CASE PASS: Scale=%0d Octave=%0d, 16 keys",
                    sc, oct
                );

            end

        end


        // ========================================================
        // Test invalid octave mode:
        // should return to normal octave mapping
        //
        // Scale = C Major
        // Key16 = D6, MIDI86
        // ========================================================

        $display("");
        $display("TEST: Invalid Octave Fallback");

        scale_mode  = 1'b1;
        octave_mode = 2'd3;
        key_index   = 4'd15;

        #10;

        if (
            midi_note !== 7'd86 ||
            note_fcw  !== 32'h0643CD1B
        ) begin

            $display(
                "FAIL: Invalid octave fallback"
            );

            $fatal(1);

        end

        passed = passed + 1;

        $display("CASE PASS: Invalid Octave Fallback");


        // ========================================================
        // Final
        // ========================================================

        $display("");
        $display("==========================================");
        $display("SCALE MAP 16 TEST PASS");
        $display("Total validated mappings: %0d", passed);
        $display("==========================================");

        $finish;

    end

endmodule