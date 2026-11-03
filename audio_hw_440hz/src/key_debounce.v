module key_debounce #(
    parameter integer DEBOUNCE_COUNT = 480000
)(
    input  wire clk,
    input  wire rst_n,

    input  wire key_in_n,

    output reg  key_down,
    output reg  key_press_pulse,
    output reg  key_release_pulse
);

    // ------------------------------------------------------------
    // Input synchronizer
    //
    // The physical key is asynchronous to clk.
    // Two flip-flops are used to reduce metastability risk.
    // ------------------------------------------------------------
    reg key_sync_ff1;
    reg key_sync_ff2;


    // ------------------------------------------------------------
    // Debounced key state
    //
    // 1 -> released
    // 0 -> pressed
    // ------------------------------------------------------------
    reg stable_key_n;


    // ------------------------------------------------------------
    // 19 bits are enough for 480000:
    //
    // 2^19 = 524288
    // ------------------------------------------------------------
    reg [18:0] debounce_count;


    // ============================================================
    // Two-stage synchronizer
    // ============================================================
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            key_sync_ff1 <= 1'b1;
            key_sync_ff2 <= 1'b1;

        end
        else begin

            key_sync_ff1 <= key_in_n;
            key_sync_ff2 <= key_sync_ff1;

        end

    end


    // ============================================================
    // Debounce logic
    // ============================================================
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            stable_key_n <= 1'b1;

            debounce_count <= 19'd0;

            key_down <= 1'b0;

            key_press_pulse   <= 1'b0;
            key_release_pulse <= 1'b0;

        end
        else begin

            // Pulses are active for only one clk cycle.
            key_press_pulse   <= 1'b0;
            key_release_pulse <= 1'b0;


            // ----------------------------------------------------
            // Input is different from the accepted stable state.
            // Start or continue timing.
            // ----------------------------------------------------
            if (key_sync_ff2 != stable_key_n) begin

                if (debounce_count >= DEBOUNCE_COUNT - 1) begin

                    debounce_count <= 19'd0;

                    stable_key_n <= key_sync_ff2;


                    // ============================================
                    // New stable state = LOW
                    // Key pressed
                    // ============================================
                    if (key_sync_ff2 == 1'b0) begin

                        key_down <= 1'b1;

                        key_press_pulse <= 1'b1;

                    end


                    // ============================================
                    // New stable state = HIGH
                    // Key released
                    // ============================================
                    else begin

                        key_down <= 1'b0;

                        key_release_pulse <= 1'b1;

                    end

                end
                else begin

                    debounce_count <=
                        debounce_count + 1'b1;

                end

            end


            // ----------------------------------------------------
            // Input returned to the accepted stable state.
            // Any unfinished debounce timing is cancelled.
            // ----------------------------------------------------
            else begin

                debounce_count <= 19'd0;

            end

        end

    end

endmodule