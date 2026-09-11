module gray_to_bin #(
    parameter DEPTH = 8       // Parameterize the bit-width here
) ( g_in, b_out);
    localparam width=$clog2(DEPTH);
    input  wire [width:0] g_in;
    output wire [width:0] b_out;

    assign b_out[width] = g_in[width];

    genvar i;
    generate
        for (i = width-1; i >= 0; i = i - 1) begin : gray2bin_loop
            assign b_out[i] = b_out[i+1] ^ g_in[i];
        end
    endgenerate
 
endmodule