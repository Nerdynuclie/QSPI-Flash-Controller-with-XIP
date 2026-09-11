module tx_shift #(parameter MAX_WIDTH = 32)( 
    //Global signals
    input  wire                 SCLK,
    input  wire                 RESETn,
    //Reister o/p
    input  wire [MAX_WIDTH-1:0] tx_data,
    input  wire [5:0]           tx_len,
    //QSPI_FSM o/p
    input  wire  [1:0]          MODE,
    input  wire                 load,
    input  wire                 shift_en,
    //o/p
    output reg   [3:0]          io_out,
    output reg                  busy,
    output reg                  done             
);
//MODES
localparam MODE_SINGLE = 2'b00;
localparam MODE_DUAL   = 2'b01;
localparam MODE_QUAD   = 2'b10;
// registers
reg [MAX_WIDTH-1:0]     shift_reg;
reg [5:0]               bit_count;

//Transmitter shift register logic block
//Launching the parallel data from cpu and coverting it to serial data for flash
always @ (posedge SCLK or negedge RESETn) begin
    if(!RESETn) begin                       //Asynchronous reset 
        //Clearing all registers
        io_out      <= 4'bzzzz;            
        busy        <= 1'b0;
        done        <= 1'b1;
        shift_reg   <= {MAX_WIDTH{1'b0}};
        bit_count   <= 6'd0;
    end

    else begin
        done <= 1'b0;               //tx_done flag 
        //LOAD
        if(load) begin              //if load enable load the data in the shift register and length in bit_counter
            if(tx_len >= MAX_WIDTH)begin
                shift_reg <= tx_data;
            end
            else begin
                shift_reg <= tx_data << (MAX_WIDTH - tx_len);
            end
            bit_count <= tx_len; 
            if(tx_len==0) begin     //length is zero enable done flag
                busy <= 1'b0;
                done <= 1'b1;
            end
            else begin              //if length is valid raise busy flag
                busy  <= 1'b1;
                done  <= 1'b0;
            end
        end
        
        //shift data
        else if (shift_en && busy) begin      //if shift enable based on the mode shift the data
            case(MODE) 
                //MODE_SINGLE: only 1 bit per cycle so right shift 1 time per cycle
                MODE_SINGLE: begin
                    io_out    <= {3'b000, shift_reg[MAX_WIDTH-1]};
                    shift_reg <= {shift_reg[MAX_WIDTH-2:0],1'b0};
                    if(bit_count == 1) begin
                        bit_count <= 0;
                        busy      <= 0;
                        done      <= 1;
                    end
                    else begin
                        bit_count <= bit_count - 1;
                    end
                 end
                //MODE_DUAL: 2 bits per cycle uses teo IO ports of qsi
                MODE_DUAL:begin
                    io_out    <= {2'b00, shift_reg[MAX_WIDTH-1 -: 2]};
                    shift_reg <= {shift_reg[MAX_WIDTH-3:0],2'b00};    //shifts 2 bit rights per cycle with zeros
                    if(bit_count >= 2) begin                                //till the bitt counter hits 2 shift and assign to IO and raise busy flag
                        bit_count<= bit_count - 6'd2;       
                    end 
                    if(bit_count <= 2) begin                                //if bit counter hits 2 the tranmission is done set the done flag
                        busy <= 1'b0;
                        done <= 1'b1;  
                    end
                end
                //MODE_QUAD: $ bits per cycle uses all the IO ports of the QSPI
                MODE_QUAD:begin
                    io_out    <= shift_reg[MAX_WIDTH-1 -: 4];
                    shift_reg <= {shift_reg[MAX_WIDTH-5:0],4'b0000}; //shift 4 bit right with zeros per cycle
                    if(bit_count >= 4) begin                                //till count reaches 4 shift the data and set busy flag
                        bit_count <= bit_count - 6'd4;  
                    end
                    if(bit_count <= 4)begin                                 //once counter reaches 4 the tranmission is done set done flag
                        busy <= 1'b0;
                        done <= 1'b1;   
                    end
                end
                default:begin
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end

        //when load and shift are disabled
        else begin
            io_out      <= 4'bzzzz;
        end
    end
end
endmodule