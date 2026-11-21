// =============================================================================
// File: pcie_tlp_gen.v
// Module: pcie_tlp_gen
// Project: PCIe Gen 3 (8 GT/s) Controller Subsystem
// Description: Transaction Layer Packet (TLP) Generator. Assembles 3DW/4DW
//              Memory Read (MRd), Memory Write (MWr), and Completion (CplD)
//              TLP frames conforming to PCI Express Base Specification 3.0.
// =============================================================================

`timescale 1ns / 1ps

module pcie_tlp_gen (
    input  wire        clk,
    input  wire        rst_n,

    // DMA / Application Interface
    input  wire        req_valid,
    output reg         req_ready,
    input  wire [1:0]  req_type,   // 2'b00: MWr (32-bit), 2'b01: MRd, 2'b10: CplD
    input  wire [31:0] req_addr,
    input  wire [9:0]  req_len_dw, // Length in Dwords (1..1024)
    input  wire [15:0] req_req_id, // Requester ID (Bus:Dev:Func)
    input  wire [7:0]  req_tag,
    input  wire [31:0] req_wdata,
    input  wire        req_wlast,

    // TLP Output to Data Link Layer (DLL)
    output reg         tlp_valid,
    input  wire        tlp_ready,
    output reg  [63:0] tlp_data,
    output reg  [7:0]  tlp_strb,
    output reg         tlp_sop,
    output reg         tlp_eop
);

    // TLP Format / Type Encodings
    localparam FMT_TYPE_MWR32 = 7'b10_00000; // 3DW MWr with data
    localparam FMT_TYPE_MRD32 = 7'b00_00000; // 3DW MRd without data
    localparam FMT_TYPE_CPLD  = 7'b10_01010; // 3DW CplD with data

    localparam S_IDLE    = 2'b00;
    localparam S_HDR_0_1 = 2'b01;
    localparam S_HDR_2_DATA0 = 2'b10;
    localparam S_DATA    = 2'b11;

    reg [1:0] state;
    reg [6:0] fmt_type;

    always @(*) begin
        case (req_type)
            2'b00: fmt_type = FMT_TYPE_MWR32;
            2'b01: fmt_type = FMT_TYPE_MRD32;
            2'b10: fmt_type = FMT_TYPE_CPLD;
            default: fmt_type = FMT_TYPE_MWR32;
        endcase
    end

    // Header Construction
    // DW0: [31:24] Fmt/Type, [23:16] TC/Attr, [15:0] Length in DW
    // DW1: [31:16] Requester ID, [15:8] Tag, [7:4] Last BE, [3:0] 1st BE
    // DW2: Address [31:2], 2'b00
    wire [31:0] dw0 = {1'b0, fmt_type, 8'h00, 6'd0, req_len_dw};
    wire [31:0] dw1 = {req_req_id, req_tag, 4'hF, 4'hF};
    wire [31:0] dw2 = {req_addr[31:2], 2'b00};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            req_ready <= 1'b1;
            tlp_valid <= 1'b0;
            tlp_data  <= 64'd0;
            tlp_strb  <= 8'd0;
            tlp_sop   <= 1'b0;
            tlp_eop   <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    tlp_sop <= 1'b0;
                    tlp_eop <= 1'b0;
                    if (req_valid && req_ready) begin
                        req_ready <= 1'b0;
                        tlp_valid <= 1'b1;
                        tlp_sop   <= 1'b1;
                        tlp_data  <= {dw1, dw0}; // DW1 in [63:32], DW0 in [31:0]
                        tlp_strb  <= 8'hFF;
                        state     <= S_HDR_2_DATA0;
                    end else begin
                        tlp_valid <= 1'b0;
                        req_ready <= 1'b1;
                    end
                end

                S_HDR_2_DATA0: begin
                    tlp_sop <= 1'b0;
                    if (tlp_ready) begin
                        if (fmt_type == FMT_TYPE_MRD32) begin
                            // Read request has no data payload, ends after DW2
                            tlp_data  <= {32'd0, dw2};
                            tlp_strb  <= 8'h0F; // Only lower DW valid
                            tlp_eop   <= 1'b1;
                            state     <= S_IDLE;
                            req_ready <= 1'b1;
                        end else begin
                            // Write / Completion has payload data in upper DW
                            tlp_data  <= {req_wdata, dw2};
                            tlp_strb  <= 8'hFF;
                            if (req_len_dw == 10'd1 || req_wlast) begin
                                tlp_eop   <= 1'b1;
                                state     <= S_IDLE;
                                req_ready <= 1'b1;
                            end else begin
                                tlp_eop <= 1'b0;
                                state   <= S_DATA;
                            end
                        end
                    end
                end

                S_DATA: begin
                    if (tlp_ready) begin
                        tlp_data <= {req_wdata, req_wdata};
                        tlp_strb <= 8'hFF;
                        if (req_wlast) begin
                            tlp_eop   <= 1'b1;
                            state     <= S_IDLE;
                            req_ready <= 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
