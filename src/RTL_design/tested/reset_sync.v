
module reset_sync
(
    input  wire clk,          // destination domain clock
    input  wire async_rst_n,  // asynchronous active-low reset (source)
    output wire sync_rst_n    // synchronized active-low reset (destination domain)
);

reg rst_ff1;
reg rst_ff2;

// Async assert (either flop clears immediately when async_rst_n drops),
// sync deassert (release ripples through two clk edges before flop2 goes high).
always @(posedge clk or negedge async_rst_n)
begin
    if(!async_rst_n)
    begin
        rst_ff1 <= 1'b0;
        rst_ff2 <= 1'b0;
    end
    else
    begin
        rst_ff1 <= 1'b1;
        rst_ff2 <= rst_ff1;
    end
end

assign sync_rst_n = rst_ff2;

endmodule