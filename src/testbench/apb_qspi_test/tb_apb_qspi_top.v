`timescale 1ns/1ps

module tb_apb_qspi_top;

reg         PCLK;
reg         PRESETn;

reg         PSEL;
reg         PENABLE;
reg         PWRITE;
reg  [7:0]  PADDR;
reg  [31:0] PWDATA;

wire [31:0] PRDATA;

//==================================================
// DUT
//==================================================

apb_flash_system DUT
(
    .PCLK      (PCLK),
    .PRESETn   (PRESETn),

    .PSEL      (PSEL),
    .PENABLE   (PENABLE),
    .PWRITE    (PWRITE),
    .PADDR     (PADDR),
    .PWDATA    (PWDATA),

    .PRDATA    (PRDATA)
);

//==================================================
// REGISTER MAP
//==================================================

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

// Number of idle PCLK cycles given to the flash after a WREN
// command completes, so the part has time to internally latch
// the WEL bit before the next command is issued (CS deselect
// to next CS assert setup, tSHSL-style margin).
localparam WREN_SETTLE_CYCLES = 20;

//==================================================
// CLOCK
//==================================================

initial
begin
    PCLK = 0;
    forever #5 PCLK = ~PCLK;
end

//==================================================
// APB WRITE
//==================================================

task apb_write;
input [7:0] addr;
input [31:0] data;
begin

    @(posedge PCLK);

    PSEL    <= 1'b1;
    PENABLE <= 1'b0;
    PWRITE  <= 1'b1;
    PADDR   <= addr;
    PWDATA  <= data;

    @(posedge PCLK);
    PENABLE <= 1'b1;

    @(posedge PCLK);

    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
    PWRITE  <= 1'b0;
    PADDR   <= 8'd0;
    PWDATA  <= 32'd0;

end
endtask

//==================================================
// APB READ
//==================================================

task apb_read;
input  [7:0] addr;
output [31:0] data;
begin

    @(posedge PCLK);

    PSEL    <= 1'b1;
    PENABLE <= 1'b0;
    PWRITE  <= 1'b0;
    PADDR   <= addr;

    @(posedge PCLK);
    PENABLE <= 1'b1;

    @(posedge PCLK);

    data = PRDATA;

    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
    PADDR   <= 8'd0;

end
endtask

//==================================================
// WAIT DONE
//==================================================

task wait_done;
reg [31:0] status;
integer timeout;
begin

    status  = 0;
    timeout = 0;

    while(status[1] == 0)
    begin

        apb_read(STATUS_REG,status);

        timeout = timeout + 1;

        if(timeout > 50000)
        begin
            $display("[%0t] TIMEOUT",$time);
            $finish;
        end
    end

end
endtask

//==================================================
// READ JEDEC
//==================================================

task read_jedec;
reg [31:0] id;
begin

    $display("\nREAD JEDEC");

    apb_write(OPCODE_REG,{23'd0,1'b1,8'h9F});

    apb_write(DATALEN_REG,
    {
        15'd0,
        1'b1,
        16'd3
    });

    apb_write(CTRL_REG,32'b11);

    wait_done();

    apb_read(RXDATA_REG,id);

    $display("JEDEC ID = %08h",id);

end
endtask

//==================================================
// WREN
// Issues 06h and, once the controller reports done,
// holds the bus idle for WREN_SETTLE_CYCLES so the
// flash has time to actually set its internal WEL bit
// before the next command (erase/program/WRSR) is sent.
//==================================================

task wren;
begin

    $display("\nWREN");

    apb_write(OPCODE_REG,{23'd0,1'b1,8'h06});

    apb_write(CTRL_REG,
    {
        28'd0,
        1'b0,
        1'b0,
        1'b0,
        1'b1
    });

    wait_done();

    // free cycles for WEL to settle inside the flash
    repeat(WREN_SETTLE_CYCLES) @(posedge PCLK);

end
endtask

//==================================================
// READ STATUS
//==================================================

task read_status;
output [31:0] status;
begin

    apb_write(OPCODE_REG,{23'd0,1'b1,8'h05});

    apb_write(DATALEN_REG,
    {
        15'd0,
        1'b1,
        16'd1
    });

    apb_write(CTRL_REG,32'b11);

    wait_done();

    apb_read(RXDATA_REG,status);

    $display("STATUS=%02h",status[7:0]);

end
endtask

//==================================================
// SECTOR ERASE
//==================================================

task sector_erase;
input [23:0] addr;
begin

    $display("\nSECTOR ERASE");

    wren();

    apb_write(OPCODE_REG,{23'd0,1'b1,8'h20});

    apb_write(ADDR_REG,
    {
        7'd0,
        1'b1,
        addr
    });

    apb_write(CTRL_REG,
    {
        28'd0,
        1'b1,
        1'b0,
        1'b0,
        1'b1
    });

    wait_done();

end
endtask

//==================================================
// PAGE PROGRAM
//==================================================

task page_program;
input [23:0] addr;
input [31:0] data;
begin

    $display("\nPAGE PROGRAM");

    wren();

    apb_write(TXDATA_REG,data);

    apb_write(OPCODE_REG,{23'd0,1'b1,8'h02});

    apb_write(ADDR_REG,
    {
        7'd0,
        1'b1,
        addr
    });

    apb_write(DATALEN_REG,
    {
        15'd0,
        1'b1,
        16'd4
    });

    apb_write(CTRL_REG,
    {
        28'd0,
        1'b0,
        1'b1,
        1'b0,
        1'b1
    });

    wait_done();

end
endtask

//==================================================
// FAST READ 0B
//==================================================

task fast_read;
input  [23:0] addr;
output [31:0] data;
begin

    apb_write(OPCODE_REG,{23'd0,1'b1,8'h0B});

    apb_write(ADDR_REG,
    {
        7'd0,
        1'b1,
        addr
    });

    apb_write(DUMMY_REG,
    {
        23'd0,
        1'b1,
        8'd8
    });

    apb_write(DATALEN_REG,
    {
        15'd0,
        1'b1,
        16'd4
    });

    apb_write(CTRL_REG,32'b11);

    wait_done();

    apb_read(RXDATA_REG,data);

end
endtask

//==================================================
// QUAD MODE ENABLE SEQUENCE
// WREN -> WRSR(01h) with QE=1 (data=0x40) -> done.
// Call this immediately before ANY quad-lane operation
// (QIOR, QPP, etc). WREN internally settles WEL before
// the WRSR command is issued, and this task in turn
// waits for the WRSR cycle to complete before returning,
// so the caller can safely issue the quad command next.
//==================================================

task quad_mode_enable;
begin

    $display("\nQUAD MODE ENABLE SEQUENCE (WREN + WRSR QE=1)");

    wren();

    apb_write(OPCODE_REG,{23'd0,1'b1,8'h01});

    apb_write(TXDATA_REG,32'h00000040);

    apb_write(DATALEN_REG,
    {
        15'd0,
        1'b1,
        16'd1
    });

    apb_write(CTRL_REG,
    {
        28'd0,
        1'b0,   // erase
        1'b1,   // write
        1'b0,   // read
        1'b1    // start
    });

    wait_done();

    $display("QE BIT SET (QUAD MODE ENABLED)");

end
endtask

//==================================================
// QIOR EB
//==================================================

task qior_read;
input  [23:0] addr;
output [31:0] data;
begin

    apb_write(MODECFG_REG,
    {
        24'd0,
        2'b10,
        2'b00,
        2'b00,
        2'b10
    });

    apb_write(OPCODE_REG,{23'd0,1'b1,8'hEB});

    apb_write(ADDR_REG,
    {
        7'd0,
        1'b1,
        addr
    });

    apb_write(MODEBYTE_REG,
    {
        23'd0,
        1'b1,
        8'h00
    });

    apb_write(DUMMY_REG,
    {
        23'd0,
        1'b1,
        8'd6
    });

    apb_write(DATALEN_REG,
    {
        15'd0,
        1'b1,
        16'd4
    });

    apb_write(CTRL_REG,32'b11);

    wait_done();

    apb_read(RXDATA_REG,data);

end
endtask

//==================================================
// RESET
//==================================================

initial
begin

    PSEL    = 0;
    PENABLE = 0;
    PWRITE  = 0;
    PADDR   = 0;
    PWDATA  = 0;

    PRESETn = 0;

    repeat(20) @(posedge PCLK);

    PRESETn = 1;

end

//==================================================
// MAIN TEST
//==================================================

reg [31:0] wr_data;
reg [31:0] rd_data;
reg [31:0] status;

initial
begin

    wait(PRESETn);

    #1000000;

    //---------------------------------------
    // RDID
    //---------------------------------------

    read_jedec();

    //---------------------------------------
    // RDSR
    //---------------------------------------

    read_status(status);

    //---------------------------------------
    // ERASE
    //---------------------------------------

    sector_erase(24'h000100);

    repeat(10)
        read_status(status);

    //---------------------------------------
    // PROGRAM
    //---------------------------------------

    wr_data = 32'hDEADBEEF;

    page_program
    (
        24'h000100,
        wr_data
    );

    repeat(10)
        read_status(status);

    //---------------------------------------
    // FAST READ
    //---------------------------------------

    fast_read
    (
        24'h000100,
        rd_data
    );

    $display("\nFAST READ DATA = %08h",rd_data);

    if(rd_data == wr_data)
        $display("FAST READ PASS");
    else
        $display("FAST READ FAIL");

    //---------------------------------------
    // QIOR READ (quad op #1)
    // Every quad-lane op is preceded by its own
    // WREN + WRSR(QE=1) sequence.
    //---------------------------------------

    quad_mode_enable();

    repeat(10)
        read_status(status);

    qior_read
    (
        24'h000100,
        rd_data
    );

    $display("\nQIOR DATA = %08h",rd_data);

    if(rd_data == wr_data)
        $display("QIOR PASS");
    else
        $display("QIOR FAIL");

    //---------------------------------------
    // Example: a second quad op later in the
    // test would repeat the same pattern:
    //
    //   quad_mode_enable();
    //   repeat(10) read_status(status);
    //   qior_read(<addr>, rd_data);
    //---------------------------------------

    //---------------------------------------
    // END
    //---------------------------------------

    $display("\nTEST COMPLETE");

    #10000;

    $finish;

end

//==================================================
// DEBUG
//==================================================

always @(posedge DUT.u_apb_test_top.spi_clk)
begin

    if(DUT.u_apb_test_top.qspi_done)
        $display("[%0t] QSPI DONE",$time);

    if(DUT.u_apb_test_top.cmd_fifo_wr_en)
        $display("[%0t] CMD FIFO WRITE %h",
                 $time,
                 DUT.u_apb_test_top.cmd_fifo_wdata);

end

//==================================================
// WAVES
//==================================================

initial
begin
    $dumpfile("flash_full.vcd");
    $dumpvars(0,tb_flash_full);
end

endmodule
