module qspi_ice
(
    input wire clk,
    input wire rst_n,

    //APB Config Registers
    input wire start,

    input wire is_read,
    input wire is_write,
    input wire erase_en,

    input wire opcode_en,
    input wire addr_en,
    input wire mode_en,
    input wire dummy_en,
    input wire data_en,

    input wire [1:0] addr_mode,
    input wire [1:0] mode_mode,
    input wire [1:0] dummy_mode,
    input wire [1:0] data_mode,

    input wire [7:0]  opcode,
    input wire [23:0] address,
    input wire [7:0]  mode_byte,
    input wire [7:0]  dummy_cycles,
    input wire [15:0] data_len,

    //CMD FIFO
    input  wire        cmd_fifo_full,
    output reg         cmd_fifo_wr_en,
    output reg [79:0]  cmd_fifo_wdata,

    //QSPI Status
    input wire qspi_done,

    //RX FIFO
    input wire [31:0] rx_fifo_rdata,
    input wire        rx_fifo_empty,
    output reg        rx_fifo_rd_en,

    //Back To APB
    output reg [31:0] ice_rdata,
    output reg        busy,
    output reg        done,
    output reg        error
);

// Descriptor Packing
wire [79:0] txn_desc;

assign txn_desc =
{
    is_read,
    is_write,
    erase_en,

    opcode_en,
    addr_en,
    mode_en,
    dummy_en,
    data_en,

    addr_mode,
    mode_mode,
    dummy_mode,
    data_mode,

    opcode,
    address,
    mode_byte,
    dummy_cycles,
    data_len
};

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        busy <= 1'b0;
    else if(qspi_done)
        busy <= 1'b0;
    else if(start && !cmd_fifo_full)
        busy <= 1'b1;
end

// Main Logic
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        cmd_fifo_wr_en <= 1'b0;
        cmd_fifo_wdata <= 80'd0;
        done           <= 1'b0;
        error          <= 1'b0;

        ice_rdata      <= 32'd0;
        rx_fifo_rd_en  <= 1'b0;
    end
    else
    begin

        cmd_fifo_wr_en <= 1'b0;
        done           <= 1'b0;
        rx_fifo_rd_en  <= 1'b0;

        
        // Start Transaction 
        if(start)
        begin

            if(cmd_fifo_full)
            begin
                error <= 1'b1;
            end
            else
            begin
                error <= 1'b0;

                cmd_fifo_wr_en <= 1'b1;
                cmd_fifo_wdata <= txn_desc;
            end
        end

        // Completion
        if(qspi_done)
        begin
            done <= 1'b1;
            // Read Transaction
            if(is_read && !rx_fifo_empty)
            begin
                rx_fifo_rd_en <= 1'b1;
                ice_rdata     <= rx_fifo_rdata;
            end
        end
    end
end

endmodule