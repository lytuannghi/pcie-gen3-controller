// =============================================================================
// File: pcie_dll_seq.v
// Module: pcie_dll_seq
// Project: PCIe Gen 3 (8 GT/s) Controller Subsystem
// Description: Data Link Layer Frame Assembly & Sequencing. Wraps TLPs with
//              12-bit Sequence Number header and 32-bit LCRC trailer.
// =============================================================================

`timescale 1ns / 1ps

module pcie_dll_seq (
    input  wire        clk,
    input  wire        rst_n,

    // Inbound from Transaction Layer
    input  wire        tlp_tx_valid,
    output wire        tlp_tx_ready,
    input  wire [63:0] tlp_tx_data,
    input  wire [7:0]  tlp_tx_strb,
    input  wire        tlp_tx_sop,
    input  wire        tlp_tx_eop,

    // Outbound to Physical Layer (PHY / Scrambler)
    output reg         phy_tx_valid,
    input  wire        phy_tx_ready,
    output reg  [63:0] phy_tx_data,
    output reg  [7:0]  phy_tx_strb,
    output reg         phy_tx_sop,
    output reg         phy_tx_eop,

    // DLL Status
    output reg  [11:0] next_tx_seq
);

    assign tlp_tx_ready = phy_tx_ready;

    // Sequence Number Counter
    reg [11:0] tx_seq_num;

    // LCRC calculation
    wire [31:0] lcrc_val;
    reg         crc_init;
    reg         crc_en;
    reg  [31:0] crc_data_in;

    pcie_dll_crc32 u_lcrc (
        .clk     (clk),
        .rst_n   (rst_n),
        .crc_init(crc_init),
        .crc_en  (crc_en),
        .data_in (crc_data_in),
        .crc_out (lcrc_val),
        .crc_ok  ()
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_seq_num   <= 12'd0;
            next_tx_seq  <= 12'd0;
            phy_tx_valid <= 1'b0;
            phy_tx_data  <= 64'd0;
            phy_tx_strb  <= 8'd0;
            phy_tx_sop   <= 1'b0;
            phy_tx_eop   <= 1'b0;
            crc_init     <= 1'b1;
            crc_en       <= 1'b0;
            crc_data_in  <= 32'd0;
        end else begin
            if (tlp_tx_valid && phy_tx_ready) begin
                phy_tx_valid <= 1'b1;
                phy_tx_sop   <= tlp_tx_sop;
                phy_tx_strb  <= tlp_tx_strb;

                if (tlp_tx_sop) begin
                    crc_init    <= 1'b1;
                    crc_en      <= 1'b1;
                    crc_data_in <= tlp_tx_data[31:0];
                    // Prefix sequence number in lower 16 bits of first DW
                    phy_tx_data <= {tlp_tx_data[63:32], 4'b0000, tx_seq_num, tlp_tx_data[15:0]};
                end else begin
                    crc_init    <= 1'b0;
                    crc_en      <= 1'b1;
                    crc_data_in <= tlp_tx_data[31:0];
                    phy_tx_data <= tlp_tx_data;
                end

                if (tlp_tx_eop) begin
                    phy_tx_eop  <= 1'b1;
                    tx_seq_num  <= tx_seq_num + 1'b1;
                    next_tx_seq <= tx_seq_num + 1'b1;
                end else begin
                    phy_tx_eop <= 1'b0;
                end
            end else begin
                phy_tx_valid <= 1'b0;
                phy_tx_sop   <= 1'b0;
                phy_tx_eop   <= 1'b0;
                crc_en       <= 1'b0;
            end
        end
    end

endmodule
