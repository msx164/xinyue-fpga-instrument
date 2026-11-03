`timescale 1ns/1ps

module ssd1306_status_i2c #(
    parameter integer CLK_HZ = 48000000,
    parameter integer I2C_HZ = 100000
)(
    input  wire clk,
    input  wire rst_n,

    input  wire [6:0] current_note,
    input  wire       timbre_sel,
    input  wire [5:0] active_voices,

    inout  wire oled_scl,
    inout  wire oled_sda
);

    // ====================================================
    // SSD1306 128x64, I2C address 0x3C
    //
    // Display:
    // PAGE 0: SOUND DOMAIN
    // PAGE 2: NOTE: C4
    // PAGE 4: TIMBRE: SINE / TRIANGLE
    // PAGE 6: VOICES: 04
    //
    // Open-drain I2C outputs.
    // Does not access existing ADS1115 bus.
    // ====================================================

    localparam integer DIV_RAW =
        CLK_HZ / (I2C_HZ * 3);

    localparam integer TICK_DIV =
        (DIV_RAW < 2) ? 2 : DIV_RAW;

    localparam integer POWER_WAIT =
        CLK_HZ / 10;

    localparam integer REFRESH_WAIT =
        CLK_HZ / 20;

    // ----------------------------------------------------
    // I2C open-drain pins
    // ----------------------------------------------------

    reg scl_low;
    reg sda_low;

    assign oled_scl = scl_low ? 1'b0 : 1'bz;
    assign oled_sda = sda_low ? 1'b0 : 1'bz;

    // ----------------------------------------------------
    // Bit timing
    // ----------------------------------------------------

    reg [31:0] div_count;

    wire bit_tick =
        (div_count == TICK_DIV - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            div_count <= 32'd0;
        else if (bit_tick)
            div_count <= 32'd0;
        else
            div_count <= div_count + 1'b1;
    end

    // ====================================================
    // Font: 5x7, column-oriented
    // Bit 0 is top pixel.
    // ====================================================

    function [39:0] font5;
        input [7:0] ch;
        begin
            case (ch)

                "A": font5 = {
                    8'h7E,8'h11,8'h11,8'h11,8'h7E
                };

                "B": font5 = {
                    8'h36,8'h49,8'h49,8'h49,8'h7F
                };

                "C": font5 = {
                    8'h22,8'h41,8'h41,8'h41,8'h3E
                };

                "D": font5 = {
                    8'h1C,8'h22,8'h41,8'h41,8'h7F
                };

                "E": font5 = {
                    8'h41,8'h49,8'h49,8'h49,8'h7F
                };

                "F": font5 = {
                    8'h01,8'h09,8'h09,8'h09,8'h7F
                };

                "G": font5 = {
                    8'h7A,8'h49,8'h49,8'h41,8'h3E
                };

                "I": font5 = {
                    8'h00,8'h41,8'h7F,8'h41,8'h00
                };

                "L": font5 = {
                    8'h40,8'h40,8'h40,8'h40,8'h7F
                };

                "M": font5 = {
                    8'h7F,8'h02,8'h0C,8'h02,8'h7F
                };

                "N": font5 = {
                    8'h7F,8'h10,8'h08,8'h04,8'h7F
                };

                "O": font5 = {
                    8'h3E,8'h41,8'h41,8'h41,8'h3E
                };

                "R": font5 = {
                    8'h46,8'h29,8'h19,8'h09,8'h7F
                };

                "S": font5 = {
                    8'h31,8'h49,8'h49,8'h49,8'h46
                };

                "T": font5 = {
                    8'h01,8'h01,8'h7F,8'h01,8'h01
                };

                "U": font5 = {
                    8'h3F,8'h40,8'h40,8'h40,8'h3F
                };

                "V": font5 = {
                    8'h1F,8'h20,8'h40,8'h20,8'h1F
                };

                "0": font5 = {
                    8'h3E,8'h51,8'h49,8'h45,8'h3E
                };

                "1": font5 = {
                    8'h00,8'h40,8'h7F,8'h42,8'h00
                };

                "2": font5 = {
                    8'h46,8'h49,8'h51,8'h61,8'h42
                };

                "3": font5 = {
                    8'h36,8'h49,8'h49,8'h41,8'h21
                };

                "4": font5 = {
                    8'h10,8'h7F,8'h12,8'h14,8'h18
                };

                "5": font5 = {
                    8'h39,8'h45,8'h45,8'h45,8'h27
                };

                "6": font5 = {
                    8'h32,8'h49,8'h49,8'h49,8'h3E
                };

                "7": font5 = {
                    8'h07,8'h09,8'h71,8'h01,8'h01
                };

                "8": font5 = {
                    8'h36,8'h49,8'h49,8'h49,8'h36
                };

                "9": font5 = {
                    8'h3E,8'h49,8'h49,8'h49,8'h26
                };

                ":": font5 = {
                    8'h00,8'h00,8'h36,8'h36,8'h00
                };

                "#": font5 = {
                    8'h14,8'h7F,8'h14,8'h7F,8'h14
                };

                "-": font5 = {
                    8'h08,8'h08,8'h08,8'h08,8'h08
                };

                default: font5 = 40'd0;

            endcase
        end
    endfunction

    // ====================================================
    // Character selection
    // ====================================================

    function [7:0] text_char;

        input [2:0] page;
        input [3:0] index;
        input [6:0] midi_note;
        input       timbre;
        input [5:0] voices;

        reg [6:0] semitone;
        reg [7:0] octave_char;
        reg [7:0] note_char;
        reg [7:0] sharp_char;

        reg [5:0] units;
        reg [7:0] tens_char;

        begin

            // --------------------------------------------
            // MIDI note -> note name and octave
            // MIDI 60 = C4
            // --------------------------------------------

            if (midi_note >= 7'd120) begin
                semitone = midi_note - 7'd120;
                octave_char = "9";
            end
            else if (midi_note >= 7'd108) begin
                semitone = midi_note - 7'd108;
                octave_char = "8";
            end
            else if (midi_note >= 7'd96) begin
                semitone = midi_note - 7'd96;
                octave_char = "7";
            end
            else if (midi_note >= 7'd84) begin
                semitone = midi_note - 7'd84;
                octave_char = "6";
            end
            else if (midi_note >= 7'd72) begin
                semitone = midi_note - 7'd72;
                octave_char = "5";
            end
            else if (midi_note >= 7'd60) begin
                semitone = midi_note - 7'd60;
                octave_char = "4";
            end
            else if (midi_note >= 7'd48) begin
                semitone = midi_note - 7'd48;
                octave_char = "3";
            end
            else if (midi_note >= 7'd36) begin
                semitone = midi_note - 7'd36;
                octave_char = "2";
            end
            else if (midi_note >= 7'd24) begin
                semitone = midi_note - 7'd24;
                octave_char = "1";
            end
            else if (midi_note >= 7'd12) begin
                semitone = midi_note - 7'd12;
                octave_char = "0";
            end
            else begin
                semitone = midi_note;
                octave_char = "-";
            end

            note_char = "C";
            sharp_char = " ";

            case (semitone)
                7'd0 : note_char = "C";

                7'd1 : begin
                    note_char = "C";
                    sharp_char = "#";
                end

                7'd2 : note_char = "D";

                7'd3 : begin
                    note_char = "D";
                    sharp_char = "#";
                end

                7'd4 : note_char = "E";
                7'd5 : note_char = "F";

                7'd6 : begin
                    note_char = "F";
                    sharp_char = "#";
                end

                7'd7 : note_char = "G";

                7'd8 : begin
                    note_char = "G";
                    sharp_char = "#";
                end

                7'd9 : note_char = "A";

                7'd10: begin
                    note_char = "A";
                    sharp_char = "#";
                end

                7'd11: note_char = "B";

                default: note_char = "C";
            endcase

            // --------------------------------------------
            // Voice count -> decimal
            // --------------------------------------------

            if (voices >= 6'd60) begin
                tens_char = "6";
                units = voices - 6'd60;
            end
            else if (voices >= 6'd50) begin
                tens_char = "5";
                units = voices - 6'd50;
            end
            else if (voices >= 6'd40) begin
                tens_char = "4";
                units = voices - 6'd40;
            end
            else if (voices >= 6'd30) begin
                tens_char = "3";
                units = voices - 6'd30;
            end
            else if (voices >= 6'd20) begin
                tens_char = "2";
                units = voices - 6'd20;
            end
            else if (voices >= 6'd10) begin
                tens_char = "1";
                units = voices - 6'd10;
            end
            else begin
                tens_char = "0";
                units = voices;
            end

            text_char = " ";

            // --------------------------------------------
            // Page 0: SOUND DOMAIN
            // --------------------------------------------

            if (page == 3'd0) begin
                case (index)
                    4'd0 : text_char = "S";
                    4'd1 : text_char = "O";
                    4'd2 : text_char = "U";
                    4'd3 : text_char = "N";
                    4'd4 : text_char = "D";
                    4'd6 : text_char = "D";
                    4'd7 : text_char = "O";
                    4'd8 : text_char = "M";
                    4'd9 : text_char = "A";
                    4'd10: text_char = "I";
                    4'd11: text_char = "N";
                    default: text_char = " ";
                endcase
            end

            // --------------------------------------------
            // Page 2: NOTE: C4
            // --------------------------------------------

            else if (page == 3'd2) begin
                case (index)
                    4'd0: text_char = "N";
                    4'd1: text_char = "O";
                    4'd2: text_char = "T";
                    4'd3: text_char = "E";
                    4'd4: text_char = ":";
                    4'd6: text_char = note_char;
                    4'd7: text_char = sharp_char;
                    4'd8: text_char = octave_char;
                    default: text_char = " ";
                endcase
            end

            // --------------------------------------------
            // Page 4: TIMBRE: SINE / TRIANGLE
            // --------------------------------------------

            else if (page == 3'd4) begin
                case (index)
                    4'd0: text_char = "T";
                    4'd1: text_char = "I";
                    4'd2: text_char = "M";
                    4'd3: text_char = "B";
                    4'd4: text_char = "R";
                    4'd5: text_char = "E";
                    4'd6: text_char = ":";

                    4'd8: text_char = "T";

                    default: text_char = " ";
                endcase

                if (!timbre) begin
                    case (index)
                        4'd8 : text_char = "S";
                        4'd9 : text_char = "I";
                        4'd10: text_char = "N";
                        4'd11: text_char = "E";
                        default: begin end
                    endcase
                end
                else begin
                    case (index)
                        4'd8 : text_char = "T";
                        4'd9 : text_char = "R";
                        4'd10: text_char = "I";
                        4'd11: text_char = "A";
                        4'd12: text_char = "N";
                        4'd13: text_char = "G";
                        4'd14: text_char = "L";
                        4'd15: text_char = "E";
                        default: begin end
                    endcase
                end
            end

            // --------------------------------------------
            // Page 6: VOICES: 04
            // --------------------------------------------

            else if (page == 3'd6) begin
                case (index)
                    4'd0: text_char = "V";
                    4'd1: text_char = "O";
                    4'd2: text_char = "I";
                    4'd3: text_char = "C";
                    4'd4: text_char = "E";
                    4'd5: text_char = "S";
                    4'd6: text_char = ":";
                    4'd8: text_char = tens_char;
                    4'd9: text_char = 8'h30 + {2'b00, units};
                    default: text_char = " ";
                endcase
            end

        end

    endfunction

    // ====================================================
    // Pixel byte generator
    // Every character occupies 8 columns.
    // Actual font uses the first 5 columns.
    // ====================================================

    function [7:0] pixel_byte;

        input [2:0] page;
        input [6:0] column;
        input [6:0] note;
        input       timbre;
        input [5:0] voices;

        reg [7:0] character;
        reg [39:0] glyph;

        begin
            character = text_char(
                page,
                column[6:3],
                note,
                timbre,
                voices
            );

            glyph = font5(character);

            case (column[2:0])
                3'd0: pixel_byte = glyph[7:0];
                3'd1: pixel_byte = glyph[15:8];
                3'd2: pixel_byte = glyph[23:16];
                3'd3: pixel_byte = glyph[31:24];
                3'd4: pixel_byte = glyph[39:32];
                default: pixel_byte = 8'h00;
            endcase
        end
    endfunction

    // ====================================================
    // SSD1306 initialization commands
    // Page addressing mode.
    // ====================================================

    function [7:0] init_command;
        input [4:0] index;
        begin
            case (index)

                5'd0 : init_command = 8'hAE;
                5'd1 : init_command = 8'hD5;
                5'd2 : init_command = 8'h80;
                5'd3 : init_command = 8'hA8;
                5'd4 : init_command = 8'h3F;
                5'd5 : init_command = 8'hD3;
                5'd6 : init_command = 8'h00;
                5'd7 : init_command = 8'h40;
                5'd8 : init_command = 8'h8D;
                5'd9 : init_command = 8'h14;
                5'd10: init_command = 8'h20;
                5'd11: init_command = 8'h02;
                5'd12: init_command = 8'hA1;
                5'd13: init_command = 8'hC8;
                5'd14: init_command = 8'hDA;
                5'd15: init_command = 8'h12;
                5'd16: init_command = 8'h81;
                5'd17: init_command = 8'h7F;
                5'd18: init_command = 8'hD9;
                5'd19: init_command = 8'hF1;
                5'd20: init_command = 8'hDB;
                5'd21: init_command = 8'h40;
                5'd22: init_command = 8'hA4;
                5'd23: init_command = 8'hA6;
                5'd24: init_command = 8'h2E;
                5'd25: init_command = 8'hAF;

                default: init_command = 8'hAE;

            endcase
        end
    endfunction

    // ====================================================
    // I2C transaction engine
    //
    // Transaction type 0:
    // START 0x78 0x00 COMMAND STOP
    //
    // Transaction type 1:
    // START 0x78 0x40 DATA[0..127] STOP
    //
    // 0x78 = 7-bit address 0x3C + write bit.
    //
    // ACK clock slots are generated.
    // This minimal version does not abort on NACK.
    // ====================================================

    localparam [3:0]
        I_IDLE       = 4'd0,
        I_START      = 4'd1,
        I_BIT_LOW    = 4'd2,
        I_BIT_HIGH   = 4'd3,
        I_BIT_END    = 4'd4,
        I_ACK_LOW    = 4'd5,
        I_ACK_HIGH   = 4'd6,
        I_ACK_END    = 4'd7,
        I_STOP_LOW   = 4'd8,
        I_STOP_HIGH  = 4'd9,
        I_STOP_FREE  = 4'd10,
        I_FINISH     = 4'd11;

    reg [3:0] i_state;

    reg [7:0] shift_byte;
    reg [7:0] byte_number;
    reg [2:0] bit_number;

    reg mode_q;
    reg [7:0] command_q;
    reg [2:0] page_q;

    reg [6:0] note_q;
    reg       timbre_q;
    reg [5:0] voices_q;

    reg tx_done;

    reg tx_go;
    reg tx_mode;
    reg [7:0] tx_command;
    reg [2:0] tx_page;

    wire [7:0] next_byte =
        (byte_number == 8'd0) ?
            (mode_q ? 8'h40 : 8'h00) :
        (byte_number == 8'd1) ?
            (mode_q ?
                pixel_byte(
                    page_q,
                    7'd0,
                    note_q,
                    timbre_q,
                    voices_q
                ) :
                command_q) :
            pixel_byte(
                page_q,
                byte_number[6:0] - 7'd1,
                note_q,
                timbre_q,
                voices_q
            );

    wire last_byte =
        mode_q ?
        (byte_number == 8'd129) :
        (byte_number == 8'd2);

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            i_state <= I_IDLE;

            scl_low <= 1'b0;
            sda_low <= 1'b0;

            shift_byte <= 8'd0;
            byte_number <= 8'd0;
            bit_number <= 3'd7;

            mode_q <= 1'b0;
            command_q <= 8'd0;
            page_q <= 3'd0;

            note_q <= 7'd60;
            timbre_q <= 1'b0;
            voices_q <= 6'd0;

            tx_done <= 1'b0;

        end
        else begin

            tx_done <= 1'b0;

            if (i_state == I_IDLE) begin

                scl_low <= 1'b0;
                sda_low <= 1'b0;

                if (tx_go) begin

                    mode_q <= tx_mode;
                    command_q <= tx_command;
                    page_q <= tx_page;

                    note_q <= current_note;
                    timbre_q <= timbre_sel;
                    voices_q <= active_voices;

                    shift_byte <= 8'h78;
                    byte_number <= 8'd0;
                    bit_number <= 3'd7;

                    scl_low <= 1'b0;
                    sda_low <= 1'b1;

                    i_state <= I_START;
                end

            end

            else if (bit_tick) begin

                case (i_state)

                    I_START: begin
                        scl_low <= 1'b0;
                        sda_low <= 1'b1;
                        i_state <= I_BIT_LOW;
                    end

                    I_BIT_LOW: begin

                        scl_low <= 1'b1;

                        // 1 = release SDA
                        // 0 = pull SDA low
                        sda_low <=
                            ~shift_byte[bit_number];

                        i_state <= I_BIT_HIGH;

                    end

                    I_BIT_HIGH: begin
                        scl_low <= 1'b0;
                        i_state <= I_BIT_END;
                    end

                    I_BIT_END: begin

                        if (bit_number == 3'd0) begin
                            i_state <= I_ACK_LOW;
                        end
                        else begin
                            bit_number <= bit_number - 1'b1;
                            i_state <= I_BIT_LOW;
                        end

                    end

                    I_ACK_LOW: begin

                        scl_low <= 1'b1;
                        sda_low <= 1'b0;

                        i_state <= I_ACK_HIGH;

                    end

                    I_ACK_HIGH: begin

                        scl_low <= 1'b0;
                        i_state <= I_ACK_END;

                    end

                    I_ACK_END: begin

                        scl_low <= 1'b1;

                        if (last_byte) begin
                            i_state <= I_STOP_LOW;
                        end
                        else begin

                            byte_number <=
                                byte_number + 1'b1;

                            shift_byte <= next_byte;
                            bit_number <= 3'd7;

                            i_state <= I_BIT_LOW;

                        end

                    end

                    I_STOP_LOW: begin

                        scl_low <= 1'b1;
                        sda_low <= 1'b1;

                        i_state <= I_STOP_HIGH;

                    end

                    I_STOP_HIGH: begin

                        scl_low <= 1'b0;
                        sda_low <= 1'b1;

                        i_state <= I_STOP_FREE;

                    end

                    I_STOP_FREE: begin

                        scl_low <= 1'b0;
                        sda_low <= 1'b0;

                        i_state <= I_FINISH;

                    end

                    I_FINISH: begin

                        tx_done <= 1'b1;
                        i_state <= I_IDLE;

                    end

                    default: begin

                        i_state <= I_IDLE;
                        scl_low <= 1'b0;
                        sda_low <= 1'b0;

                    end

                endcase

            end

        end

    end

    // ====================================================
    // OLED frame controller
    //
    // 1. Power-on wait
    // 2. SSD1306 initialization
    // 3. For each of eight pages:
    //      page address
    //      low column address
    //      high column address
    //      128 display bytes
    // 4. Periodic refresh
    //
    // Runs independently of audio frame generation.
    // ====================================================

    localparam [2:0]
        C_POWER  = 3'd0,
        C_INIT   = 3'd1,
        C_PAGE   = 3'd2,
        C_COL_LO = 3'd3,
        C_COL_HI = 3'd4,
        C_DATA   = 3'd5,
        C_WAIT   = 3'd6;

    reg [2:0] controller_state;

    reg [31:0] wait_counter;
    reg [4:0] init_index;
    reg [2:0] display_page;

    reg pending;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            controller_state <= C_POWER;

            wait_counter <= 32'd0;
            init_index <= 5'd0;
            display_page <= 3'd0;

            pending <= 1'b0;

            tx_go <= 1'b0;
            tx_mode <= 1'b0;
            tx_command <= 8'd0;
            tx_page <= 3'd0;

        end
        else begin

            tx_go <= 1'b0;

            case (controller_state)

                // ----------------------------------------
                // Power-on settling
                // ----------------------------------------

                C_POWER: begin

                    if (wait_counter >= POWER_WAIT - 1) begin

                        wait_counter <= 32'd0;
                        controller_state <= C_INIT;

                    end
                    else
                        wait_counter <= wait_counter + 1'b1;

                end

                // ----------------------------------------
                // Send SSD1306 init commands
                // ----------------------------------------

                C_INIT: begin

                    if (!pending) begin

                        tx_mode <= 1'b0;
                        tx_command <=
                            init_command(init_index);

                        tx_page <= 3'd0;
                        tx_go <= 1'b1;
                        pending <= 1'b1;

                    end
                    else if (tx_done) begin

                        pending <= 1'b0;

                        if (init_index == 5'd25) begin

                            init_index <= 5'd0;
                            display_page <= 3'd0;

                            controller_state <= C_PAGE;

                        end
                        else begin

                            init_index <= init_index + 1'b1;

                        end

                    end

                end

                // ----------------------------------------
                // Set page address (0xB0..0xB7)
                // ----------------------------------------

                C_PAGE: begin

                    if (!pending) begin

                        tx_mode <= 1'b0;

                        tx_command <=
                            8'hB0 | {5'd0, display_page};

                        tx_go <= 1'b1;
                        pending <= 1'b1;

                    end
                    else if (tx_done) begin

                        pending <= 1'b0;
                        controller_state <= C_COL_LO;

                    end

                end

                // ----------------------------------------
                // Set lower column = 0
                // ----------------------------------------

                C_COL_LO: begin

                    if (!pending) begin

                        tx_mode <= 1'b0;
                        tx_command <= 8'h00;

                        tx_go <= 1'b1;
                        pending <= 1'b1;

                    end
                    else if (tx_done) begin

                        pending <= 1'b0;
                        controller_state <= C_COL_HI;

                    end

                end

                // ----------------------------------------
                // Set higher column = 0
                // ----------------------------------------

                C_COL_HI: begin

                    if (!pending) begin

                        tx_mode <= 1'b0;
                        tx_command <= 8'h10;

                        tx_go <= 1'b1;
                        pending <= 1'b1;

                    end
                    else if (tx_done) begin

                        pending <= 1'b0;
                        controller_state <= C_DATA;

                    end

                end

                // ----------------------------------------
                // Send 128 bytes for one page
                // ----------------------------------------

                C_DATA: begin

                    if (!pending) begin

                        tx_mode <= 1'b1;
                        tx_page <= display_page;

                        tx_go <= 1'b1;
                        pending <= 1'b1;

                    end
                    else if (tx_done) begin

                        pending <= 1'b0;

                        if (display_page == 3'd7) begin

                            display_page <= 3'd0;
                            wait_counter <= 32'd0;

                            controller_state <= C_WAIT;

                        end
                        else begin

                            display_page <=
                                display_page + 1'b1;

                            controller_state <= C_PAGE;

                        end

                    end

                end

                // ----------------------------------------
                // Refresh pause
                // ----------------------------------------

                C_WAIT: begin

                    if (wait_counter >= REFRESH_WAIT - 1) begin

                        wait_counter <= 32'd0;
                        controller_state <= C_PAGE;

                    end
                    else begin

                        wait_counter <= wait_counter + 1'b1;

                    end

                end

                default: begin

                    controller_state <= C_POWER;
                    pending <= 1'b0;
                    wait_counter <= 32'd0;

                end

            endcase

        end

    end

endmodule