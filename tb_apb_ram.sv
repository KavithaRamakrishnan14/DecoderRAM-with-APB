
`timescale 1ns/1ps

module tb_apb_ram;

    //==================================================
    // 1. APB INTERFACE SIGNALS
    //==================================================
    reg PCLK;
    reg PRESETn;
    reg PSEL;
    reg PENABLE;
    reg PWRITE;
    reg [6:0] PADDR;
    reg [7:0] PWDATA;

    wire [7:0] PRDATA;
    wire PREADY;
    wire PSLVERR;

    integer pass_count = 0;
    integer fail_count = 0;
    integer assertion_fail_count = 0;

    //==================================================
    // 2. EXPECTED MEMORY - SCOREBOARD REFERENCE MODEL
    //==================================================
    reg [7:0] expected_mem [0:127];
    integer i;

    //==================================================
    // 3. DESIGN UNDER TEST (DUT)
    //==================================================
    apb_ram dut (
        .PCLK    (PCLK),
        .PRESETn (PRESETn),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PADDR   (PADDR),
        .PWDATA  (PWDATA),
        .PRDATA  (PRDATA),
        .PREADY  (PREADY),
        .PSLVERR (PSLVERR)
    );

    //==================================================
    // 4. CLOCK GENERATION
    //==================================================
    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK;
    end

    //==================================================
    // 5. FUNCTIONAL COVERAGE
    //==================================================
    covergroup apb_coverage;

        // Cover all four RAM blocks
        cp_block: coverpoint PADDR[6:5] {
            bins ram0 = {2'b00};
            bins ram1 = {2'b01};
            bins ram2 = {2'b10};
            bins ram3 = {2'b11};
        }

        // Cover read and write operations
        cp_operation: coverpoint PWRITE {
            bins read_op  = {1'b0};
            bins write_op = {1'b1};
        }

        // Cover read/write operations in every RAM block
        block_operation: cross cp_block, cp_operation;

    endgroup

    apb_coverage cov;

    initial begin
        cov = new();
    end

    //==================================================
    // 6. DRIVER
    // Generates APB transactions
    //==================================================

    task apb_write;
        input [6:0] address;
        input [7:0] data;
        begin
            // Setup phase
            @(negedge PCLK);
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b1;
            PADDR   = address;
            PWDATA  = data;

            // Access phase
            @(negedge PCLK);
            PENABLE = 1'b1;

            // Allow the access to complete
            @(posedge PCLK);
            #1;

            @(negedge PCLK);
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = 0;
            PWDATA  = 0;
        end
    endtask

    task apb_read;
        input [6:0] address;
        begin
            // Setup phase
            @(negedge PCLK);
            PSEL    = 1'b1;
            PENABLE = 1'b0;
            PWRITE  = 1'b0;
            PADDR   = address;
            PWDATA  = 0;

            // Access phase
            @(negedge PCLK);
            PENABLE = 1'b1;

            // Monitor and scoreboard sample at posedge
            @(posedge PCLK);
            #1;

            @(negedge PCLK);
            PSEL    = 1'b0;
            PENABLE = 1'b0;
            PADDR   = 0;
        end
    endtask

    //==================================================
    // 7. MONITOR + SCOREBOARD
    // Observe transfers and compare expected data
    //==================================================

    initial begin
        for (i = 0; i < 128; i = i + 1)
            expected_mem[i] = 8'h00;
    end

    // Clear the reference model when reset is asserted
    always @(negedge PRESETn) begin
        for (integer j = 0; j < 128; j = j + 1)
            expected_mem[j] = 8'h00;
    end

    always @(posedge PCLK) begin
        if (PRESETn && PSEL && PENABLE && PREADY) begin

            // Sample functional coverage
            cov.sample();

            // Monitor completed APB transfer
            $display(
                "[MONITOR] time=%0t addr=%0d write=%b wdata=%h rdata=%h",
                $time, PADDR, PWRITE, PWDATA, PRDATA
            );

            if (PSLVERR !== 1'b0) begin
                $display("[SCOREBOARD] FAIL: PSLVERR asserted");
                fail_count = fail_count + 1;
            end
            else if (PWRITE) begin

                // Update expected memory after a write
                expected_mem[PADDR] = PWDATA;

                $display(
                    "[SCOREBOARD] WRITE recorded: addr=%0d data=%h",
                    PADDR, PWDATA
                );

                pass_count = pass_count + 1;
            end
            else begin

                // Compare actual read with expected read
                if (PRDATA === expected_mem[PADDR]) begin
                    $display(
                        "[SCOREBOARD] PASS: addr=%0d expected=%h actual=%h",
                        PADDR, expected_mem[PADDR], PRDATA
                    );
                    pass_count = pass_count + 1;
                end
                else begin
                    $display(
                        "[SCOREBOARD] FAIL: addr=%0d expected=%h actual=%h",
                        PADDR, expected_mem[PADDR], PRDATA
                    );
                    fail_count = fail_count + 1;
                end
            end
        end
    end

    //==================================================
    // 8. ASSERTIONS
    // Check basic APB protocol requirements
    //==================================================

    reg prev_setup;
    reg [6:0] prev_addr;
    reg [7:0] prev_wdata;
    reg prev_write;

    initial begin
        prev_setup = 0;
        prev_addr = 0;
        prev_wdata = 0;
        prev_write = 0;
    end

    always @(posedge PCLK) begin
        if (!PRESETn) begin
            prev_setup <= 0;
        end
        else begin

            // PENABLE must not be high without PSEL
            if (PENABLE && !PSEL) begin
                $error("ASSERTION FAILED: PENABLE high without PSEL");
                assertion_fail_count = assertion_fail_count + 1;
            end

            // Check setup followed by access
            if (PSEL && !PENABLE) begin
                prev_setup <= 1;
                prev_addr <= PADDR;
                prev_wdata <= PWDATA;
                prev_write <= PWRITE;
            end
            else if (PSEL && PENABLE) begin

                if (!prev_setup) begin
                    $error("ASSERTION FAILED: Access without setup");
                    assertion_fail_count = assertion_fail_count + 1;
                end

                // Address and control must remain stable
                if (prev_setup &&
                    ((PADDR !== prev_addr) ||
                     (PWRITE !== prev_write) ||
                     (PWRITE && (PWDATA !== prev_wdata)))) begin

                    $error("ASSERTION FAILED: APB controls changed");
                    assertion_fail_count = assertion_fail_count + 1;
                end

                // This DUT is designed for zero wait states
                if (PREADY !== 1'b1) begin
                    $error("ASSERTION FAILED: PREADY should be high");
                    assertion_fail_count = assertion_fail_count + 1;
                end

                prev_setup <= 0;
            end
            else begin
                prev_setup <= 0;
            end
        end
    end

    //==================================================
    // 9. MAIN TEST SEQUENCE
    //==================================================

    integer k;
    reg [7:0] random_data;

    initial begin
        PSEL = 0;
        PENABLE = 0;
        PWRITE = 0;
        PADDR = 0;
        PWDATA = 0;
        PRESETn = 0;

        $display("==================================");
        $display("APB RAM VERIFICATION STARTED");
        $display("==================================");

        // Reset
        repeat (2) @(negedge PCLK);
        PRESETn = 1;

        // Test every RAM block
      /*  apb_write(7,   8'hA5);
        apb_read(7);

        apb_write(40,  8'h3C);
        apb_read(40);

        apb_write(75,  8'hF0);
        apb_read(75);

        apb_write(100, 8'h69);
        apb_read(100);

        // Test first and last locations
        apb_write(31,  8'h5A);
        apb_read(31);

        apb_write(63,  8'hC3);
        apb_read(63);

        apb_write(95,  8'h0F);
        apb_read(95);

        apb_write(127, 8'h96);
        apb_read(127);

        // Test overwriting an existing location
        apb_write(7, 8'h12);
        apb_read(7);*/
// Test every RAM block
apb_write(7,   8'hA5);
expected_mem[7] = 8'hFF;  // Intentionally wrong expected value
apb_read(7);              // Should report FAIL

apb_write(40,  8'h3C);
apb_read(40);

apb_write(75,  8'hF0);
apb_read(75);

apb_write(100, 8'h69);
apb_read(100);

// Test first and last locations
apb_write(31,  8'h5A);
apb_read(31);

apb_write(63,  8'hC3);
apb_read(63);

apb_write(95,  8'h0F);
apb_read(95);

apb_write(127, 8'h96);
apb_read(127);

// Test overwriting an existing location
apb_write(7, 8'h12);
apb_read(7);

        // Test randomized write/read pairs
        for (k = 0; k < 20; k = k + 1) begin
            random_data = $urandom;
            apb_write($urandom_range(0,127), random_data);

            // Read back the same address
            // Save the chosen address before reading
            // (see corrected random sequence below)
        end

        // Reset test
        @(negedge PCLK);
        PRESETn = 0;
        PSEL = 0;
        PENABLE = 0;
        PWRITE = 0;
        PADDR = 0;
        PWDATA = 0;

        repeat (2) @(negedge PCLK);
        PRESETn = 1;

        // Read a previously written address after reset
        apb_read(7);
        apb_read(40);
        apb_read(75);
        apb_read(100);

        // Final report
        #2;
        $display("==================================");
        $display("VERIFICATION SUMMARY");
        $display("Scoreboard PASS = %0d", pass_count);
        $display("Scoreboard FAIL = %0d", fail_count);
        $display("Assertion FAIL  = %0d", assertion_fail_count);
        $display("Functional coverage = %0.2f%%", cov.get_coverage());
        $display("==================================");

        if ((fail_count == 0) && (assertion_fail_count == 0))
            $display("RESULT: ALL CHECKS PASSED");
        else
            $display("RESULT: VERIFICATION FAILED");

        $finish;
    end

endmodule
