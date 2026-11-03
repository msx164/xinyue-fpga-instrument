
module ttp229_reader #(
    parameter integer POWERUP_CYCLES     = 25000000,
    parameter integer SCAN_GAP_CYCLES    = 500000,
    parameter integer HALF_PERIOD_CYCLES = 250
)(
    input  wire        clk,
    input  wire        rst_n,

    output reg         ttp_scl,
    input  wire        ttp_sdo,

    output reg [15:0]  key_state,
    output reg         scan_valid
);

    localparam [1:0] ST_POWERUP = 2'd0;
    localparam [1:0] ST_GAP     = 2'd1;
    localparam [1:0] ST_LOW     = 2'd2;
    localparam [1:0] ST_HIGH    = 2'd3;

    reg [1:0]  state;
    reg [25:0] timer;
    reg [3:0]  bit_index;
    reg [15:0] shift_data;

    reg sdo_meta;
    reg sdo_sync;

    // Input synchronizer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sdo_meta <= 1'b1;
            sdo_sync <= 1'b1;
        end
        else begin
            sdo_meta <= ttp_sdo;
            sdo_sync <= sdo_meta;
        end
    end

    // TTP229 default serial mode:
    // SCL idle HIGH, clock pulses active LOW.
    // Data is sampled after SCL returns HIGH.
    // SDO key bits are active LOW.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_POWERUP;
            timer      <= POWERUP_CYCLES - 1;
            bit_index  <= 4'd0;
            shift_data <= 16'd0;

            ttp_scl    <= 1'b1;
            key_state  <= 16'd0;
            scan_valid <= 1'b0;
        end
        else begin
            scan_valid <= 1'b0;

            case (state)

                ST_POWERUP: begin
                    ttp_scl <= 1'b1;

                    if (timer == 0) begin
                        bit_index  <= 4'd0;
                        shift_data <= 16'd0;
                        timer      <= HALF_PERIOD_CYCLES - 1;
                        ttp_scl    <= 1'b0;
                        state      <= ST_LOW;
                    end
                    else begin
                        timer <= timer - 1'b1;
                    end
                end

                ST_GAP: begin
                    ttp_scl <= 1'b1;

                    if (timer == 0) begin
                        bit_index  <= 4'd0;
                        shift_data <= 16'd0;
                        timer      <= HALF_PERIOD_CYCLES - 1;
                        ttp_scl    <= 1'b0;
                        state      <= ST_LOW;
                    end
                    else begin
                        timer <= timer - 1'b1;
                    end
                end

                ST_LOW: begin
                    ttp_scl <= 1'b0;

                    if (timer == 0) begin
                        ttp_scl <= 1'b1;
                        timer   <= HALF_PERIOD_CYCLES - 1;
                        state   <= ST_HIGH;
                    end
                    else begin
                        timer <= timer - 1'b1;
                    end
                end

                ST_HIGH: begin
                    ttp_scl <= 1'b1;

                    if (timer == 0) begin

                        if (bit_index == 4'd15) begin
                            key_state <= {
                                ~sdo_sync,
                                shift_data[14:0]
                            };

                            scan_valid <= 1'b1;
                            timer      <= SCAN_GAP_CYCLES - 1;
                            state      <= ST_GAP;
                        end
                        else begin
                            shift_data[bit_index] <= ~sdo_sync;
                            bit_index <= bit_index + 1'b1;

                            ttp_scl <= 1'b0;
                            timer   <= HALF_PERIOD_CYCLES - 1;
                            state   <= ST_LOW;
                        end
                    end
                    else begin
                        timer <= timer - 1'b1;
                    end
                end

                default: begin
                    state   <= ST_POWERUP;
                    timer   <= POWERUP_CYCLES - 1;
                    ttp_scl <= 1'b1;
                end

            endcase
        end
    end

endmodule
