module adsr_envelope #(
    parameter [14:0] ATTACK_STEP   = 15'd14,
    parameter [14:0] DECAY_STEP    = 15'd3,
    parameter [14:0] SUSTAIN_LEVEL = 15'd19660,
    parameter [14:0] RELEASE_STEP  = 15'd2
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sample_en,
    input  wire        gate,

    output reg  [14:0] env_level,
    output wire        env_active
);

    // ------------------------------------------------------------
    // Envelope range
    //
    // 0     -> silence
    // 32767 -> full level
    // ------------------------------------------------------------
    localparam [14:0] MAX_LEVEL =
        15'd32767;


    // ------------------------------------------------------------
    // ADSR states
    // ------------------------------------------------------------
    localparam [2:0] STATE_IDLE =
        3'd0;

    localparam [2:0] STATE_ATTACK =
        3'd1;

    localparam [2:0] STATE_DECAY =
        3'd2;

    localparam [2:0] STATE_SUSTAIN =
        3'd3;

    localparam [2:0] STATE_RELEASE =
        3'd4;


    reg [2:0] state;


    // ============================================================
    // Envelope active indicator
    // ============================================================
    assign env_active =
        (state != STATE_IDLE) ||
        (env_level != 15'd0);


    // ============================================================
    // ADSR state machine
    //
    // Envelope changes only once per audio sample.
    // ============================================================
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state     <= STATE_IDLE;
            env_level <= 15'd0;

        end
        else if (sample_en) begin

            case (state)

                // =================================================
                // IDLE
                //
                // Wait for Note On.
                // =================================================
                STATE_IDLE: begin

                    env_level <= 15'd0;

                    if (gate) begin

                        state <= STATE_ATTACK;

                    end

                end


                // =================================================
                // ATTACK
                //
                // Envelope rises toward maximum level.
                // =================================================
                STATE_ATTACK: begin

                    // Note released during Attack.
                    if (!gate) begin

                        state <= STATE_RELEASE;

                    end

                    // Attack finished.
                    else if (
                        env_level >=
                        (MAX_LEVEL - ATTACK_STEP)
                    ) begin

                        env_level <= MAX_LEVEL;

                        state <= STATE_DECAY;

                    end

                    // Continue Attack.
                    else begin

                        env_level <=
                            env_level + ATTACK_STEP;

                    end

                end


                // =================================================
                // DECAY
                //
                // Envelope falls from maximum level
                // toward sustain level.
                // =================================================
                STATE_DECAY: begin

                    // Note released during Decay.
                    if (!gate) begin

                        state <= STATE_RELEASE;

                    end

                    // Decay finished.
                    else if (
                        env_level <=
                        (SUSTAIN_LEVEL + DECAY_STEP)
                    ) begin

                        env_level <=
                            SUSTAIN_LEVEL;

                        state <=
                            STATE_SUSTAIN;

                    end

                    // Continue Decay.
                    else begin

                        env_level <=
                            env_level - DECAY_STEP;

                    end

                end


                // =================================================
                // SUSTAIN
                //
                // Hold sustain level while key is held.
                // =================================================
                STATE_SUSTAIN: begin

                    env_level <=
                        SUSTAIN_LEVEL;

                    if (!gate) begin

                        state <=
                            STATE_RELEASE;

                    end

                end


                // =================================================
                // RELEASE
                //
                // Envelope gradually falls toward zero.
                // =================================================
                STATE_RELEASE: begin

                    // Retrigger while release is still active.
                    if (gate) begin

                        state <=
                            STATE_ATTACK;

                    end

                    // Release finished.
                    else if (
                        env_level <= RELEASE_STEP
                    ) begin

                        env_level <= 15'd0;

                        state <= STATE_IDLE;

                    end

                    // Continue Release.
                    else begin

                        env_level <=
                            env_level - RELEASE_STEP;

                    end

                end


                // =================================================
                // Safety default
                // =================================================
                default: begin

                    state     <= STATE_IDLE;
                    env_level <= 15'd0;

                end

            endcase

        end

    end

endmodule