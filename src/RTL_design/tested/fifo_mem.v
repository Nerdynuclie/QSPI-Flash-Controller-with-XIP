module fifo_mem #(
    parameter WIDTH = 6,
    parameter DEPTH = 8 //always power of 2
)(
    input  wire                      wr_clk,
    input  wire                      wr_rst_n,      // active-low async reset
    input  wire                      rd_clk,
    input  wire                      rd_rst_n,
    input  wire                      wr_en,
    input  wire                      rd_en,
    input  wire                      fifo_full,
    input  wire                      fifo_empty,
    input  wire [$clog2(DEPTH)-1:0]  wr_addr,
    input  wire [$clog2(DEPTH)-1:0]  rd_addr,
    input  wire [WIDTH-1:0]          wr_data,
    output reg  [WIDTH-1:0]          rd_data
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    integer i;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            for(i = 0 ; i<DEPTH ; i = i+1) begin
                mem [i] <= 0;
            end
        end
        else begin
            if (wr_en && !fifo_full) begin
                mem[wr_addr] <= wr_data;
            end
        end
    end

    always @ (posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            rd_data <= {WIDTH{1'b0}};
        end
        else begin
            if(rd_en && !fifo_empty) begin
                    rd_data <= mem[rd_addr];
            end
        end
    end
endmodule
