module bin_to_gray #(
    parameter DEPTH = 8
    ) (b_in , g_out);
localparam width=$clog2(DEPTH);

input wire [width:0]  b_in;
output wire [width:0] g_out;

assign g_out = b_in ^b_in>>1;

endmodule
