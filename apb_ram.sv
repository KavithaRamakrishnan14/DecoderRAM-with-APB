
module apb_ram (
    input PCLK,
    input PRESETn,

    input PSEL,
    input PENABLE,
    input PWRITE,
    input [6:0] PADDR,
    input [7:0] PWDATA,

    output [7:0] PRDATA,
    output PREADY,
    output PSLVERR
);

    wire we;
    wire re;
    wire [7:0] ram_rdata;
    wire ram_valid;

    // APB access phase
    wire access;
    assign access = PSEL && PENABLE;

    // Convert APB control signals into RAM controls
    assign we = access && PWRITE;
    assign re = access && !PWRITE;

    // Zero-wait-state APB slave
    assign PREADY = access;
    assign PSLVERR = 1'b0;

    // Read data from RAM
    assign PRDATA = ram_rdata;

    // Instantiate the decoder RAM
    decoder_ram u_decoder_ram (
        .clk   (PCLK),
        .rst   (PRESETn),
        .we    (we),
        .re    (re),
        .addr  (PADDR),
        .wdata (PWDATA),
        .rdata (ram_rdata),
        .valid (ram_valid)
    );

endmodule
