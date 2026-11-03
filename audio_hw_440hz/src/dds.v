module dds (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_en,
    input  wire [31:0]        fcw,

    output wire signed [15:0] pcm_out
);

    reg [31:0] phase_acc;

    reg signed [15:0] sine_rom [0:1023];

    wire [9:0] wave_addr;


    // Load the sine lookup table
    initial begin
        $readmemh("src/sine_1024.mem", sine_rom);
    end


    // Phase accumulator
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phase_acc <= 32'd0;
        else if (sample_en)
            phase_acc <= phase_acc + fcw;
    end


    // Use the upper 10 bits as the ROM address
    assign wave_addr = phase_acc[31:22];


    // Output signed 16-bit PCM sample
    assign pcm_out = sine_rom[wave_addr];

endmodule