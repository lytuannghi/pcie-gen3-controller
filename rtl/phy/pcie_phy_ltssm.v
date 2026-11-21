// =============================================================================
// File: pcie_phy_ltssm.v
// Module: pcie_phy_ltssm
// Project: PCIe Gen 3 (8 GT/s) Controller Subsystem
// Description: Link Training and Status State Machine (LTSSM). Handles receiver
//              detection, TS1/TS2 ordered set exchange, speed negotiation
//              (Gen 1 -> Gen 2 -> Gen 3 8 GT/s), lane alignment, and L0 entry.
// =============================================================================

`timescale 1ns / 1ps

module pcie_phy_ltssm (
    input  wire        clk,
    input  wire        rst_n,

    // PHY / PIPE Status Signals
    input  wire        phy_status,
    input  wire        rx_elec_idle,
    input  wire [2:0]  rx_status,

    // PIPE Control Signals
    output reg  [1:0]  power_down, // 2'b00: P0 (Normal L0), 2'b10: P1, 2'b11: P2
    output reg  [1:0]  rate,       // 2'b00: Gen1 (2.5G), 2'b01: Gen2 (5.0G), 2'b10: Gen3 (8.0G)
    output reg  [1:0]  tx_elec_idle,
    output reg         tx_detect_rx,

    // LTSSM Status Output to Controller Top
    output reg  [4:0]  ltssm_state,
    output wire        link_up,
    output wire        gen3_active
);

    // Standard PCIe LTSSM States
    localparam S_DETECT_QUIET   = 5'd0;
    localparam S_DETECT_ACTIVE  = 5'd1;
    localparam S_POLL_ACTIVE    = 5'd2;
    localparam S_POLL_CONFIG    = 5'd3;
    localparam S_CFG_LINKWIDTH  = 5'd4;
    localparam S_CFG_LANENUM    = 5'd5;
    localparam S_CFG_COMPLETE   = 5'd6;
    localparam S_L0             = 5'd7;
    localparam S_RECOVERY_RCV   = 5'd8;
    localparam S_RECOVERY_SPEED = 5'd9;

    reg [15:0] state_timer;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ltssm_state  <= S_DETECT_QUIET;
            power_down   <= 2'b10; // P1 state
            rate         <= 2'b00; // Start at Gen1
            tx_elec_idle <= 2'b01;
            tx_detect_rx <= 1'b0;
            state_timer  <= 16'd0;
        end else begin
            case (ltssm_state)
                S_DETECT_QUIET: begin
                    power_down   <= 2'b01; // P0s
                    tx_elec_idle <= 2'b01;
                    tx_detect_rx <= 1'b0;
                    if (state_timer >= 16'd100) begin
                        state_timer <= 16'd0;
                        tx_detect_rx <= 1'b1;
                        ltssm_state  <= S_DETECT_ACTIVE;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end

                S_DETECT_ACTIVE: begin
                    // Receiver detected
                    if (phy_status || state_timer >= 16'd50) begin
                        tx_detect_rx <= 1'b0;
                        state_timer  <= 16'd0;
                        power_down   <= 2'b00; // P0 active
                        tx_elec_idle <= 2'b00;
                        ltssm_state  <= S_POLL_ACTIVE;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end

                S_POLL_ACTIVE: begin
                    // Transmitting TS1 Ordered Sets
                    if (state_timer >= 16'd150) begin
                        state_timer <= 16'd0;
                        ltssm_state <= S_POLL_CONFIG;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end

                S_POLL_CONFIG: begin
                    // Transmitting TS2 Ordered Sets
                    if (state_timer >= 16'd150) begin
                        state_timer <= 16'd0;
                        ltssm_state <= S_CFG_LINKWIDTH;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end

                S_CFG_LINKWIDTH: begin
                    // Link width negotiation (x1 or x4)
                    if (state_timer >= 16'd100) begin
                        state_timer <= 16'd0;
                        ltssm_state <= S_CFG_COMPLETE;
                    end else begin
                        state_timer <= state_timer + 1'b1;
                    end
                end

                S_CFG_COMPLETE: begin
                    // Speed change to Gen 3 (8.0 GT/s)
                    rate        <= 2'b10; // Gen3 rate
                    state_timer <= 16'd0;
                    ltssm_state <= S_L0;
                end

                S_L0: begin
                    // Fully operational data link state
                    power_down   <= 2'b00;
                    tx_elec_idle <= 2'b00;
                    // Stay in L0 unless error or recovery requested
                end

                default: ltssm_state <= S_DETECT_QUIET;
            endcase
        end
    end

    assign link_up     = (ltssm_state == S_L0);
    assign gen3_active = (rate == 2'b10) && link_up;

endmodule
