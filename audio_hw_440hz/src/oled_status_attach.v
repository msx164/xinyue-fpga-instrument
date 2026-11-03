`timescale 1ns/1ps

module oled_status_attach (
    input wire clk,
    input wire rst_n,

    input wire event_valid,
    input wire event_on,
    input wire [6:0] event_note,

    input wire timbre_sel,
    input wire [31:0] active_mask,

    inout wire oled_scl,
    inout wire oled_sda
);

    // ==================================================
    // 1. Last played note
    // ==================================================

    reg [6:0] last_note;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n)
            last_note <= 7'd60;

        else if (event_valid && event_on)
            last_note <= event_note;

    end

    // ==================================================
    // 2. Population count for four active bits
    // ==================================================

    function [2:0] popcount4;
        input [3:0] bits;
        begin
            popcount4 =
                {2'b00, bits[0]} +
                {2'b00, bits[1]} +
                {2'b00, bits[2]} +
                {2'b00, bits[3]};
        end
    endfunction

    // ==================================================
    // 3. Count all 32 active voices
    // ==================================================

    wire [5:0] active_count =
        {3'd0, popcount4(active_mask[3:0])}   +
        {3'd0, popcount4(active_mask[7:4])}   +
        {3'd0, popcount4(active_mask[11:8])}  +
        {3'd0, popcount4(active_mask[15:12])} +
        {3'd0, popcount4(active_mask[19:16])} +
        {3'd0, popcount4(active_mask[23:20])} +
        {3'd0, popcount4(active_mask[27:24])} +
        {3'd0, popcount4(active_mask[31:28])};

    // ==================================================
    // 4. Independent SSD1306 display
    // ==================================================

    ssd1306_status_i2c #(
        .CLK_HZ(48000000),
        .I2C_HZ(100000)
    ) u_ssd1306 (
        .clk           (clk),
        .rst_n         (rst_n),

        .current_note  (last_note),
        .timbre_sel    (timbre_sel),
        .active_voices (active_count),

        .oled_scl      (oled_scl),
        .oled_sda      (oled_sda)
    );

endmodule