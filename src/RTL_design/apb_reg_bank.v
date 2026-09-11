module apb_regbank
(
    input  wire         PCLK,
    input  wire         PRESETn,
    input  wire         PSEL,
    input  wire         PENABLE,
    input  wire         PWRITE,
    input  wire [7:0]   PADDR,
    input  wire [31:0]  PWDATA,
    output reg  [31:0]  PRDATA,
    
    //TX FIFO
    output reg          tx_fifo_wr_en,
    output reg [31:0]   tx_fifo_wdata,
    input  wire         tx_fifo_full,

    //ICE Interface
    output reg          start,
    output reg          is_read,
    output reg          is_write,
    output reg          erase_en,
    output reg          opcode_en,
    output reg          addr_en,
    output reg          mode_en,
    output reg          dummy_en,
    output reg          data_en,
    output reg [1:0]    addr_mode,
    output reg [1:0]    mode_mode,
    output reg [1:0]    dummy_mode,
    output reg [1:0]    data_mode,
    output reg [7:0]    opcode,
    output reg [23:0]   address,
    output reg [7:0]    mode_byte,
    output reg [7:0]    dummy_cycles,
    output reg [15:0]   data_len,
    
    // From ICE
    input  wire [31:0]  ice_rdata,
    input  wire         busy,
    input  wire         done,
    input  wire         error
);

localparam CTRL_REG      = 8'h00;
localparam OPCODE_REG    = 8'h04;
localparam ADDR_REG      = 8'h08;
localparam MODEBYTE_REG  = 8'h0C;
localparam DUMMY_REG     = 8'h10;
localparam DATALEN_REG   = 8'h14;
localparam MODECFG_REG   = 8'h18;
localparam TXDATA_REG    = 8'h1C;
localparam RXDATA_REG    = 8'h20;
localparam STATUS_REG    = 8'h24;

wire apb_write;
wire apb_read;

assign apb_write = PSEL & PENABLE & PWRITE;
assign apb_read  = PSEL & PENABLE & ~PWRITE;

always @(posedge PCLK or negedge PRESETn)
begin
    if(!PRESETn)
    begin
        start <= 0;

        is_read  <= 0;
        is_write <= 0;
        erase_en <= 0;

        opcode_en <= 0;
        addr_en   <= 0;
        mode_en   <= 0;
        dummy_en  <= 0;
        data_en   <= 0;

        opcode       <= 0;
        address      <= 0;
        mode_byte    <= 0;
        dummy_cycles <= 0;
        data_len     <= 0;

        addr_mode  <= 0;
        mode_mode  <= 0;
        dummy_mode <= 0;
        data_mode  <= 0;

        tx_fifo_wr_en <= 0;
        tx_fifo_wdata <= 0;
    end
    else
    begin

        start         <= 1'b0;
        tx_fifo_wr_en <= 1'b0;

        if(apb_write)
        begin

            case(PADDR)

            CTRL_REG:
            begin
                start    <= PWDATA[0];
                is_read  <= PWDATA[1];
                is_write <= PWDATA[2];
                erase_en <= PWDATA[3];
            end

            OPCODE_REG:
            begin
                opcode_en <= PWDATA[8];
                opcode    <= PWDATA[7:0];
            end

            ADDR_REG:
            begin
                addr_en <= PWDATA[24];
                address <= PWDATA[23:0];
            end

            MODEBYTE_REG:
            begin
                mode_en   <= PWDATA[8];
                mode_byte <= PWDATA[7:0];
            end

            DUMMY_REG:
            begin
                dummy_en     <= PWDATA[8];
                dummy_cycles <= PWDATA[7:0];
            end

            DATALEN_REG:
            begin
                data_en  <= PWDATA[16];
                data_len <= PWDATA[15:0];
            end

            MODECFG_REG:
            begin
                addr_mode  <= PWDATA[1:0];
                mode_mode  <= PWDATA[3:2];
                dummy_mode <= PWDATA[5:4];
                data_mode  <= PWDATA[7:6];
            end

            //Data
            TXDATA_REG:
            begin
                if(!tx_fifo_full)
                begin
                    tx_fifo_wr_en <= 1'b1;
                    tx_fifo_wdata <= PWDATA;
                end
            end

            endcase
        end
    end
end

always @(*)
begin

    PRDATA = 32'd0;

    if(apb_read)
    begin

        case(PADDR)
        RXDATA_REG:
            PRDATA = ice_rdata;
        STATUS_REG:
            PRDATA =
            {
                29'd0,
                error,
                done,
                busy
            };
        default:
            PRDATA = 32'd0;

        endcase
    end
end

endmodule
