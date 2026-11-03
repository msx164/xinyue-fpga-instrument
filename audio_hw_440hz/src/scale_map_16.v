module scale_map_16 (
    input  wire [3:0]  key_index,
    input  wire [1:0]  octave_mode,
    input  wire        scale_mode,

    output reg  [6:0]  midi_note,
    output reg  [31:0] note_fcw
);

    // ============================================================
    // Task 8.5-A
    //
    // 16-Key Scale Mapping
    //
    // scale_mode:
    //   0 = Chromatic
    //   1 = C Major
    //
    // octave_mode:
    //   0 = One octave down
    //   1 = Normal
    //   2 = One octave up
    //
    // Reference:
    //   MIDI 60 = C4
    //   Sample rate = 48000 Hz
    //   DDS phase accumulator = 32 bits
    // ============================================================


    // ============================================================
    // 1. Semitone offset from C4
    // ============================================================

    reg [5:0] note_offset;

    always @(*) begin

        if (scale_mode == 1'b0) begin

            // Chromatic:
            //
            // C4, C#4, D4, ...
            // C5, C#5, D5, D#5

            note_offset = {2'b00, key_index};

        end
        else begin

            // C Major:
            //
            // C4 D4 E4 F4 G4 A4 B4 C5
            // D5 E5 F5 G5 A5 B5 C6 D6

            case (key_index)

                4'd0:  note_offset = 6'd0;
                4'd1:  note_offset = 6'd2;
                4'd2:  note_offset = 6'd4;
                4'd3:  note_offset = 6'd5;

                4'd4:  note_offset = 6'd7;
                4'd5:  note_offset = 6'd9;
                4'd6:  note_offset = 6'd11;
                4'd7:  note_offset = 6'd12;

                4'd8:  note_offset = 6'd14;
                4'd9:  note_offset = 6'd16;
                4'd10: note_offset = 6'd17;
                4'd11: note_offset = 6'd19;

                4'd12: note_offset = 6'd21;
                4'd13: note_offset = 6'd23;
                4'd14: note_offset = 6'd24;
                4'd15: note_offset = 6'd26;

                default:
                    note_offset = 6'd0;

            endcase

        end

    end


    // ============================================================
    // 2. DDS FCW lookup
    //
    // Base octave is C4 and above:
    //
    // MIDI 60 ~ MIDI 86
    //
    // FCW = round(
    //     frequency * 2^32 / 48000
    // )
    //
    // Existing FCW constants are preserved.
    // ============================================================

    reg [31:0] base_fcw;

    always @(*) begin

        case (note_offset)

            // C4 ~ B4
            6'd0:  base_fcw = 32'h016534C3;
            6'd1:  base_fcw = 32'h017A725A;
            6'd2:  base_fcw = 32'h0190F347;
            6'd3:  base_fcw = 32'h01A8CAC3;

            6'd4:  base_fcw = 32'h01C20D2F;
            6'd5:  base_fcw = 32'h01DCD01D;
            6'd6:  base_fcw = 32'h01F92A6D;
            6'd7:  base_fcw = 32'h02173456;

            6'd8:  base_fcw = 32'h02370783;
            6'd9:  base_fcw = 32'h0258BF26;
            6'd10: base_fcw = 32'h027C780B;
            6'd11: base_fcw = 32'h02A250BA;

            // C5 ~ B5
            6'd12: base_fcw = 32'h02CA6987;
            6'd13: base_fcw = 32'h02F4E4B4;
            6'd14: base_fcw = 32'h0321E68D;
            6'd15: base_fcw = 32'h03519586;

            6'd16: base_fcw = 32'h03841A5D;
            6'd17: base_fcw = 32'h03B9A03A;
            6'd18: base_fcw = 32'h03F254D9;
            6'd19: base_fcw = 32'h042E68AC;

            6'd20: base_fcw = 32'h046E0F07;
            6'd21: base_fcw = 32'h04B17E4B;
            6'd22: base_fcw = 32'h04F8F017;
            6'd23: base_fcw = 32'h0544A173;

            // C6 ~ D6
            6'd24: base_fcw = 32'h0594D30D;
            6'd25: base_fcw = 32'h05E9C968;
            6'd26: base_fcw = 32'h0643CD1B;

            default:
                base_fcw = 32'd0;

        endcase

    end


    // ============================================================
    // 3. Octave transposition
    //
    // Down:
    //   MIDI 48 + offset
    //   FCW / 2
    //
    // Normal:
    //   MIDI 60 + offset
    //   FCW unchanged
    //
    // Up:
    //   MIDI 72 + offset
    //   FCW * 2
    //
    // Invalid octave mode falls back to normal.
    // ============================================================

    always @(*) begin

        case (octave_mode)

            2'd0: begin

                midi_note =
                    7'd48 + {1'b0, note_offset};

                note_fcw =
                    base_fcw >> 1;

            end

            2'd1: begin

                midi_note =
                    7'd60 + {1'b0, note_offset};

                note_fcw =
                    base_fcw;

            end

            2'd2: begin

                midi_note =
                    7'd72 + {1'b0, note_offset};

                note_fcw =
                    base_fcw << 1;

            end

            default: begin

                midi_note =
                    7'd60 + {1'b0, note_offset};

                note_fcw =
                    base_fcw;

            end

        endcase

    end

endmodule