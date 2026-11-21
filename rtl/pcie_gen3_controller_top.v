// =============================================================================
// File: pcie_gen3_controller_top.v
// Module: pcie_gen3_controller_top
// Project: PCIe Gen 3 (8 GT/s) Controller Subsystem (Full-Flow ASIC Tape-Out)
// Description: Complete PCI Express Base Specification 3.0 Controller Top-Level
//              integrating Transaction Layer (TLP), Data Link Layer (LCRC/Seq),
//              Physical Layer (LTSSM/PIPE/Scrambler), and AXI4 DMA Subsystem.
// =============================================================================

`timescale 1ns / 1ps

module pcie_gen3_controller_top (
    input  wire        sys_clk,       // 250 MHz Core System Clock
    input  wire        rst_n,

    // PIPE 4.3 Physical Interface (to Multi-Gigabit SerDes PHY)
    output wire [31:0] pipe_tx_data,
    output wire [3:0]  pipe_tx_datak,
    input  wire [31:0] pipe_rx_data,
    input  wire [3:0]  pipe_rx_datak,
    input  wire        pipe_rx_valid,
    input  wire        pipe_rx_elec_idle,
    input  wire [2:0]  pipe_rx_status,
    output wire [1:0]  pipe_rate,
    output wire [1:0]  pipe_power_down,
    output wire [1:0]  pipe_tx_elec_idle,
    output wire        pipe_tx_detect_rx,
    input  wire        pipe_phy_status,

    // AXI4 Master Interface (DMA System Interconnect)
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

    // Controller Status & Interrupts
    output wire        link_up,
    output wire        gen3_active,
    output wire [4:0]  ltssm_state,
    output wire        dma_irq
);

    // LTSSM Physical Layer FSM
    pcie_phy_ltssm u_ltssm (
        .clk             (sys_clk),
        .rst_n           (rst_n),
        .phy_status      (pipe_phy_status),
        .rx_elec_idle    (pipe_rx_elec_idle),
        .rx_status       (pipe_rx_status),
        .power_down      (pipe_power_down),
        .rate            (pipe_rate),
        .tx_elec_idle    (pipe_tx_elec_idle),
        .tx_detect_rx    (pipe_tx_detect_rx),
        .ltssm_state     (ltssm_state),
        .link_up         (link_up),
        .gen3_active     (gen3_active)
    );

    // PIPE Interface Bridge
    wire [31:0] mac_tx_data;
    wire [3:0]  mac_tx_datak;
    wire        mac_tx_valid;

    wire [31:0] mac_rx_data;
    wire [3:0]  mac_rx_datak;
    wire        mac_rx_valid;

    pcie_phy_pipe_if u_pipe_if (
        .pipe_pclk         (sys_clk),
        .rst_n             (rst_n),
        .mac_tx_data       (mac_tx_data),
        .mac_tx_datak      (mac_tx_datak),
        .mac_tx_valid      (mac_tx_valid),
        .mac_rx_data       (mac_rx_data),
        .mac_rx_datak      (mac_rx_datak),
        .mac_rx_valid      (mac_rx_valid),
        .pipe_tx_data      (pipe_tx_data),
        .pipe_tx_datak     (pipe_tx_datak),
        .pipe_rx_data      (pipe_rx_data),
        .pipe_rx_datak     (pipe_rx_datak),
        .pipe_rx_valid     (pipe_rx_valid),
        .pipe_rx_elec_idle (pipe_rx_elec_idle),
        .pipe_rx_status    (pipe_rx_status),
        .pipe_rate         (pipe_rate),
        .pipe_power_down   (pipe_power_down),
        .pipe_tx_elec_idle (pipe_tx_elec_idle),
        .pipe_tx_detect_rx (pipe_tx_detect_rx),
        .pipe_phy_status   ()
    );

    // DMA & TLP Request Signals
    wire        tlp_req_valid;
    wire        tlp_req_ready;
    wire [1:0]  tlp_req_type;
    wire [31:0] tlp_req_addr;
    wire [9:0]  tlp_req_len;
    wire [31:0] tlp_req_wdata;
    wire        tlp_req_wlast;

    // Transaction Layer: TLP Generator
    wire        tlp_gen_valid;
    wire        tlp_gen_ready;
    wire [63:0] tlp_gen_data;
    wire [7:0]  tlp_gen_strb;
    wire        tlp_gen_sop;
    wire        tlp_gen_eop;

    pcie_tlp_gen u_tlp_gen (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .req_valid  (tlp_req_valid),
        .req_ready  (tlp_req_ready),
        .req_type   (tlp_req_type),
        .req_addr   (tlp_req_addr),
        .req_len_dw (tlp_req_len),
        .req_req_id (16'h0100), // Bus 1, Dev 0, Func 0
        .req_tag    (8'h01),
        .req_wdata  (tlp_req_wdata),
        .req_wlast  (tlp_req_wlast),
        .tlp_valid  (tlp_gen_valid),
        .tlp_ready  (tlp_gen_ready),
        .tlp_data   (tlp_gen_data),
        .tlp_strb   (tlp_gen_strb),
        .tlp_sop    (tlp_gen_sop),
        .tlp_eop    (tlp_gen_eop)
    );

    // Data Link Layer: Sequencing and LCRC
    wire        dll_tx_valid;
    wire [63:0] dll_tx_data;
    wire [7:0]  dll_tx_strb;
    wire        dll_tx_sop;
    wire        dll_tx_eop;
    wire [11:0] next_seq;

    pcie_dll_seq u_dll (
        .clk          (sys_clk),
        .rst_n        (rst_n),
        .tlp_tx_valid (tlp_gen_valid),
        .tlp_tx_ready (tlp_gen_ready),
        .tlp_tx_data  (tlp_gen_data),
        .tlp_tx_strb  (tlp_gen_strb),
        .tlp_tx_sop   (tlp_gen_sop),
        .tlp_tx_eop   (tlp_gen_eop),
        .phy_tx_valid (dll_tx_valid),
        .phy_tx_ready (1'b1),
        .phy_tx_data  (dll_tx_data),
        .phy_tx_strb  (dll_tx_strb),
        .phy_tx_sop   (dll_tx_sop),
        .phy_tx_eop   (dll_tx_eop),
        .next_tx_seq  (next_seq)
    );

    // Physical Layer: Payload Scrambler
    wire [31:0] scrambled_tx;
    pcie_phy_scrambler u_scrambler (
        .clk            (sys_clk),
        .rst_n          (rst_n),
        .scrambler_en   (link_up),
        .scrambler_reset(dll_tx_sop),
        .data_in        (dll_tx_data[31:0]),
        .data_out       (scrambled_tx)
    );

    assign mac_tx_data  = link_up ? scrambled_tx : 32'h4A4A4A4A; // TS1 OS when training
    assign mac_tx_datak = link_up ? 4'b0000 : 4'b0001;
    assign mac_tx_valid = dll_tx_valid;

    // Transaction Layer: Inbound TLP Parser
    wire        app_req_valid;
    wire [1:0]  app_req_type;
    wire [31:0] app_req_addr;
    wire [9:0]  app_req_len;
    wire [7:0]  app_req_tag;
    wire [31:0] app_req_data;
    wire        app_req_last;

    pcie_tlp_parse u_tlp_parse (
        .clk          (sys_clk),
        .rst_n        (rst_n),
        .rx_tlp_valid (mac_rx_valid),
        .rx_tlp_ready (),
        .rx_tlp_data  (mac_rx_data),
        .rx_tlp_sop   (mac_rx_datak[0]),
        .rx_tlp_eop   (mac_rx_datak[3]),
        .app_req_valid(app_req_valid),
        .app_req_type (app_req_type),
        .app_req_addr (app_req_addr),
        .app_req_len  (app_req_len),
        .app_req_tag  (app_req_tag),
        .app_req_data (app_req_data),
        .app_req_last (app_req_last)
    );

    // Scatter-Gather DMA Subsystem
    pcie_axi4_dma_engine u_dma (
        .clk          (sys_clk),
        .rst_n        (rst_n),
        .reg_wr       (app_req_valid && (app_req_type == 2'b00) && (app_req_addr[31:24] == 8'h00)),
        .reg_addr     (app_req_addr[7:0]),
        .reg_wdata    (app_req_data),
        .reg_rdata    (),
        .tlp_req_valid(tlp_req_valid),
        .tlp_req_ready(tlp_req_ready),
        .tlp_req_type (tlp_req_type),
        .tlp_req_addr (tlp_req_addr),
        .tlp_req_len  (tlp_req_len),
        .tlp_req_wdata(tlp_req_wdata),
        .tlp_req_wlast(tlp_req_wlast),
        .cpl_valid    (app_req_valid && (app_req_type == 2'b10)),
        .cpl_data     (app_req_data),
        .cpl_last     (app_req_last),
        .m_axi_awaddr (m_axi_awaddr),
        .m_axi_awlen  (m_axi_awlen),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata  (m_axi_wdata),
        .m_axi_wstrb  (m_axi_wstrb),
        .m_axi_wlast  (m_axi_wlast),
        .m_axi_wvalid (m_axi_wvalid),
        .m_axi_wready (m_axi_wready),
        .m_axi_bvalid (m_axi_bvalid),
        .m_axi_bready (m_axi_bready),
        .dma_done_irq (dma_irq)
    );

endmodule
