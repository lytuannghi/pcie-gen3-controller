// =============================================================================
// File: pcie_phy_pipe_if.v
// Module: pcie_phy_pipe_if
// Project: PCIe Gen 3 (8 GT/s) Controller Subsystem
// Description: Standard Intel PIPE 4.3 Physical Interface bridge for SerDes.
// =============================================================================

`timescale 1ns / 1ps

module pcie_phy_pipe_if (
    input  wire        pipe_pclk,
    input  wire        rst_n,

    // MAC Tx Interface
    input  wire [31:0] mac_tx_data,
    input  wire [3:0]  mac_tx_datak,
    input  wire        mac_tx_valid,

    // MAC Rx Interface
    output wire [31:0] mac_rx_data,
    output wire [3:0]  mac_rx_datak,
    output wire        mac_rx_valid,

    // PIPE Physical Pins (to SerDes Macro)
    output reg  [31:0] pipe_tx_data,
    output reg  [3:0]  pipe_tx_datak,
    input  wire [31:0] pipe_rx_data,
    input  wire [3:0]  pipe_rx_datak,
    input  wire        pipe_rx_valid,
    input  wire        pipe_rx_elec_idle,
    input  wire [2:0]  pipe_rx_status,

    // Rate & Power Controls
    input  wire [1:0]  pipe_rate,
    input  wire [1:0]  pipe_power_down,
    input  wire [1:0]  pipe_tx_elec_idle,
    input  wire        pipe_tx_detect_rx,
    output reg         pipe_phy_status
);

    assign mac_rx_data  = pipe_rx_data;
    assign mac_rx_datak = pipe_rx_datak;
    assign mac_rx_valid = pipe_rx_valid;

    always @(posedge pipe_pclk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_tx_data    <= 32'd0;
            pipe_tx_datak   <= 4'd0;
            pipe_phy_status <= 1'b0;
        end else begin
            pipe_tx_data  <= mac_tx_data;
            pipe_tx_datak <= mac_tx_datak;

            // Acknowledge receiver detection or power changes
            if (pipe_tx_detect_rx) begin
                pipe_phy_status <= 1'b1;
            end else begin
                pipe_phy_status <= 1'b0;
            end
        end
    end

endmodule
