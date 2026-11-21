// =============================================================================
// File: pcie_tlp_parse.v
// Module: pcie_tlp_parse
// Project: PCIe Gen 3 (8 GT/s) Controller Subsystem
// Description: Inbound 32-bit TLP Parser. Decodes DW0, DW1, DW2 headers and
//              extracts payload for DMA / Register programming.
// =============================================================================

`timescale 1ns / 1ps

module pcie_tlp_parse (
    input  wire        clk,
    input  wire        rst_n,

    // Inbound 32-bit Stream from PHY
    input  wire        rx_tlp_valid,
    output wire        rx_tlp_ready,
    input  wire [31:0] rx_tlp_data,
    input  wire        rx_tlp_sop,
    input  wire        rx_tlp_eop,

    // Decoded Request to Application / DMA
    output reg         app_req_valid,
    output reg  [1:0]  app_req_type, // 0: MWr, 1: MRd, 2: CplD
    output reg  [31:0] app_req_addr,
    output reg  [9:0]  app_req_len,
    output reg  [7:0]  app_req_tag,
    output reg  [31:0] app_req_data,
    output reg         app_req_last
);

    assign rx_tlp_ready = 1'b1;

    localparam P_IDLE = 2'b00;
    localparam P_DW1  = 2'b01;
    localparam P_DW2  = 2'b10;
    localparam P_DATA = 2'b11;

    reg [1:0] state;
    reg [6:0] fmt_type;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= P_IDLE;
            app_req_valid <= 1'b0;
            app_req_type  <= 2'b00;
            app_req_addr  <= 32'd0;
            app_req_len   <= 10'd0;
            app_req_tag   <= 8'd0;
            app_req_data  <= 32'd0;
            app_req_last  <= 1'b0;
            fmt_type      <= 7'd0;
        end else begin
            app_req_valid <= 1'b0;

            case (state)
                P_IDLE: begin
                    if (rx_tlp_valid && rx_tlp_sop) begin
                        fmt_type    <= rx_tlp_data[30:24];
                        app_req_len <= rx_tlp_data[9:0];
                        if (rx_tlp_data[30:24] == 7'b10_01010) begin
                            app_req_type <= 2'b10; // CplD
                        end else if (rx_tlp_data[30:29] == 2'b10) begin
                            app_req_type <= 2'b00; // MWr
                        end else begin
                            app_req_type <= 2'b01; // MRd
                        end
                        state <= P_DW1;
                    end
                end

                P_DW1: begin
                    if (rx_tlp_valid) begin
                        app_req_tag <= rx_tlp_data[15:8];
                        state       <= P_DW2;
                    end
                end

                P_DW2: begin
                    if (rx_tlp_valid) begin
                        app_req_addr <= rx_tlp_data;
                        if (rx_tlp_eop) begin
                            // Header only (e.g. MRd)
                            app_req_valid <= 1'b1;
                            app_req_last  <= 1'b1;
                            state         <= P_IDLE;
                        end else begin
                            state <= P_DATA;
                        end
                    end
                end

                P_DATA: begin
                    if (rx_tlp_valid) begin
                        app_req_data  <= rx_tlp_data;
                        app_req_valid <= 1'b1;
                        app_req_last  <= rx_tlp_eop;
                        if (rx_tlp_eop) begin
                            state <= P_IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule
