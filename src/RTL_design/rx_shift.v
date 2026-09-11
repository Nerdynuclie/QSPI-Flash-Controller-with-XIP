module rx_shift #(parameter MAX_WIDTH = 32)(
    //Global Signal
    input  wire                 SCLK,
    input  wire                 RESETn,
    //FSM O/P
    input  wire                 load,
    input  wire                 shift_en,
    input  wire  [1:0]          MODE,
    input  wire  [5:0]          rx_len,
    //QSPI IO
    input  wire  [3:0]          io_in,
    //Output
    output reg [MAX_WIDTH-1:0] rx_data,
    output reg                 done,
    output reg                 busy

);
//SPI MODES 
localparam MODE_SINGLE = 2'b00;
localparam MODE_DUAL   = 2'b01;
localparam MODE_QUAD   = 2'b10;

//Shift register
reg [MAX_WIDTH-1:0] shift_reg;
//bit counter 
reg [15:0]           bit_count;

//Recieve shift register logic 
//Capturing serial data from QSPI IO lines and converting it into parallel data
always @ (negedge SCLK or negedge RESETn) begin
    if(!RESETn) begin                   //Asynchronous Active low reset
        //clearing all the registers
        shift_reg <= {MAX_WIDTH{1'b0}}; 
        rx_data   <= {MAX_WIDTH{1'b0}};
        bit_count <= 6'd0;
        busy      <= 1'b0;
        done      <= 1'b0;
    end 
    else begin 
        done <= 1'b0;   //intializing done as zero
        if(load) begin                      //when load data comes setting the register to its initial values
             shift_reg <= {MAX_WIDTH{1'b0}};
             bit_count <= rx_len*8;           // Load number of bits to receive
             busy      <= 1'b1;             // set busy flag 
             done      <= 1'b0;
        end

        //SHIFT PHASE: Recieve data while shift enable and busy
        else if(shift_en && busy) begin    

            case(MODE) 
            //SINGLE SPI MODE 
            //1-bit per SCLK cycle from IO_0
                MODE_SINGLE: begin
                    //Shifting incoming bit into LSB of shift register
                    shift_reg   <= { shift_reg[MAX_WIDTH-2:0],io_in[1]};

                    //Decrementing Bit counter 
                    if(bit_count >1) begin
                        bit_count <= bit_count - 16'd1;
                    end

                    //reception completed
                    if(bit_count <=1) begin
                        rx_data <= {shift_reg[MAX_WIDTH-2:0],io_in[1]}; //assigning the data to the o/p reg
                        busy    <= 1'b0;
                        done    <= 1'b1;                                //set done flag
                    end
                end

            //DUAL SPI MODE
            //2-bit per SCLK Cycle from IO_0 and IO_1
                MODE_DUAL: begin
                    //Shifting incoming 2 bits into register 
                    shift_reg   <= {shift_reg[MAX_WIDTH-3:0],io_in[1:0]};

                    //Decrementing remaining bit count 
                    if(bit_count >2)begin
                        bit_count <= bit_count - 16'd2;
                    end

                    //reception completed 
                    if(bit_count <=2) begin
                        rx_data <= {shift_reg[MAX_WIDTH-3:0], io_in[1:0]};  //assigning the data to the o/p reg
                        busy    <= 1'b0;
                        done    <= 1'b1;                                    //set done flag
                    end
                end

            //QUAD SPI MODE
            //4-bit per SCLK cycle From all IO (IO_0 to IO_3)
                MODE_QUAD: begin
                    //Shifting incoming 4 bits into register
                    shift_reg   <= {shift_reg[MAX_WIDTH-5:0],io_in[3:0]};

                    //decrementing remaining bit count
                    if(bit_count >4)begin
                        bit_count <= bit_count - 16'd4;
                    end

                    //reception completed 
                    if(bit_count <=4) begin
                        rx_data <= {shift_reg[MAX_WIDTH-5:0], io_in[3:0]};  //assigning the shifted data to o/p reg
                        busy    <= 1'b0;
                        done    <= 1'b1;                                    //set the done flag    
                    end
                end

                //default mode
                default: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            endcase       
        end
    end
end
endmodule