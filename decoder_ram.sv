
module decoder_ram (
    input clk,
    input rst,
    input we,
    input re,
    input [6:0] addr,
    input [7:0] wdata,
    output reg [7:0] rdata,
    output reg valid
);

    wire [1:0] block_select;
    wire [4:0] word_address;

    assign block_select = addr[6:5];
    assign word_address = addr[4:0];

    integer i;

    reg [7:0] mem_block0 [0:31];
    reg [7:0] mem_block1 [0:31];
    reg [7:0] mem_block2 [0:31];
    reg [7:0] mem_block3 [0:31];

    // Write operation
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                mem_block0[i] <= 8'h00;
                mem_block1[i] <= 8'h00;
                mem_block2[i] <= 8'h00;
                mem_block3[i] <= 8'h00;
            end
        end
        else if (we) begin
            case (block_select)
                2'b00: mem_block0[word_address] <= wdata;
                2'b01: mem_block1[word_address] <= wdata;
                2'b10: mem_block2[word_address] <= wdata;
                2'b11: mem_block3[word_address] <= wdata;
            endcase
        end
    end

    // Combinational read operation
    always @(*) begin
        rdata = 8'h00;
        valid = 1'b0;

        if (re) begin
            case (block_select)
                2'b00: rdata = mem_block0[word_address];
                2'b01: rdata = mem_block1[word_address];
                2'b10: rdata = mem_block2[word_address];
                2'b11: rdata = mem_block3[word_address];
            endcase

            valid = 1'b1;
        end
    end

endmodule
