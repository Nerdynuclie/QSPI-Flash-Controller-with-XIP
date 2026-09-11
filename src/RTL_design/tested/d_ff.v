module d_ff (
    input  wire clk,rst,
    input  wire din,
    output reg  dout
);

always @ (posedge clk or negedge rst) begin
    if(!rst) begin
        dout<=0;
    end
    else begin
        dout<=din;
    end
end
endmodule