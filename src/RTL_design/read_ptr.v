module read_ptr #(parameter DEPTH = 8) ( rd_clk, rd_rst , rd_en , req_to_wrptr , rd_ptr , rd_addr , fifo_empty);
localparam ptr_width = $clog2(DEPTH);
input wire              rd_clk;
input wire              rd_rst;
input wire              rd_en;
input wire [ptr_width:0]    req_to_wrptr;

output reg [ptr_width:0]   rd_ptr;
output reg [ptr_width-1:0] rd_addr;

output wire                 fifo_empty;
assign fifo_empty = (rd_ptr == req_to_wrptr);


always @(posedge rd_clk or negedge rd_rst)
begin
    if(!rd_rst)
    begin
        rd_ptr  <= 0;
        rd_addr <= 0;
    end
    else if(rd_en && !fifo_empty)
    begin
        rd_ptr  <= rd_ptr + 1'b1;
        rd_addr <= rd_addr + 1'b1;
    end
end
endmodule

