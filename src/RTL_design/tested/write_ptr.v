module write_ptr #(parameter DEPTH=8) ( wr_clk , wr_rst , wr_en, wr_ptr , req_to_rdptr , fifo_full, wr_addr);
localparam width=$clog2(DEPTH);
//input ports
input wire              wr_clk;
input wire              wr_rst;
input wire              wr_en;
input wire [width:0]    req_to_rdptr;

//output
output reg [width:0]    wr_ptr;
wire [width:0] wr_ptr_next;

assign wr_ptr_next = wr_ptr + 1'b1;
output reg [width-1:0]  wr_addr;
output reg              fifo_full;

always @(posedge wr_clk or negedge wr_rst) begin
    if(!wr_rst) begin
        wr_ptr<=0;
        wr_addr<=0;
        fifo_full<=0;
    end
    else begin
        if(wr_en) begin
            if(!({~wr_ptr_next[width],wr_ptr_next[width-1:0]}!=req_to_rdptr)) begin
                fifo_full <= 1'b1;
            end 
            else begin
                wr_ptr    <= wr_ptr + 1'b1;
                wr_addr   <= wr_addr + 1'b1;
                fifo_full <= 0;
            end
    end
    else begin
        wr_ptr    <= wr_ptr;
        wr_addr   <= wr_addr;
        fifo_full <= fifo_full;
    
    end
end
end
endmodule

