module two_ff_sync(clk , rst , din , dout);
input  wire clk;
input  wire rst;
input  wire din;
output reg  dout;

reg reg_1;
always @ (posedge clk or negedge rst) begin
    if(!rst) begin
        dout <= 0;
        reg_1 <= 0;
    end
    else begin
        reg_1 <= din;
        dout <= reg_1;
    end
end
endmodule
