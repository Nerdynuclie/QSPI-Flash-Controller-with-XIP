module qspi_decoder
(
    input  wire [79:0] txn_desc,

    output wire        is_read,
    output wire        is_write,
    output wire        erase_en,

    output wire        opcode_en,
    output wire        addr_en,
    output wire        mode_en,
    output wire        dummy_en,
    output wire        data_en,

    output wire [1:0]  addr_SPI_MODE,
    output wire [1:0]  mode_SPI_MODE,
    output wire [1:0]  dummy_SPI_MODE,
    output wire [1:0]  data_SPI_MODE,

    output wire [7:0]  opcode,
    output wire [23:0] address,
    output wire [7:0]  mode_byte,
    output wire [7:0]  dummy_cycles,
    output wire [15:0] data_len
);

assign is_read         = txn_desc[79];
assign is_write        = txn_desc[78];
assign erase_en        = txn_desc[77];

assign opcode_en       = txn_desc[76];
assign addr_en         = txn_desc[75];
assign mode_en         = txn_desc[74];
assign dummy_en        = txn_desc[73];
assign data_en         = txn_desc[72];

assign addr_SPI_MODE   = txn_desc[71:70];
assign mode_SPI_MODE   = txn_desc[69:68];
assign dummy_SPI_MODE  = txn_desc[67:66];
assign data_SPI_MODE   = txn_desc[65:64];

assign opcode          = txn_desc[63:56];

assign address         = txn_desc[55:32];

assign mode_byte       = txn_desc[31:24];

assign dummy_cycles    = txn_desc[23:16];

assign data_len        = txn_desc[15:0];

endmodule