module clk_div(
    input  wire         PCLK,
    input  wire         PRESETn,
    input  wire [22:0]  DIVIDER,
    input  wire         EN,
    input  wire         SPI_BUSY,
    input  wire         CPOL,
    input  wire         CPHA,

    output reg          SCLK,
    output reg          SPOS,
    output reg          SNEG,  
    output wire          sample_edge,
    output wire         shift_edge
);

reg [22:0] count;

//clock generation
always @ (posedge PCLK or negedge PRESETn) begin
    if(!PRESETn) begin
        SCLK        <= CPOL;
        count       <= 23'b0;
        SPOS        <= 1'b0;
        SNEG        <= 1'b0;
    end
    else if(SPI_BUSY && EN) begin
        SPOS <= 1'b0;
        SNEG <= 1'b0;
        if(count >= DIVIDER-1'b1) begin
            //edge detection
            if (SCLK == 1'b0) begin
                SPOS <= 1'b1;
            end
            else begin
                SNEG <= 1'b1;
            end
            SCLK    <= ~SCLK;
            count   <= 23'b0;
        end
        else begin
            count   <= count + 1'b1;
            SCLK    <= SCLK;
        end
    end
    else begin
        SCLK    <= CPOL;
        count   <= 23'b0;
        SPOS    <= 1'b0;
        SNEG    <= 1'b0;
    end
end

assign sample_edge = (CPHA) ? (CPOL ? SPOS : SNEG) : (CPOL ? SNEG : SPOS);
assign shift_edge  = (CPHA) ? (CPOL ? SNEG : SPOS) : (CPOL ? SPOS : SNEG);

endmodule