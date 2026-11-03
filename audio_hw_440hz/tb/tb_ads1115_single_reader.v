`timescale 1ns/1ps

module tb_ads1115_single_reader;

    // ============================================================
    // 1. Test clock
    // ============================================================

    reg clk = 1'b0;

    always #10 clk = ~clk;

    reg rst_n;
    reg start;

    wire [15:0] adc_raw;
    wire data_valid;
    wire done;
    wire nack_error;
    wire busy;

    // ============================================================
    // 2. Pull-up I2C bus
    //
    // tri1 models the pull-up resistors.
    // ============================================================

    tri1 i2c_scl;
    tri1 i2c_sda;

    reg slave_sda_low;

    assign i2c_sda =
        slave_sda_low ? 1'b0 : 1'bz;

    // ============================================================
    // 3. DUT
    //
    // Short timings for simulation only.
    // ============================================================

    ads1115_single_reader #(
        .I2C_QUARTER_CYCLES(4),
        .CONVERSION_WAIT_CYCLES(80),
        .I2C_ADDR(7'h48),
        .CHANNEL(2'd0)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),

        .i2c_scl(i2c_scl),
        .i2c_sda(i2c_sda),

        .adc_raw(adc_raw),
        .data_valid(data_valid),
        .done(done),
        .nack_error(nack_error),
        .busy(busy)
    );

    // ============================================================
    // 4. Slave-side I2C tasks
    // ============================================================

    task wait_start;

        begin : start_wait

            forever begin

                @(negedge i2c_sda);

                if (i2c_scl === 1'b1)
                    disable start_wait;

            end

        end

    endtask


    task wait_stop;

        begin : stop_wait

            forever begin

                @(posedge i2c_sda);

                if (i2c_scl === 1'b1)
                    disable stop_wait;

            end

        end

    endtask


    // ============================================================
    // Receive one byte from FPGA
    // ============================================================

    task receive_byte;

        output [7:0] value;

        integer bit_number;

        begin

            value = 8'd0;

            for (
                bit_number = 7;
                bit_number >= 0;
                bit_number = bit_number - 1
            ) begin

                @(posedge i2c_scl);
                #1;

                value[bit_number] = i2c_sda;

                @(negedge i2c_scl);

            end

        end

    endtask


    // ============================================================
    // Check transmitted byte and send ACK
    // ============================================================

    task expect_byte_ack;

        input [7:0] expected;

        reg [7:0] received;

        begin

            receive_byte(received);

            if (received !== expected) begin

                $display(
                    "FAIL: Expected I2C byte=%h, got=%h",
                    expected,
                    received
                );

                $fatal(1);

            end

            // Slave ACK is active-low.
            slave_sda_low = 1'b1;

            @(posedge i2c_scl);
            @(negedge i2c_scl);

            slave_sda_low = 1'b0;

        end

    endtask


    // ============================================================
    // Send conversion byte to FPGA
    //
    // expected_ack:
    //   1 = FPGA must ACK
    //   0 = FPGA must NACK
    // ============================================================

    task send_byte;

        input [7:0] value;
        input expected_ack;

        integer bit_number;

        reg expected_sda;

        begin

            for (
                bit_number = 7;
                bit_number >= 0;
                bit_number = bit_number - 1
            ) begin

                // I2C data is set while SCL is low.
                slave_sda_low = ~value[bit_number];

                @(posedge i2c_scl);
                @(negedge i2c_scl);

            end

            // Release SDA for master's ACK/NACK.
            slave_sda_low = 1'b0;

            @(posedge i2c_scl);
            #1;

            expected_sda =
                expected_ack ? 1'b0 : 1'b1;

            if (i2c_sda !== expected_sda) begin

                $display(
                    "FAIL: Master ACK/NACK incorrect"
                );

                $fatal(1);

            end

            @(negedge i2c_scl);

        end

    endtask


    // ============================================================
    // 5. Simulated ADS1115
    //
    // Test samples:
    //
    // Case 1: 0x1234
    // Case 2: 0x6543
    //
    // Case 3: Address NACK
    // ============================================================

    integer transaction_index;

    reg [15:0] sample_value;
    reg [7:0] received_address;

    reg slave_finished;

    initial begin

        slave_sda_low = 1'b0;
        slave_finished = 1'b0;

        for (
            transaction_index = 0;
            transaction_index < 2;
            transaction_index = transaction_index + 1
        ) begin

            if (transaction_index == 0)
                sample_value = 16'h1234;
            else
                sample_value = 16'h6543;


            // ================================================
            // Transaction A:
            //
            // START
            // 0x90 -> ACK
            // 0x01 -> ACK
            // 0xC3 -> ACK
            // 0xE3 -> ACK
            // STOP
            // ================================================

            wait_start();

            expect_byte_ack(8'h90);
            expect_byte_ack(8'h01);
            expect_byte_ack(8'hC3);
            expect_byte_ack(8'hE3);

            wait_stop();


            // ================================================
            // Transaction B:
            //
            // Set Conversion register pointer.
            // ================================================

            wait_start();

            expect_byte_ack(8'h90);
            expect_byte_ack(8'h00);

            wait_stop();


            // ================================================
            // Transaction C:
            //
            // Read 16-bit conversion result.
            // ================================================

            wait_start();

            expect_byte_ack(8'h91);

            send_byte(
                sample_value[15:8],
                1'b1
            );

            send_byte(
                sample_value[7:0],
                1'b0
            );

            wait_stop();

            $display(
                "SLAVE: Completed conversion transaction %0d",
                transaction_index
            );

        end


        // ====================================================
        // Third test:
        // Device does not acknowledge its address.
        // ====================================================

        wait_start();

        receive_byte(received_address);

        if (received_address !== 8'h90) begin

            $display("FAIL: NACK test address mismatch");
            $fatal(1);

        end

        // Do not pull SDA low.
        // This is a slave NACK.
        slave_sda_low = 1'b0;

        @(posedge i2c_scl);
        @(negedge i2c_scl);

        wait_stop();

        slave_finished = 1'b1;

    end


    // ============================================================
    // 6. FPGA-side test
    // ============================================================

    task request_conversion;

        input expect_failure;
        input [15:0] expected_raw;

        begin

            @(negedge clk);
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            if (busy !== 1'b1) begin

                $display("FAIL: Busy not asserted");
                $fatal(1);

            end

            @(posedge done);
            #1;

            if (expect_failure) begin

                if (nack_error !== 1'b1 ||
                    data_valid !== 1'b0) begin

                    $display(
                        "FAIL: NACK handling incorrect"
                    );

                    $fatal(1);

                end

                // Failed transaction must not replace
                // the last good ADC result.
                if (adc_raw !== expected_raw) begin

                    $display(
                        "FAIL: ADC value changed on NACK"
                    );

                    $fatal(1);

                end

            end
            else begin

                if (nack_error !== 1'b0 ||
                    data_valid !== 1'b1 ||
                    adc_raw !== expected_raw) begin

                    $display("");
                    $display("FAIL: ADC conversion mismatch");

                    $display(
                        "Expected=%h Actual=%h",
                        expected_raw,
                        adc_raw
                    );

                    $display(
                        "Valid=%b NACK=%b",
                        data_valid,
                        nack_error
                    );

                    $fatal(1);

                end

            end

            repeat (8)
                @(negedge clk);

            if (busy !== 1'b0) begin

                $display(
                    "FAIL: Controller did not return idle"
                );

                $fatal(1);

            end

        end

    endtask


    // ============================================================
    // Main sequence
    // ============================================================

    initial begin

        rst_n = 1'b0;
        start = 1'b0;

        repeat (10)
            @(negedge clk);

        rst_n = 1'b1;

        repeat (8)
            @(negedge clk);


        $display("");
        $display("CASE 1: Read ADS1115 AIN0");

        request_conversion(
            1'b0,
            16'h1234
        );

        $display("CASE 1 PASS");


        $display("");
        $display("CASE 2: Second conversion");

        request_conversion(
            1'b0,
            16'h6543
        );

        $display("CASE 2 PASS");


        $display("");
        $display("CASE 3: Address NACK");

        request_conversion(
            1'b1,
            16'h6543
        );

        $display("CASE 3 PASS");


        if (!slave_finished) begin

            $display("FAIL: Slave incomplete");
            $fatal(1);

        end

        $display("");
        $display("==========================================");
        $display("ADS1115 SINGLE READER TEST PASS");
        $display("Successful conversions: 2");
        $display("NACK handling: PASS");
        $display("==========================================");

        $finish;

    end


    // ============================================================
    // Simulation timeout
    // ============================================================

    initial begin

        #5000000;

        $display("FAIL: Simulation timeout");
        $fatal(1);

    end

endmodule