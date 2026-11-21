// =============================================================================
// File: pcie_phy_scrambler.v
// Module: pcie_phy_scrambler
// Project: PCIe Gen 3 (8 GT/s) Controller Subsystem
// Description: Gen 3 128b/130b Payload Scrambler & Descrambler using 23-bit LFSR:
//              G(D) = D^23 + D^21 + D^16 + D^8 + D^5 + D^2 + 1
// =============================================================================

`timescale 1ns / 1ps

module pcie_phy_scrambler (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        scrambler_en,
    input  wire        scrambler_reset, // Reset LFSR on Sync Header / EDB
    input  wire [31:0] data_in,
    output reg  [31:0] data_out
);

    reg [22:0] lfsr;

    // Advance 23-bit LFSR for 32 bits of parallel data
    function [22:0] next_lfsr23(input [22:0] state);
        reg [22:0] s;
        integer i;
        reg feedback;
        begin
            s = state;
            for (i = 0; i < 32; i = i + 1) begin
                feedback = s[22] ^ s[20] ^ s[15] ^ s[7] ^ s[4] ^ s[1];
                s = {s[21:0], feedback};
            end
            next_lfsr23 = s;
        end
    endfunction

    // 32-bit mask generation
    function [31:0] lfsr_mask32(input [22:0] state);
        reg [22:0] s;
        reg [31:0] mask;
        integer i;
        reg feedback;
        begin
            s = state;
            for (i = 0; i < 32; i = i + 1) begin
                feedback = s[22] ^ s[20] ^ s[15] ^ s[7] ^ s[4] ^ s[1];
                mask[i]  = feedback;
                s = {s[21:0], feedback};
            end
            lfsr_mask32 = mask;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr     <= 23'h1DBFBC; // PCIe Gen3 seed constant
            data_out <= 32'd0;
        end else if (scrambler_reset) begin
            lfsr     <= 23'h1DBFBC;
            data_out <= data_in;
        end else if (scrambler_en) begin
            data_out <= data_in ^ lfsr_mask32(lfsr);
            lfsr     <= next_lfsr23(lfsr);
        end else begin
            data_out <= data_in;
        end
    end

endmodule
