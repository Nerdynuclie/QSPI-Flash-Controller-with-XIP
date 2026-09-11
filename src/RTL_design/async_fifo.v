module async_fifo #(parameter WIDTH = 6 , 
                    parameter DEPTH = 8 //always power 2 value
                    ) ( wr_data, wr_clk, wr_rst , wr_en , rd_data , rd_en, rd_clk, rd_rst, fifo_full, fifo_empty );

// wr_ptr
input wire wr_clk;
input wire wr_rst;
input wire  wr_en;
output wire fifo_full;

//rd_ptr 
input wire rd_clk;
input wire rd_rst;
input wire  rd_en;
output wire fifo_empty;
//data in
input  wire [WIDTH-1:0] wr_data;
//data out
output wire [WIDTH-1:0] rd_data;

//width of pointers 
localparam ptr_width = $clog2(DEPTH);

//pointers

wire [$clog2(DEPTH):0] wr_ptr; //write pointer

wire [$clog2(DEPTH):0] rd_ptr; //read pointer


//address 

wire [$clog2(DEPTH)-1:0] wr_addr; //write address 
wire [$clog2(DEPTH)-1:0] rd_addr; //read address

wire  [$clog2(DEPTH):0] req_to_rdptr, rd_ptr_bg, rd_ptr_reg, rd_ptr_sync ;
wire  [$clog2(DEPTH):0] req_to_wrptr, wr_ptr_bg, wr_ptr_reg, wr_ptr_sync ;

wire fifo_full_bus;
wire fifo_empty_bus;


//memory 
fifo_mem #(WIDTH , DEPTH) mem1 (
    .wr_clk     (wr_clk),
    .wr_en      (wr_en),
    .wr_rst_n   (wr_rst),
    .rd_clk     (rd_clk),
    .rd_rst_n   (rd_rst),
    .rd_en      (rd_en),
    .fifo_full  (fifo_full_bus),
    .fifo_empty (fifo_empty_bus),
    .wr_addr    (wr_addr),
    .rd_addr    (rd_addr),
    .wr_data    (wr_data),
    .rd_data    (rd_data)
    	
);

//write clock domain
write_ptr #( DEPTH) w1(  
    .wr_clk         (wr_clk) ,    
    .wr_rst         (wr_rst) , 
    .wr_en          (wr_en) , 
    .req_to_rdptr   (req_to_rdptr), 
    .fifo_full      (fifo_full_bus),
    .wr_addr        (wr_addr),
    .wr_ptr	        (wr_ptr)
);
//bin to gray read-write
genvar i;

bin_to_gray #( DEPTH) bg1 (
    .b_in(rd_ptr) , 
    .g_out(rd_ptr_bg)
);

//reg read_ptr_bg
generate
    for(i=0;i<=ptr_width;i=i+1) begin :loop_1
        d_ff d1(
            .clk(rd_clk) ,
            .rst(rd_rst) , 
            .din(rd_ptr_bg[i]) , 
            .dout(rd_ptr_reg[i])
        );
    end
endgenerate
//sync read-write

generate
    for(i=0;i<=ptr_width;i=i+1) begin :loop_2
        two_ff_sync t1(
            .clk(wr_clk) ,
            .rst(wr_rst) , 
            .din(rd_ptr_reg[i]) , 
            .dout(rd_ptr_sync[i])
        );
    end
endgenerate

//gray to bin sync-write

gray_to_bin #(DEPTH) gb1( 
    .g_in(rd_ptr_sync),
    .b_out(req_to_rdptr)
);


//read clock domain
read_ptr #(DEPTH) w2(   
    .rd_clk         (rd_clk) , 
    .rd_rst         (rd_rst) , 
    .rd_en          (rd_en) , 
    .req_to_wrptr   (req_to_wrptr),
    .fifo_empty     (fifo_empty_bus),
    .rd_ptr         (rd_ptr),
    .rd_addr        (rd_addr)
);

//bin to gray read-write

bin_to_gray #(DEPTH) bg2 (
    .b_in(wr_ptr) , 
    .g_out(wr_ptr_bg)
);

//registering the wr_pyt_bg

generate
    for(i=0;i<=ptr_width;i=i+1) begin :loop_3
        d_ff d2(
            .clk(wr_clk) ,
            .rst(wr_rst) , 
            .din(wr_ptr_bg[i]) ,
            .dout(wr_ptr_reg[i])
        );
    end
endgenerate

//sync write-read

generate
    for(i=0;i<=ptr_width;i=i+1) begin :loop_4
        two_ff_sync t2(
            .clk(rd_clk) ,
            .rst(rd_rst) , 
            .din(wr_ptr_reg[i]) ,
            .dout(wr_ptr_sync[i])
        );
    end
endgenerate

//gray to bin sync-write
gray_to_bin #(DEPTH) gb2(
    .g_in(wr_ptr_sync), 
    .b_out(req_to_wrptr)
);

assign fifo_full = fifo_full_bus;
assign fifo_empty = fifo_empty_bus;
    
endmodule



