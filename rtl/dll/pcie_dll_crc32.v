// =============================================================================
// File: pcie_dll_crc32.v
// Module: pcie_dll_crc32
// Project: PCIe Gen 3 (8 GT/s) Controller Subsystem
// Description: Parallel 32-bit Link CRC (LCRC) Generator & Checker using
//              the standard PCIe polynomial:
//              G(x) = x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 +
//                     x^8 + x^7 + x^5 + x^4 + x^2 + x + 1 (0x04C11DB7)
// =============================================================================

`timescale 1ns / 1ps

module pcie_dll_crc32 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        crc_init,
    input  wire        crc_en,
    input  wire [31:0] data_in,
    output reg  [31:0] crc_out,
    output wire        crc_ok
);

    reg [31:0] crc_reg;

    function [31:0] next_crc32(input [31:0] data, input [31:0] current_crc);
        reg [31:0] d;
        reg [31:0] c;
        begin
            d = data;
            c = current_crc ^ d;
            // 32-bit parallel LFSR XOR step reduction
            next_crc32 = {
                c[30] ^ c[25], c[29] ^ c[24], c[28] ^ c[23], c[27] ^ c[22],
                c[26] ^ c[21], c[25] ^ c[20] ^ c[31], c[24] ^ c[19] ^ c[30], c[23] ^ c[18] ^ c[29],
                c[22] ^ c[17] ^ c[28], c[21] ^ c[16] ^ c[27], c[20] ^ c[15] ^ c[26], c[19] ^ c[14] ^ c[25],
                c[18] ^ c[13] ^ c[24], c[17] ^ c[12] ^ c[23], c[16] ^ c[11] ^ c[22], c[15] ^ c[10] ^ c[21],
                c[14] ^ c[9]  ^ c[20], c[13] ^ c[8]  ^ c[19], c[12] ^ c[7]  ^ c[18], c[11] ^ c[6]  ^ c[17],
                c[10] ^ c[5]  ^ c[16], c[9]  ^ c[4]  ^ c[15], c[8]  ^ c[3]  ^ c[14], c[7]  ^ c[2]  ^ c[13],
                c[6]  ^ c[1]  ^ c[12], c[5]  ^ c[0]  ^ c[11], c[4]  ^ c[10],        c[3]  ^ c[9],
                c[2]  ^ c[8],         c[1]  ^ c[7],         c[0]  ^ c[6],         c[31] ^ c[5]
            };
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= 32'hFFFF_FFFF;
            crc_out <= 32'hFFFF_FFFF;
        end else if (crc_init) begin
            crc_reg <= 32'hFFFF_FFFF;
            crc_out <= 32'hFFFF_FFFF;
        end else if (crc_en) begin
            crc_reg <= next_crc32(data_in, crc_reg);
            crc_out <= ~next_crc32(data_in, crc_reg);
        end
    end

    // Standard residual magic check constant: 0xC704DD7B
    assign crc_ok = (crc_reg == 32'hC704_DD7B);

endmodule
