module qspi_fsm(
    input  wire        SCLK,
    input  wire        RESETn,
    input  wire        START,
    // Decoder Outputs
    input  wire [1:0]   addr_SPI_MODE,
    input  wire [1:0]   mode_SPI_MODE,
    input  wire [1:0]   dummy_SPI_MODE,
    input  wire [1:0]   data_SPI_MODE,
    input  wire [15:0]  data_len,
    input  wire         READ_EN,
    input  wire         WRITE_EN,
    input  wire         ERASE_EN,
    input  wire [7:0]  DUMMY_CYCLE,
    input  wire        OPCODE_EN,
    input  wire        ADDR_EN,
    input  wire        DATA_EN,
    input  wire        DUMMY_EN,
    input  wire        MODE_EN,
    //input  wire        OPCODE_ERROR,
    // Shift Engines
    input  wire        tx_done,
    input  wire        rx_done,
    input  wire        tx_busy,
    input  wire        rx_busy,
    // Status Register
    input  wire        WIP,
    // TX Controls
    output reg         load_wren,
    output reg         load_opcode,
    output reg         load_addr,
    output reg         load_data,
    output reg         load_status,
    output reg         load_mode,
    output reg         Tx_Shift,
    // RX Controls
    output reg         Rx_Load,
    output reg         Rx_Shift,
    output reg [1:0]   SPI_MODE,
    // QSPI
    output reg [3:0]   Ioen,
    output wire         CS_n,
    output wire         SCLK_OUT,
    output wire         RESETn_OUT,
    // Status
    output reg         Busy,
    output reg         Done,
    output reg         Error
);


// SPI Modes
localparam MODE_SINGLE = 2'b00;
localparam MODE_DUAL   = 2'b01;
localparam MODE_QUAD   = 2'b10;

// FSM States
localparam IDLE         = 4'd0;
localparam SHIFT_OPCODE = 4'd1;
localparam SHIFT_ADDR   = 4'd2;
localparam SHIFT_MODE   = 4'd3;
localparam DUMMY_STATE  = 4'd4;
localparam SHIFT_DATA   = 4'd5;
localparam READ_DATA    = 4'd6;
localparam ERASE_STATE  = 4'd7;
localparam STATUS_READ  = 4'd8;
localparam DONE_STATE   = 4'd9;
localparam SHIFT_WREN   = 4'd10;
localparam SHIFT_STATUS = 4'd11;


//FSM reg
reg [3:0] current_state;
reg [3:0] next_state;
reg [3:0] prev_state;
reg [7:0] dummy_count;
//reg [1:0] MODE;
wire dummy_done;

//cs_n delay
reg cs_n_r;
reg next_cs_n;

always @(posedge SCLK or negedge RESETn)
begin
    if(!RESETn) begin
        cs_n_r    <= 1'b1;
    end
    else
        cs_n_r <= next_cs_n;
end

assign CS_n = cs_n_r;
//FSM sequential
always @(posedge SCLK or negedge RESETn)
begin
    if(!RESETn) begin
        current_state <= IDLE;
        prev_state    <= IDLE;
    end 
    else begin
        current_state <= next_state;
        prev_state    <= current_state;
    end
end

//Dummy cycle counter generates dummy cycle
always @(posedge SCLK or negedge RESETn)
begin
    if(!RESETn)
        dummy_count <= 4'd0;
    else if(current_state != DUMMY_STATE)
        dummy_count <= 4'd0;
    else
        dummy_count <= dummy_count + 1'b1;
end

assign dummy_done = (dummy_count == (DUMMY_CYCLE-1'b1));

// FSM next_state STATE LOGIC
/*
QSPI FSM
Flow:
1. Receive decoded command information from qspi_decoder.
2. For WRITE and ERASE operations:
    WREN (0x06) -> Actual Command
3. Send opcode.
4. Send address if required.
5. Insert dummy cycles if required.
6. Send write data or receive read data.
7. For erase operations:
    Poll Status Register (RDSR1)
    until WIP bit becomes 0.
8. Assert Done when transaction completes.

The FSM also handles:
- Dummy cycle generation
- Flash busy polling        (WIP)
- Write enable sequencing   (WREN --> PP/SE)
*/
always @(*)
begin
    next_state = current_state;
    case(current_state)
        IDLE: begin
            if(START) begin
                if((WRITE_EN) || (ERASE_EN)) begin
                    next_state = SHIFT_WREN;
                end
                else begin
                    if(OPCODE_EN)
                    next_state = SHIFT_OPCODE;
                end
            end
            else
                next_state = IDLE;
        end

        // this state loads the Write Enable (WREN) opcode (06h) into the TX shift register.
        // flash memories require a WREN command before any PP(0x02) or SE(0x20)
        // without this command the flash ignores write/erase requests.


        // sends the WREN opcode to the flash.
        // Once transmission is complete, the FSM proceeds to send the actual command opcode.
        SHIFT_WREN: begin
            if(tx_done)     next_state = SHIFT_OPCODE;
            else            next_state = SHIFT_WREN;
        end

        // sends the opcode to the flash.
        //Once transmission is complete based on operation it proceeds to next state
        SHIFT_OPCODE: begin
            if(tx_done)
            begin
                if(ADDR_EN) begin
                    next_state = SHIFT_ADDR;
                end
                else if((READ_EN)&& DATA_EN)   begin   //operation is read proceed to read state
                    next_state = READ_DATA;
                end

                else if(WRITE_EN&& DATA_EN)  begin//operation is write proceed to write state
                    next_state = SHIFT_DATA;
                end

                else if((ERASE_EN) && !DATA_EN) begin //operation is erase proceed to write
                    next_state = ERASE_STATE;
                end
                else begin
                    next_state = DONE_STATE;             //operation is control (WREN) then proceed to done state 
                end
            end
            else begin        //opcode still sending (tx_busy)
                next_state = SHIFT_OPCODE; 
            end             
        end 

        // sends the address to the flash.
        //Once transmission is complete based on operation it proceeds to next state        
        SHIFT_ADDR: begin
            if(tx_done)
            begin
                if(MODE_EN)
                    next_state = SHIFT_MODE;
                else if(DUMMY_EN) begin                   //if dummy cycle are needed for the operation (FAST_READ (0x0B) and QIOR(0xEB)) proceed to dummy cycke state 
                    next_state = DUMMY_STATE;
                end
                else if((READ_EN) && DATA_EN) begin
                    next_state = READ_DATA;
                end
                else if((WRITE_EN) && DATA_EN) begin
                    next_state = SHIFT_DATA;
                end
                else if((ERASE_EN) && !DATA_EN) begin
                    next_state = ERASE_STATE;
                end

                else begin
                    next_state = DONE_STATE;
                end
            end
            else begin                  //sending address (tx_busy)
                next_state = SHIFT_ADDR;
            end
        end

        SHIFT_MODE: begin
            if(tx_done) begin
                if(DUMMY_EN)
                    next_state = DUMMY_STATE;
                else if((READ_EN) && DATA_EN)
                    next_state = READ_DATA;
                else if((WRITE_EN) && DATA_EN)
                    next_state = SHIFT_DATA;
                else if((ERASE_EN) && !DATA_EN)
                    next_state = ERASE_STATE;
                else
                    next_state = DONE_STATE;
            end
            else 
                next_state = SHIFT_MODE;
            end
        
        //waits dummy counter to finish count the and after that proceeds to next states 
        DUMMY_STATE: begin
            if(dummy_done) begin        //if dummy counter done proceed to next state
                if(READ_EN)    begin
                    next_state = READ_DATA;
                end
                else begin
                    next_state = DONE_STATE;
                end
            end
            else begin //dummy cycles (dummy counter not done)
                next_state = DUMMY_STATE;
            end
        end

        //sends the data to the flash.
        //Once transmission is complete based on operation it proceeds to next state
        SHIFT_DATA: begin
            if(tx_done) begin
                next_state = SHIFT_STATUS;
            end
            else begin                      //sending Data (tx_busy)
                next_state = SHIFT_DATA;
            end
        end

        SHIFT_STATUS: begin
            if(tx_done) begin
                next_state = READ_DATA;
            end
            else begin
                next_state = SHIFT_STATUS;
            end
        end

        //once data is recieved from flash the operation is done
        READ_DATA: begin
            if(rx_done) begin
                if      (prev_state == SHIFT_DATA || prev_state == ERASE_STATE) next_state = STATUS_READ;
                else                                                            next_state = DONE_STATE;
            end
            else        next_state = READ_DATA;
        end

        //first loads the opcode of RDSR1 (0x05) for polling
        ERASE_STATE: begin
            next_state = SHIFT_STATUS;
        end

        // READ RDSR1 COMMAND
        //continuously monitors the WIP bit in RDSR1 register to check the status of erase
        STATUS_READ: begin
            if(rx_done)
            begin
                if(WIP) next_state = SHIFT_STATUS;     //SECTOR ERASE not done so load the RDSR1 opcode again
                else next_state = DONE_STATE;       //SECTOR ERASE done 
            end
            else
                next_state = STATUS_READ;           //Reading the RDSR1 reg
        end

        DONE_STATE: begin
            next_state = IDLE;
        end


        default: begin
            next_state = IDLE;
        end
    endcase
end

// FSM OUTPUT LOGIC
/*
The FSM OUTPUT generates control signals for:

- TX Shift Engine       (tx_en, tx_shift, tx_load)
- RX Shift Engine       (rx_en, rx_shift, rx_load)
- Chip Select           (CS_n)

*/
always @(*)
begin
    //default values of status flag ,tx and rx controls signals
    load_wren       =1'b0;
    load_opcode     = 1'b0;
    load_addr       = 1'b0;
    load_data       = 1'b0;
    load_status     = 1'b0;
    Tx_Shift        = 1'b0;
    Rx_Load         = 1'b0;
    Rx_Shift        = 1'b0;
    Busy            = 1'b0;
    Done            = 1'b0;
    Error           = 1'b0;
    load_mode       = 1'b0;
    SPI_MODE = MODE_SINGLE;   // <<< ADD THIS
    case(current_state)
        IDLE: begin
            if(START) begin
                if((WRITE_EN) || (ERASE_EN))  load_wren     = 1'b1;
                else begin
                   load_opcode   = 1'b1;
                   Tx_Shift = 1'b1;
                end
            end
            next_cs_n = 1'b1;

        end

        SHIFT_WREN: begin
            if(tx_done) begin
                load_opcode = 1'b1;
            end  
            else begin
            SPI_MODE  = MODE_SINGLE;
            load_wren = 1'b0;   //tx_load disable
            Tx_Shift  = 1'b1;   //tx_shift enable
            Busy      = 1'b1;   
            next_cs_n      = 1'b0;   //keep flash slected
            end

        end
        SHIFT_OPCODE: begin
            if(tx_done) begin
                if(ADDR_EN) begin
                    load_addr = 1'b1;
                end
                else if((READ_EN)&& DATA_EN)   begin   //operation is read proceed to read state
                    Rx_Load = 1'b1;
                end

                else if(WRITE_EN&& DATA_EN)  begin//operation is write proceed to write state
                    load_data = 1'b1;
                end
                else if((ERASE_EN)) 
                    Done = 1'b0;
                else begin
                    Done = 1'b1;
                end
            end
            else begin
                SPI_MODE    = MODE_SINGLE;
                load_opcode = 1'b0;
                Tx_Shift    = 1'b1; //tx_shift enable
                Busy        = 1'b1;
                next_cs_n        = 1'b0;
            end
        end

        SHIFT_ADDR: begin
             if(tx_done)
            begin
                if(MODE_EN) begin
                    load_mode = 1'b1;
                end

                else if((READ_EN) && DATA_EN) begin
                     Rx_Load = 1'b1;
                end

                else if((WRITE_EN) && DATA_EN) begin
                    load_data = 1'b1;
                end
                else if((ERASE_EN))
                    Error = 1'b0;
                else  begin
                    Error = 1'b1;
                end
            end
            else begin
                load_addr   = 1'b0;
                Tx_Shift    = 1'b1; //tx_shift enable
                Busy        = 1'b1;
                next_cs_n        = 1'b0;
                SPI_MODE      = addr_SPI_MODE;
            end
        end

        SHIFT_MODE: begin
             if(tx_done) begin
                if(DUMMY_EN)
                    load_mode = 1'b0;
                else if((READ_EN) && DATA_EN)
                    Rx_Load = 1'b1;
                else if((WRITE_EN) && DATA_EN)
                    load_data = 1'b1;
                else if((ERASE_EN)) begin
                    Error = 1'b0;
                    Done  = 1'b0;
                end
                else begin
                    Error = 1'b1;
                    Done  = 1'b1;
                end
            end
            else begin
                load_mode = 1'b0;
                Tx_Shift  = 1'b1;
                Busy      = 1'b1;
                next_cs_n      = 1'b0;
                SPI_MODE      = mode_SPI_MODE;
            end
        end

        DUMMY_STATE:
        begin
             if(dummy_done) begin        //if dummy counter done proceed to next state
                if(READ_EN)    begin
                    Rx_Load = 1'b1;
                end
                else begin
                    Error=1'b1;
                end
            end
            else begin
                Busy = 1'b1;        //controller busy flag
                next_cs_n = 1'b0;       
            end
        end

        SHIFT_DATA: begin
            if(tx_done) begin
                load_status = 1'b1;
            end
            else begin
                load_data   = 1'b0;     
                Tx_Shift    = 1'b1;     //tx_shift enable
                Busy        = 1'b1;
                next_cs_n        = 1'b0;
                SPI_MODE      = data_SPI_MODE;
            end
        end

        SHIFT_STATUS: begin
            if(tx_done) begin
                Rx_Load = 1'b1;
            end
            else begin
                SPI_MODE      = MODE_SINGLE;
                load_status   = 1'b0;     
                Tx_Shift      = 1'b1;     //tx_shift enable
                Busy          = 1'b1;
                next_cs_n          = 1'b0;
            end
        end

        READ_DATA: begin
            if(rx_done)
            begin
                if(WIP) load_status = 1'b1;     //SECTOR ERASE or write not done so load the RDSR1 opcode again
                else    Done        = 1'b1;       //SECTOR ERASE or write done 
            end
            else begin
                SPI_MODE = data_SPI_MODE;
                Rx_Load  = 1'b0;
                Rx_Shift = 1'b1;      //rx_shift enable
                Busy     = 1'b1;
                next_cs_n     = 1'b0;
            end
        end

        ERASE_STATE: begin
            load_status = 1'b1;
            Busy        = 1'b1;
            next_cs_n        = 1'b0;
        end

        // READ STATUS OPCODE (RDSR1)
        STATUS_READ: begin
            if(rx_done)
            begin
                if(WIP) load_status = 1'b1;     //SECTOR ERASE not done so load the RDSR1 opcode again
                else    Done        = 1'b1;       //SECTOR ERASE done 
            end
            Rx_Load  = 1'b0;
            Rx_Shift = 1'b1;       //monitors the register
            Busy     = 1'b1;
            next_cs_n     = 1'b0;
        end

        DONE_STATE: begin   
            Done        = 1'b1;     // controller done flag
            next_cs_n   = 1'b1;     // chip select deasserted
            load_status = 1'b0;     
            Busy        = 1'b0;     
        end

        default: begin
            load_status = 1'b0;
            SPI_MODE    = MODE_SINGLE;
        end
    endcase
end
/*
The FSM OUTPUT generates control signal for:
- IO Enable Control     (Ioen)
*/

always @(*) begin
        case(SPI_MODE)
            MODE_SINGLE : begin
            if(current_state != READ_DATA && current_state != STATUS_READ) Ioen = 4'b0001;
            else                                                           Ioen = 4'b0010;
            end

            MODE_DUAL :
                Ioen = 4'b0011;

            MODE_QUAD :
                Ioen = 4'b1111;

            default :
                Ioen = 4'b0001;

        endcase
end

//clock and reset signal for FLASH
assign SCLK_OUT     = SCLK;
assign RESETn_OUT   = RESETn;

endmodule