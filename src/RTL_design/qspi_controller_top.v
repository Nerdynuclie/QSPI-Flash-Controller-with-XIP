module qspi_controller_top
#(
    parameter MAX_WIDTH = 32
)
(
    //--------------------------------------------------
    // Global Signals
    //--------------------------------------------------
    input  wire         SCLK,
    input  wire         RESETn,

    //--------------------------------------------------
    // Arbiter Interface
    //--------------------------------------------------
    input  wire         start,
    input  wire         is_read,
    input  wire         is_write,
    input  wire         erase_en,
    input  wire         opcode_en,
    input  wire         addr_en,
    input  wire         mode_en,
    input  wire         dummy_en,
    input  wire         data_en,
    input  wire [1:0]   addr_SPI_MODE,
    input  wire [1:0]   mode_SPI_MODE,
    input  wire [1:0]   dummy_SPI_MODE,
    input  wire [1:0]   data_SPI_MODE,

    input  wire [7:0]   opcode,
    input  wire [23:0]  address,
    input  wire [7:0]   mode_byte,
    input  wire [7:0]   dummy_cycles,
    input  wire [15:0]  data_len,
    input  wire [31:0]  write_data,
    //--------------------------------------------------
    // Flash Interface
    //--------------------------------------------------
    inout  wire [3:0]   io,
    output wire         cs_n,
    //--------------------------------------------------
    // Status
    //--------------------------------------------------
    output wire [31:0]  read_data,
    output wire         busy,
    output wire         done,
    output wire         error
);

//===================================================
//Flash Interface Signal
//===================================================
wire [3:0] io_in;
wire [3:0] io_out;
wire [3:0] io_oe;



//====================================================
// FSM Signals
//====================================================

wire        load_wren;
wire        load_opcode;
wire        load_addr;
wire        load_mode;
wire        load_data;
wire        load_status;

wire        tx_shift_en;
wire        rx_load;
wire        rx_shift_en;

wire [3:0]  ioen;
wire [1:0]  SPI_MODE;


//====================================================
// TX/RX Status
//====================================================

wire tx_done;
wire tx_busy;

wire rx_done;
wire rx_busy;


//====================================================
// Status Register Read Data
//====================================================

wire wip;
assign wip = read_data[0];


//====================================================
// TX Data Mux
//====================================================

reg [MAX_WIDTH-1:0] tx_data;
reg [5:0]           tx_len;

//--------------------------------------------------
// QSPI Bidirectional IO
//--------------------------------------------------

assign io_in = io;

assign io[0] = io_oe[0] ? io_out[0] : 1'bz;
assign io[1] = io_oe[1] ? io_out[1] : 1'bz;
assign io[2] = io_oe[2] ? io_out[2] : 1'bz;
assign io[3] = io_oe[3] ? io_out[3] : 1'bz;

always @(*)
begin
    tx_data = {MAX_WIDTH{1'b0}};
    tx_len  = 6'd0;

    if(load_opcode)
    begin
        tx_data = {24'd0, opcode};
        tx_len  = 6'd8;
    end

    else if(load_wren)
    begin
        tx_data = 32'h00000006;   // WREN
        tx_len  = 6'd8;
    end

    else if(load_addr)
    begin
        tx_data = address;
        tx_len  = 6'd24;
    end

    else if(load_mode)
    begin
        tx_data = {24'd0, mode_byte};
        tx_len  = 6'd8;
    end

    else if(load_data)
    begin
        tx_data = write_data;
        tx_len  = data_len[5:0];
    end

    else if(load_status)
    begin
        tx_data = 32'h00000005;   // RDSR1
        tx_len  = 6'd8;
    end
end


//====================================================
// FSM
//====================================================

qspi_fsm u_fsm
(
    .SCLK            (SCLK),
    .RESETn          (RESETn),

    .START           (start),
    .data_len        (data_len),
    .READ_EN         (is_read),
    .WRITE_EN        (is_write),
    .ERASE_EN        (erase_en),

    .OPCODE_EN       (opcode_en),
    .ADDR_EN         (addr_en),
    .MODE_EN         (mode_en),
    .DUMMY_EN        (dummy_en),
    .DATA_EN         (data_en),

    .addr_SPI_MODE   (addr_SPI_MODE),
    .mode_SPI_MODE   (mode_SPI_MODE),
    .dummy_SPI_MODE  (dummy_SPI_MODE),
    .data_SPI_MODE   (data_SPI_MODE),

    .DUMMY_CYCLE     (dummy_cycles),

    .tx_done         (tx_done),

    .rx_done         (rx_done),

    .WIP             (wip),

    .load_wren       (load_wren),
    .load_opcode     (load_opcode),
    .load_addr       (load_addr),
    .load_mode       (load_mode),
    .load_data       (load_data),
    .load_status     (load_status),

    .Tx_Shift        (tx_shift_en),
    .Rx_Load         (rx_load),
    .Rx_Shift        (rx_shift_en),
    .SPI_MODE         (SPI_MODE),


    .Ioen            (ioen),

    .CS_n            (cs_n),

    .Busy            (busy),
    .Done            (done),
    .Error           (error)
);


//====================================================
// TX LOAD
//====================================================

wire tx_load;

assign tx_load =
       load_wren   |
       load_opcode |
       load_addr   |
       load_mode   |
       load_data   |
       load_status;


//====================================================
// TX SHIFT
//====================================================

tx_shift
#(
    .MAX_WIDTH(MAX_WIDTH)
)
u_tx_shift
(
    .SCLK       (SCLK),
    .RESETn     (RESETn),

    .tx_data    (tx_data),
    .tx_len     (tx_len),

    .MODE       (SPI_MODE),

    .load       (tx_load),
    .shift_en   (tx_shift_en),

    .io_out     (io_out),

    .busy       (tx_busy),
    .done       (tx_done)
);


//====================================================
// RX SHIFT
//====================================================

rx_shift
#(
    .MAX_WIDTH(MAX_WIDTH)
)
u_rx_shift
(
    .SCLK       (SCLK),
    .RESETn     (RESETn),
    .load       (rx_load),
    .shift_en   (rx_shift_en),
    .MODE       (SPI_MODE),
    .rx_len     (data_len[5:0]),
    .io_in      (io_in),
    .rx_data    (read_data),
    .done       (rx_done),
    .busy       (rx_busy)
);


//====================================================
// IO Enable
//====================================================

assign io_oe = ioen;

endmodule