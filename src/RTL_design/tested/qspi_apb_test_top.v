module qspi_apb_test_top
(
    input  wire         PCLK,
    input  wire         PRESETn,

    // APB
    input  wire         PSEL,
    input  wire         PENABLE,
    input  wire         PWRITE,
    input  wire [7:0]   PADDR,
    input  wire [31:0]  PWDATA,
    output wire [31:0]  PRDATA,

    // QSPI IO
    inout  wire [3:0]   io,
    output wire         cs_n
);

//====================================================
// APB -> ICE
//====================================================

wire start;

wire is_read;
wire is_write;
wire erase_en;

wire opcode_en;
wire addr_en;
wire mode_en;
wire dummy_en;
wire data_en;

wire [1:0] addr_mode;
wire [1:0] mode_mode;
wire [1:0] dummy_mode;
wire [1:0] data_mode;

wire [7:0] opcode;
wire [23:0] address;
wire [7:0] mode_byte;
wire [7:0] dummy_cycles;
wire [15:0] data_len;

wire start_qspi;
//====================================================
// Status
//====================================================

wire busy;
wire done;
wire error;

//====================================================
// TX FIFO
//====================================================

wire        tx_fifo_wr_en;
wire [31:0] tx_fifo_wdata;

wire        tx_fifo_rd_en;
wire [31:0] tx_fifo_rdata;

wire        tx_fifo_full;
wire        tx_fifo_empty;

//====================================================
// RX FIFO
//====================================================

wire        rx_fifo_wr_en;
wire [31:0] rx_fifo_wdata;

wire        rx_fifo_rd_en;
wire [31:0] rx_fifo_rdata;

wire        rx_fifo_full;
wire        rx_fifo_empty;

//====================================================
// ICE
//====================================================

wire [31:0] ice_rdata;

//====================================================
// CMD FIFO
//====================================================

wire        cmd_fifo_wr_en;
wire [79:0] cmd_fifo_wdata;

wire [79:0] cmd_fifo_rdata;

wire        cmd_fifo_full;
wire        cmd_fifo_empty;



//====================================================
// Decoder Outputs
//====================================================
wire        cmd_valid;

wire        dec_is_read;
wire        dec_is_write;
wire        dec_erase_en;

wire        dec_opcode_en;
wire        dec_addr_en;
wire        dec_mode_en;
wire        dec_dummy_en;
wire        dec_data_en;

wire [1:0]  dec_addr_mode;
wire [1:0]  dec_mode_mode;
wire [1:0]  dec_dummy_mode;
wire [1:0]  dec_data_mode;

wire [7:0]  dec_opcode;
wire [23:0] dec_address;
wire [7:0]  dec_mode_byte;
wire [7:0]  dec_dummy_cycles;
wire [15:0] dec_data_len;

//====================================================
// QSPI
//====================================================

wire [31:0] qspi_read_data;
wire        qspi_busy;
wire        qspi_done;
wire        qspi_error;


//====================================================
//CLK DIV
//====================================================
wire        spi_clk;
wire        sample_edge;
wire        shift_edge;

wire [22:0] divider_cfg;
wire        cpol_cfg;
wire        cpha_cfg;
wire cmd_fifo_rd_en;
reg  cmd_fifo_rd_en_r;
reg  cmd_read_pending;


reg [79:0] txn_desc_reg;

wire spi_clk_enable;

//=====================================================
//RESET SYNC  (spi_clk domain)
//=====================================================
wire spi_rst_n;

reset_sync u_reset_sync_spi
(
    .clk         (spi_clk),
    .async_rst_n (PRESETn),
    .sync_rst_n  (spi_rst_n)
);

//==========================================
// cmd_fifo read-capture FSM
// (lives entirely in spi_clk domain - this logic reads
//  cmd_fifo_rdata, and u_cmd_fifo's read port is on spi_clk,
//  so the capture logic must be clocked here, not on PCLK)
//
// start_pulse_spi is generated in the SAME always block, the
// cycle txn_desc_reg becomes valid. Since cmd_fifo_rd_en_r,
// this capture FSM, and u_qspi are ALL in the spi_clk domain,
// no PCLK<->spi_clk crossing is needed for start at all - it
// was only needed back when cmd_fifo_rd_en_r lived on PCLK.
//==========================================
reg start_pulse_spi_r;

always @(posedge spi_clk or negedge spi_rst_n)
begin
    if(!spi_rst_n)
    begin
        cmd_read_pending  <= 1'b0;
        txn_desc_reg      <= 80'd0;
        start_pulse_spi_r <= 1'b0;
    end
    else
    begin
        start_pulse_spi_r <= 1'b0;   // default: single-cycle pulse

        if(cmd_fifo_rd_en)
        begin
            cmd_read_pending <= 1'b1;
        end
        else if(cmd_read_pending)
        begin
            txn_desc_reg      <= cmd_fifo_rdata;
            cmd_read_pending  <= 1'b0;
            start_pulse_spi_r <= 1'b1;   // fire once txn_desc_reg is valid
        end
    end
end

wire start_pulse_spi;
assign start_pulse_spi = start_pulse_spi_r;

//==============================
// qspi_done : spi_clk -> PCLK synchronizer + edge detect
//==============================
wire qspi_done_sync;

two_ff_sync sync_done
(
    .clk  (PCLK),
    .rst  (PRESETn),
    .din  (qspi_done),
    .dout (qspi_done_sync)
);

reg qspi_done_d;

always @(posedge PCLK or negedge PRESETn)
begin
    if(!PRESETn)
        qspi_done_d <= 1'b0;
    else
        qspi_done_d <= qspi_done_sync;
end

wire qspi_done_pulse;

assign qspi_done_pulse =
       qspi_done_sync &
      ~qspi_done_d;

//========================================
// qspi_busy : spi_clk -> PCLK synchronizer
//========================================
wire qspi_busy_pclk_sync;

two_ff_sync sync_busy
(
    .clk  (PCLK),
    .rst  (PRESETn),
    .din  (qspi_busy),
    .dout (qspi_busy_pclk_sync)
);

//====================================================
// cmd_fifo read-request generation (spi_clk domain,
// matches rd_clk of u_cmd_fifo)
//====================================================
assign cmd_fifo_rd_en = cmd_fifo_rd_en_r;

always @(posedge spi_clk or negedge spi_rst_n)
begin
    if(!spi_rst_n)
        cmd_fifo_rd_en_r <= 1'b0;
    else
        cmd_fifo_rd_en_r <= (!cmd_fifo_empty &&
                             !qspi_busy &&
                             !cmd_read_pending);
end


assign divider_cfg = 23'd4;
assign cpol_cfg    = 1'b0;
assign cpha_cfg    = 1'b0;


clk_div u_clk_div
(
    .PCLK           (PCLK),
    .PRESETn        (PRESETn),

    .DIVIDER        (divider_cfg),
    .EN             (1'b1),

    .SPI_BUSY       (1'b1),

    .CPOL           (cpol_cfg),
    .CPHA           (cpha_cfg),

    .SCLK           (spi_clk)
);


//=====================================================

//====================================================
// APB REGBANK
//====================================================

qspi_apb_regbank u_apb
(
    .PCLK           (PCLK),
    .PRESETn        (PRESETn),

    .PSEL           (PSEL),
    .PENABLE        (PENABLE),
    .PWRITE         (PWRITE),
    .PADDR          (PADDR),
    .PWDATA         (PWDATA),
    .PRDATA         (PRDATA),

    .tx_fifo_wr_en  (tx_fifo_wr_en),
    .tx_fifo_wdata  (tx_fifo_wdata),

    .tx_fifo_full   (tx_fifo_full),

    .start          (start),

    .is_read        (is_read),
    .is_write       (is_write),
    .erase_en       (erase_en),

    .opcode_en      (opcode_en),
    .addr_en        (addr_en),
    .mode_en        (mode_en),
    .dummy_en       (dummy_en),
    .data_en        (data_en),

    .addr_mode      (addr_mode),
    .mode_mode      (mode_mode),
    .dummy_mode     (dummy_mode),
    .data_mode      (data_mode),

    .opcode         (opcode),
    .address        (address),
    .mode_byte      (mode_byte),
    .dummy_cycles   (dummy_cycles),
    .data_len       (data_len),

    .ice_rdata      (ice_rdata),

    .busy           (busy),
    .done           (done),
    .error          (error)
);

//====================================================
// ICE
//====================================================

qspi_ice u_ice
(
    .clk            (PCLK),
    .rst_n          (PRESETn),

    .start          (start),

    .is_read        (is_read),
    .is_write       (is_write),
    .erase_en       (erase_en),

    .opcode_en      (opcode_en),
    .addr_en        (addr_en),
    .mode_en        (mode_en),
    .dummy_en       (dummy_en),
    .data_en        (data_en),

    .addr_mode      (addr_mode),
    .mode_mode      (mode_mode),
    .dummy_mode     (dummy_mode),
    .data_mode      (data_mode),

    .opcode         (opcode),
    .address        (address),
    .mode_byte      (mode_byte),
    .dummy_cycles   (dummy_cycles),
    .data_len       (data_len),

    .cmd_fifo_full  (cmd_fifo_full),

    .cmd_fifo_wr_en (cmd_fifo_wr_en),
    .cmd_fifo_wdata (cmd_fifo_wdata),

    .qspi_done      (qspi_done_sync),

    .rx_fifo_rdata  (rx_fifo_rdata),
    .rx_fifo_empty  (rx_fifo_empty),

    .rx_fifo_rd_en  (rx_fifo_rd_en),

    .ice_rdata      (ice_rdata),

    .busy           (busy),
    .done           (done),
    .error          (error)
);

//====================================================
// Command FIFO
//====================================================

async_fifo
#(
    .WIDTH (80),
    .DEPTH (16)
)
u_cmd_fifo
(
    .wr_data    (cmd_fifo_wdata),
    .wr_en      (cmd_fifo_wr_en),
    .wr_clk     (PCLK),
    .wr_rst     (PRESETn),

    .rd_data    (cmd_fifo_rdata),
    .rd_en      (cmd_fifo_rd_en),
    .rd_clk     (spi_clk),
    .rd_rst     (spi_rst_n),

    .fifo_full  (cmd_fifo_full),
    .fifo_empty (cmd_fifo_empty)
);



//====================================================
// TX FIFO
//====================================================

async_fifo
#(
    .WIDTH (32),
    .DEPTH (16)
)
u_tx_fifo
(
    .wr_data    (tx_fifo_wdata),
    .wr_clk     (PCLK),
    .wr_rst     (PRESETn),
    .wr_en      (tx_fifo_wr_en),

    .rd_data    (tx_fifo_rdata),
    .rd_en      (tx_fifo_rd_en),
    .rd_clk     (spi_clk),
    .rd_rst     (spi_rst_n),

    .fifo_full  (tx_fifo_full),
    .fifo_empty (tx_fifo_empty)
);

//====================================================
// RX FIFO
//====================================================

async_fifo
#(
    .WIDTH (32),
    .DEPTH (16)
)
u_rx_fifo
(
    .wr_data    (rx_fifo_wdata),
    .wr_clk     (spi_clk),
    .wr_rst     (spi_rst_n),
    .wr_en      (rx_fifo_wr_en),

    .rd_data    (rx_fifo_rdata),
    .rd_en      (rx_fifo_rd_en),
    .rd_clk     (PCLK),
    .rd_rst     (PRESETn),

    .fifo_full  (rx_fifo_full),
    .fifo_empty (rx_fifo_empty)
);


//====================================================
// TX FIFO READ
// (was gated on undriven 'start_qspi' - now uses the
//  real spi_clk-domain start pulse, matches rd_clk)
//====================================================

assign tx_fifo_rd_en =
       start_pulse_spi &&
       dec_is_write &&
       !tx_fifo_empty;

//====================================================
// RX FIFO WRITE
// (generated natively in spi_clk domain to match
//  u_rx_fifo's wr_clk, instead of using the PCLK-domain
//  qspi_done_pulse)
//====================================================

reg qspi_done_spi_d;

always @(posedge spi_clk or negedge spi_rst_n)
begin
    if(!spi_rst_n)
        qspi_done_spi_d <= 1'b0;
    else
        qspi_done_spi_d <= qspi_done;
end

wire qspi_done_pulse_spi;

assign qspi_done_pulse_spi =
       qspi_done &
      ~qspi_done_spi_d;

assign rx_fifo_wr_en =
       qspi_done_pulse_spi &&
       dec_is_read &&
       !rx_fifo_full;

assign rx_fifo_wdata = qspi_read_data;

//====================================================
// DECODER
//====================================================

qspi_decoder u_decoder
(
    .txn_desc          (txn_desc_reg),

    .is_read           (dec_is_read),
    .is_write          (dec_is_write),
    .erase_en          (dec_erase_en),

    .opcode_en         (dec_opcode_en),
    .addr_en           (dec_addr_en),
    .mode_en           (dec_mode_en),
    .dummy_en          (dec_dummy_en),
    .data_en           (dec_data_en),

    .addr_SPI_MODE     (dec_addr_mode),
    .mode_SPI_MODE     (dec_mode_mode),
    .dummy_SPI_MODE    (dec_dummy_mode),
    .data_SPI_MODE     (dec_data_mode),

    .opcode            (dec_opcode),
    .address           (dec_address),
    .mode_byte         (dec_mode_byte),
    .dummy_cycles      (dec_dummy_cycles),
    .data_len          (dec_data_len)
);




//====================================================
// QSPI CONTROLLER
//====================================================

qspi_controller_top u_qspi
(
    .SCLK           (spi_clk),
    .RESETn         (spi_rst_n),

    .start          (start_pulse_spi),

    .is_read        (dec_is_read),
    .is_write       (dec_is_write),
    .erase_en       (dec_erase_en),

    .opcode_en      (dec_opcode_en),
    .addr_en        (dec_addr_en),
    .mode_en        (dec_mode_en),
    .dummy_en       (dec_dummy_en),
    .data_en        (dec_data_en),

    .addr_SPI_MODE  (dec_addr_mode),
    .mode_SPI_MODE  (dec_mode_mode),
    .dummy_SPI_MODE (dec_dummy_mode),
    .data_SPI_MODE  (dec_data_mode),

    .opcode         (dec_opcode),
    .address        (dec_address),
    .mode_byte      (dec_mode_byte),
    .dummy_cycles   (dec_dummy_cycles),
    .data_len       (dec_data_len),

    .write_data     (tx_fifo_rdata),

    .io             (io),
    .cs_n           (cs_n),

    .read_data      (qspi_read_data),

    .busy           (qspi_busy),
    .done           (qspi_done),
    .error          (qspi_error)
);

endmodule