`timescale 1ns / 1 ps

// This essentially replicates the Tri-Mode MAC
// using an AXI Ethernet Lite and a PicoBlaze.
// This goddamn thing used to be a block diagram,
// but I've since given up on those because
// packaging them, reusing them, WHATEVER,
// NOTHING WORKS.
//
// This also means, you jackass, that I CAN'T USE A GODDAMN
// SYSTEM ILA BECAUSE YOU'RE HORRIBLE HUMAN BEINGS.
//
// This is really just a simple AXI connect of
// DataMover MM2S      <--> |
// DataMover S2MM      <--> | <--> EthernetLite
// PicoBlaze<-> Bridge <--> |
// but of course that means it takes eight miles of code.
module axi_ethernet_streamer( input clk100,
			      input 	   locked,
			      input 	   resetn,
			      output 	   reset_out,
			      output [7:0] m_axis_eth_rx_tdata,
			      output 	   m_axis_eth_rx_tkeep,
			      output 	   m_axis_eth_rx_tlast,
			      output 	   m_axis_eth_rx_tvalid,
			      input 	   m_axis_eth_rx_tready,

			      input [7:0]  s_axis_eth_tx_tdata,
			      input 	   s_axis_eth_tx_tlast,
			      input 	   s_axis_eth_tx_tvalid,
			      output 	   s_axis_eth_tx_tready,

			      input [47:0] mac_address,

			      output 	   mdio_mdc,
			      input 	   mdio_mdio_i,
			      output 	   mdio_mdio_o,
			      output 	   mdio_mdio_t,

			      input 	   mii_col,
			      input 	   mii_crs,
			      output 	   mii_rst_n,
			      input 	   mii_rx_clk,
			      input 	   mii_rx_dv,
			      input 	   mii_rx_er,
			      input [3:0]  mii_rxd,
			      input 	   mii_tx_clk,
			      output 	   mii_tx_en,
			      output [3:0] mii_txd);

   //// DATA MOVER ////
   
   // DataMover AXI4-Stream MM2S status link. 
   wire [7:0] 				   axis_dm_mm2s_sts_tdata;
   wire 				   axis_dm_mm2s_sts_tready;
   wire 				   axis_dm_mm2s_sts_tvalid;
   // DataMover AXI4-Stream MM2S command link.
   wire [71:0] 				   axis_dm_mm2s_cmd_tdata;
   wire 				   axis_dm_mm2s_cmd_tready;
   wire 				   axis_dm_mm2s_cmd_tvalid;  
   // DataMover AXI4-Stream S2MM status link.
   wire [31:0] 				   axis_dm_s2mm_sts_tdata;
   wire 				   axis_dm_s2mm_sts_tready;
   wire 				   axis_dm_s2mm_sts_tvalid;
   // DataMover AXI4-Stream S2MM command link.
   wire [71:0] 				   axis_dm_s2mm_cmd_tdata;
   wire 				   axis_dm_s2mm_cmd_tready;
   wire 				   axis_dm_s2mm_cmd_tvalid;

   // DataMover S2MM link. The MM2S link goes out of the module,
   // but the S2MM link has to be parsed by the PicoBlaze.
   wire [7:0] 				   pb2dm_s2mm_tdata;
   wire 				   pb2dm_s2mm_tvalid;
   wire 				   pb2dm_s2mm_tready;
   wire 				   pb2dm_s2mm_tkeep;
   wire 				   pb2dm_s2mm_tlast;
   
   // DataMover AXI-4 MM2S Link. This side is read-only.
   // AR stream.
   wire [31:0] 				   axi_dm_mm2s_araddr;
   wire [1:0] 				   axi_dm_mm2s_arburst;
   wire [3:0] 				   axi_dm_mm2s_arcache;
   wire [7:0] 				   axi_dm_mm2s_arlen;
   wire [2:0] 				   axi_dm_mm2s_arprot;
   wire 				   axi_dm_mm2s_arready;
   wire [2:0] 				   axi_dm_mm2s_arsize;
   wire [3:0] 				   axi_dm_mm2s_aruser;
   wire 				   axi_dm_mm2s_arvalid;
   // R stream.
   wire [31:0] 				   axi_dm_mm2s_rdata;
   wire 				   axi_dm_mm2s_rlast;
   wire 				   axi_dm_mm2s_rready;
   wire [1:0]				   axi_dm_mm2s_rresp;
   wire 				   axi_dm_mm2s_rvalid;
   // DataMover AXI-4 S2MM Link. This side is write only.
   // AW stream
   wire [31:0] 				   axi_dm_s2mm_awaddr;
   wire [1:0] 				   axi_dm_s2mm_awburst;
   wire [3:0] 				   axi_dm_s2mm_awcache;
   wire [7:0] 				   axi_dm_s2mm_awlen;
   wire [2:0] 				   axi_dm_s2mm_awprot;
   wire 				   axi_dm_s2mm_awready;
   wire [2:0] 				   axi_dm_s2mm_awsize;
   wire [3:0] 				   axi_dm_s2mm_awuser;
   wire 				   axi_dm_s2mm_awvalid;
   // B stream.
   wire [1:0] 				   axi_dm_s2mm_bresp;
   wire 				   axi_dm_s2mm_bready;   
   wire 				   axi_dm_s2mm_bvalid;
   // W stream.
   wire [31:0] 				   axi_dm_s2mm_wdata;
   wire 				   axi_dm_s2mm_wlast;
   wire 				   axi_dm_s2mm_wready;
   wire [3:0] 				   axi_dm_s2mm_wstrb;
   wire 				   axi_dm_s2mm_wvalid;

   //// ETHERNET LITE ////
   wire [31:0] 				   eth_araddr;
   wire 				   eth_arready;
   wire 				   eth_arvalid;
   // burst/cache/len/size
   wire [1:0] 				   eth_arburst;
   wire [3:0] 				   eth_arcache;
   wire [7:0] 				   eth_arlen;
   wire [2:0] 				   eth_arsize;
   // AW channel
   wire [31:0] 				   eth_awaddr;
   wire 				   eth_awready;
   wire 				   eth_awvalid;
   // burst/cache/len/size   
   wire [1:0] 				   eth_awburst;
   wire [3:0] 				   eth_awcache;
   wire [7:0] 				   eth_awlen;
   wire [2:0] 				   eth_awsize;
   wire [1:0] 				   eth_bresp;
   wire 				   eth_bready;
   wire 				   eth_bvalid;
   wire [31:0] 				   eth_rdata;
   wire [1:0] 				   eth_rresp;   
   wire 				   eth_rready;
   wire 				   eth_rvalid;   
   wire 				   eth_rlast;
   wire [31:0] 				   eth_wdata;
   wire 				   eth_wready;
   wire 				   eth_wvalid;
   wire 				   eth_wlast;

   //// PICOBLAZE AXI-4 ////
   // This is the output of the protocol converter.
   wire [12:0] 				   pbaxi4_araddr;
   wire 				   pbaxi4_arready;
   wire 				   pbaxi4_arvalid;   
   wire [1:0] 				   pbaxi4_arburst;
   wire [3:0] 				   pbaxi4_arcache;
   wire [7:0] 				   pbaxi4_arlen;
   wire 				   pbaxi4_arlock;
   wire [2:0] 				   pbaxi4_arprot;
   wire [3:0] 				   pbaxi4_arqos;
   wire [2:0] 				   pbaxi4_arsize;

   wire [12:0] 				   pbaxi4_awaddr;
   wire 				   pbaxi4_awready;
   wire 				   pbaxi4_awvalid;   
   wire [1:0] 				   pbaxi4_awburst;
   wire [3:0] 				   pbaxi4_awcache;
   wire [7:0] 				   pbaxi4_awlen;
   wire 				   pbaxi4_awlock;
   wire [2:0] 				   pbaxi4_awprot;
   wire [3:0] 				   pbaxi4_awqos;
   wire [2:0] 				   pbaxi4_awsize;   

   wire [1:0] 				   pbaxi4_bresp;
   wire 				   pbaxi4_bvalid;
   wire 				   pbaxi4_bready;

   wire [31:0] 				   pbaxi4_rdata;
   wire 				   pbaxi4_rready;
   wire 				   pbaxi4_rvalid;
   wire                    pbaxi4_rlast;
   wire [1:0] 				   pbaxi4_rresp;

   wire [31:0] 			   pbaxi4_wdata;
   wire 				   pbaxi4_wready;
   wire 				   pbaxi4_wvalid;
   wire 				   pbaxi4_wlast;
   wire [3:0]              pbaxi4_wstrb;
   
   //// PICOBLAZE AXI4-LITE ////
   wire [12:0] 				   pb_araddr;
   wire 				   pb_arready;
   wire 				   pb_arvalid;
   wire [12:0] 				   pb_awaddr;
   wire 				   pb_awready;
   wire 				   pb_awvalid;
   wire [1:0] 				   pb_bresp;
   wire 				   pb_bready;
   wire 				   pb_bvalid;
   wire [31:0] 				   pb_rdata;
   wire [1:0] 				   pb_rresp;
   wire 				   pb_rready;
   wire 				   pb_rvalid;
   wire [31:0] 				   pb_wdata;
   wire 				   pb_wready;
   wire 				   pb_wvalid;
   wire [3:0]              pb_wstrb;
   
   wire 				   peripheral_resetn;
   wire 				   interconnect_resetn;
   aeths_reset u_reset(.aux_reset_in(1'b0),
                .mb_debug_sys_rst(1'b0),
		       .dcm_locked(locked),
		       .ext_reset_in(!resetn),
		       .mb_reset(),
		       .bus_struct_reset(),
		       .interconnect_aresetn(interconnect_resetn),
		       .peripheral_aresetn(peripheral_resetn),
		       .peripheral_reset(reset_out),
		       .slowest_sync_clk(clk100));   
   
   aeths_datamover u_dm(.m_axi_mm2s_aclk(clk100),
		      .m_axi_mm2s_aresetn(peripheral_resetn),
		      .m_axi_mm2s_araddr(axi_dm_mm2s_araddr),
		      .m_axi_mm2s_arready(axi_dm_mm2s_arready),
		      .m_axi_mm2s_arvalid(axi_dm_mm2s_arvalid),
		      // burst/cache/len/prot/size/user
		      .m_axi_mm2s_arburst(axi_dm_mm2s_arburst),
		      .m_axi_mm2s_arcache(axi_dm_mm2s_arcache),
		      .m_axi_mm2s_arlen(axi_dm_mm2s_arlen),
		      .m_axi_mm2s_arprot(axi_dm_mm2s_arprot),
		      .m_axi_mm2s_arsize(axi_dm_mm2s_arsize),
		      .m_axi_mm2s_aruser(axi_dm_mm2s_aruser),
		      .m_axi_mm2s_rdata(axi_dm_mm2s_rdata),
		      .m_axi_mm2s_rvalid(axi_dm_mm2s_rvalid),
		      .m_axi_mm2s_rready(axi_dm_mm2s_rready),
		      .m_axi_mm2s_rlast(axi_dm_mm2s_rlast),
		      .m_axi_mm2s_rresp(axi_dm_mm2s_rresp),
		      .m_axi_s2mm_aclk(clk100),
		      .m_axi_s2mm_aresetn(peripheral_resetn),
		      .m_axi_s2mm_awaddr(axi_dm_s2mm_awaddr),
		      .m_axi_s2mm_awready(axi_dm_s2mm_awready),
		      .m_axi_s2mm_awvalid(axi_dm_s2mm_awvalid),
		      // burst/cache/len/prot/size/user		      
		      .m_axi_s2mm_awburst(axi_dm_s2mm_awburst),
		      .m_axi_s2mm_awcache(axi_dm_s2mm_awcache),
		      .m_axi_s2mm_awlen(axi_dm_s2mm_awlen),
		      .m_axi_s2mm_awprot(axi_dm_s2mm_awprot),
		      .m_axi_s2mm_awsize(axi_dm_s2mm_awsize),
		      .m_axi_s2mm_awuser(axi_dm_s2mm_awuser),
		      .m_axi_s2mm_bresp(axi_dm_s2mm_bresp),
		      .m_axi_s2mm_bvalid(axi_dm_s2mm_bvalid),
		      .m_axi_s2mm_bready(axi_dm_s2mm_bready),
		      .m_axi_s2mm_wdata(axi_dm_s2mm_wdata),
		      .m_axi_s2mm_wvalid(axi_dm_s2mm_wvalid),
		      .m_axi_s2mm_wready(axi_dm_s2mm_wready),
		      .m_axi_s2mm_wlast(axi_dm_s2mm_wlast),
		      .m_axi_s2mm_wstrb(axi_dm_s2mm_wstrb),
		      
		      // MM2S cmdsts link
		      .m_axis_mm2s_cmdsts_aclk(clk100),
		      .m_axis_mm2s_cmdsts_aresetn(peripheral_resetn),
		      .m_axis_mm2s_sts_tdata(axis_dm_mm2s_sts_tdata),
		      .m_axis_mm2s_sts_tready(axis_dm_mm2s_sts_tready),
		      .m_axis_mm2s_sts_tvalid(axis_dm_mm2s_sts_tvalid),
		      .s_axis_mm2s_cmd_tdata(axis_dm_mm2s_cmd_tdata),
		      .s_axis_mm2s_cmd_tvalid(axis_dm_mm2s_cmd_tvalid),
		      .s_axis_mm2s_cmd_tready(axis_dm_mm2s_cmd_tready),
		      // MM2S link
		      .m_axis_mm2s_tdata(m_axis_eth_rx_tdata),
		      .m_axis_mm2s_tkeep(m_axis_eth_rx_tkeep),
		      .m_axis_mm2s_tlast(m_axis_eth_rx_tlast),
		      .m_axis_mm2s_tready(m_axis_eth_rx_tready),
		      .m_axis_mm2s_tvalid(m_axis_eth_rx_tvalid),
		      // S2MM cmdsts link
		      .m_axis_s2mm_cmdsts_awclk(clk100),
		      .m_axis_s2mm_cmdsts_aresetn(peripheral_resetn),
		      .m_axis_s2mm_sts_tdata(axis_dm_s2mm_sts_tdata),
		      .m_axis_s2mm_sts_tvalid(axis_dm_s2mm_sts_tvalid),
		      .m_axis_s2mm_sts_tready(axis_dm_s2mm_sts_tready),
		      .s_axis_s2mm_cmd_tdata(axis_dm_s2mm_cmd_tdata),
		      .s_axis_s2mm_cmd_tready(axis_dm_s2mm_cmd_tready),
		      .s_axis_s2mm_cmd_tvalid(axis_dm_s2mm_cmd_tvalid),
		      // S2MM link
		      .s_axis_s2mm_tdata(pb2dm_s2mm_tdata),
		      .s_axis_s2mm_tvalid(pb2dm_s2mm_tvalid),
		      .s_axis_s2mm_tready(pb2dm_s2mm_tready),
		      .s_axis_s2mm_tkeep(pb2dm_s2mm_tkeep),
		      .s_axis_s2mm_tlast(pb2dm_s2mm_tlast));

   aeths_ethlite u_eth( .s_axi_aclk(clk100),
                        .s_axi_aresetn(peripheral_resetn),
			.s_axi_araddr(eth_araddr[12:0]),
			.s_axi_arready(eth_arready),
			.s_axi_arvalid(eth_arvalid),
			// burst/cache/len/size
			.s_axi_arburst(eth_arburst),
			.s_axi_arcache(eth_arcache),
			.s_axi_arlen(eth_arlen),
			.s_axi_arsize(eth_arsize),
			
			.s_axi_awaddr(eth_awaddr[12:0]),
			.s_axi_awready(eth_awready),
			.s_axi_awvalid(eth_awvalid),
			// burst/cache/len/size
			.s_axi_awburst(eth_awburst),
			.s_axi_awcache(eth_awcache),
			.s_axi_awlen(eth_awlen),
			.s_axi_awsize(eth_awsize),

			.s_axi_bresp(eth_bresp),
			.s_axi_bready(eth_bready),
			.s_axi_bvalid(eth_bvalid),

			.s_axi_rdata(eth_rdata),
			.s_axi_rresp(eth_rresp),
			.s_axi_rready(eth_rready),
			.s_axi_rvalid(eth_rvalid),
			.s_axi_rlast(eth_rlast),

			.s_axi_wdata(eth_wdata),
			.s_axi_wready(eth_wready),
			.s_axi_wvalid(eth_wvalid),
			.s_axi_wlast(eth_wlast),
			// Hard tie the write strobes to 1.
			// Nothing can partial write.
			.s_axi_wstrb({4{1'b1}}),
			// MII side
			.phy_col(mii_col),
			.phy_crs(mii_crs),
			.phy_dv(mii_rx_dv),
			.phy_mdc(mdio_mdc),
			.phy_mdio_i(mdio_mdio_i),
			.phy_mdio_o(mdio_mdio_o),
			.phy_mdio_t(mdio_mdio_t),
			.phy_rst_n(mii_rst_n),
			.phy_rx_clk(mii_rx_clk),
			.phy_rx_data(mii_rxd),
			.phy_rx_er(mii_rx_er),
			.phy_tx_clk(mii_tx_clk),
			.phy_tx_data(mii_txd),
			.phy_tx_en(mii_tx_en));
   
   // PicoBlaze.
   aeths_pbethlite_ctrl u_pb( .m_axi_aclk(clk100),
                    .m_axi_aresetn(peripheral_resetn),
			      .m_axi_araddr(pb_araddr),
			      .m_axi_arready(pb_arready),
			      .m_axi_arvalid(pb_arvalid),
			      .m_axi_awaddr(pb_awaddr),
			      .m_axi_awready(pb_awready),
			      .m_axi_awvalid(pb_awvalid),
			      .m_axi_bresp(pb_bresp),
			      .m_axi_bready(pb_bready),
			      .m_axi_bvalid(pb_bvalid),
			      .m_axi_rdata(pb_rdata),
			      .m_axi_rresp(pb_rresp),
			      .m_axi_rready(pb_rready),
			      .m_axi_rvalid(pb_rvalid),
			      .m_axi_wdata(pb_wdata),
			      .m_axi_wready(pb_wready),
			      .m_axi_wvalid(pb_wvalid),
			      .m_axi_wstrb(pb_wstrb),

			      .m_axis_mm2s_cmd_tdata(axis_dm_mm2s_cmd_tdata),
			      .m_axis_mm2s_cmd_tready(axis_dm_mm2s_cmd_tready),
			      .m_axis_mm2s_cmd_tvalid(axis_dm_mm2s_cmd_tvalid),
			      .s_axis_mm2s_sts_tdata(axis_dm_mm2s_sts_tdata),
			      .s_axis_mm2s_sts_tready(axis_dm_mm2s_sts_tready),
			      .s_axis_mm2s_sts_tvalid(axis_dm_mm2s_sts_tvalid),
			      .m_axis_s2mm_cmd_tdata(axis_dm_s2mm_cmd_tdata),
			      .m_axis_s2mm_cmd_tready(axis_dm_s2mm_cmd_tready),
			      .m_axis_s2mm_cmd_tvalid(axis_dm_s2mm_cmd_tvalid),
			      .s_axis_s2mm_sts_tdata(axis_dm_s2mm_sts_tdata),
			      .s_axis_s2mm_sts_tvalid(axis_dm_s2mm_sts_tvalid),
			      .s_axis_s2mm_sts_tready(axis_dm_s2mm_sts_tready),

			      .m_axis_s2mm_tdata(pb2dm_s2mm_tdata),
			      .m_axis_s2mm_tready(pb2dm_s2mm_tready),
			      .m_axis_s2mm_tvalid(pb2dm_s2mm_tvalid),
			      .m_axis_s2mm_tkeep(pb2dm_s2mm_tkeep),
			      .m_axis_s2mm_tlast(pb2dm_s2mm_tlast),

			      .s_axis_s2mm_tdata(s_axis_eth_tx_tdata),
			      .s_axis_s2mm_tlast(s_axis_eth_tx_tlast),
			      .s_axis_s2mm_tready(s_axis_eth_tx_tready),
			      .s_axis_s2mm_tvalid(s_axis_eth_tx_tvalid),

			      .mac_address(mac_address));
   // Protocol adapter.
   aeths_protocol_converter u_conv( .aclk(clk100),
				    .aresetn(interconnect_resetn),
				    .m_axi_araddr(pbaxi4_araddr),
				    .m_axi_arburst(pbaxi4_arburst),
				    .m_axi_arcache(pbaxi4_arcache),
				    .m_axi_arlen(pbaxi4_arlen),
				    .m_axi_arlock(pbaxi4_arlock),
				    .m_axi_arprot(pbaxi4_arprot),
				    .m_axi_arqos(pbaxi4_arqos),
				    .m_axi_arready(pbaxi4_arready),
				    .m_axi_arsize(pbaxi4_arsize),
				    .m_axi_arvalid(pbaxi4_arvalid),

				    .m_axi_awaddr(pbaxi4_awaddr),
				    .m_axi_awburst(pbaxi4_awburst),
				    .m_axi_awcache(pbaxi4_awcache),
				    .m_axi_awlen(pbaxi4_awlen),
				    .m_axi_awlock(pbaxi4_awlock),
				    .m_axi_awprot(pbaxi4_awprot),
				    .m_axi_awqos(pbaxi4_awqos),
				    .m_axi_awready(pbaxi4_awready),
				    .m_axi_awsize(pbaxi4_awsize),
				    .m_axi_awvalid(pbaxi4_awvalid),

				    .m_axi_bready(pbaxi4_bready),
				    .m_axi_bresp(pbaxi4_bresp),
				    .m_axi_bvalid(pbaxi4_bvalid),

				    .m_axi_rdata(pbaxi4_rdata),
				    .m_axi_rresp(pbaxi4_rresp),
				    .m_axi_rlast(pbaxi4_rlast),
				    .m_axi_rready(pbaxi4_rready),
				    .m_axi_rvalid(pbaxi4_rvalid),

				    .m_axi_wdata(pbaxi4_wdata),
				    .m_axi_wlast(pbaxi4_wlast),
				    .m_axi_wready(pbaxi4_wready),
				    .m_axi_wvalid(pbaxi4_wvalid),
				    .m_axi_wstrb(pbaxi4_wstrb),

				    .s_axi_araddr(pb_araddr),
				    .s_axi_arready(pb_arready),
				    .s_axi_arvalid(pb_arvalid),
				    .s_axi_arprot(3'b000),

				    .s_axi_awaddr(pb_awaddr),
				    .s_axi_awready(pb_awready),
				    .s_axi_awvalid(pb_awvalid),
				    .s_axi_awprot(3'b000),

				    .s_axi_bresp(pb_bresp),
				    .s_axi_bready(pb_bready),
				    .s_axi_bvalid(pb_bvalid),

				    .s_axi_rdata(pb_rdata),
				    .s_axi_rresp(pb_rresp),
				    .s_axi_rready(pb_rready),
				    .s_axi_rvalid(pb_rvalid),

				    .s_axi_wdata(pb_wdata),
				    .s_axi_wready(pb_wready),
				    .s_axi_wstrb(pb_wstrb),
				    .s_axi_wvalid(pb_wvalid));
   
   // axi IDs for echoing
   wire [3:0] eth_wid;
   wire [3:0] eth_rid;
   
   // and now all that's left is the interconnect
   // Note that Xilinx sucks here. it doesn't matter that we said
   // that we don't have certain signals. It still wants them.
   // On the plus side it at least believed us with read/write channels only!
//   dumb_block_diagram_wrapper u_wrapper(.aresetn(interconnect_resetn),
//                                        .clk100(clk100),
//                                        // ethlite connection
//                                        .eth_araddr(eth_araddr),
//                                        .eth_arburst(eth_arburst),
//                                        .eth_arcache(eth_arcache),
//                                        .eth_arid(eth_rid),
//                                        .eth_arlen(eth_arlen),
//                                        .eth_arlock(),
//                                        .eth_arprot(),
//                                        .eth_arqos(),
//                                        .eth_arready(eth_arready),
//                                        .eth_arregion(),
//                                        .eth_arsize(eth_arsize),
//                                        .eth_arvalid(eth_arvalid),

//                                        .eth_awaddr(eth_awaddr),
//                                        .eth_awburst(eth_awburst),
//                                        .eth_awcache(eth_awcache),
//                                        .eth_awid(eth_wid),
//                                        .eth_awlen(eth_awlen),
//                                        .eth_awlock(),
//                                        .eth_awprot(),
//                                        .eth_awqos(),
//                                        .eth_awready(eth_awready),
//                                        .eth_awregion(),
//                                        .eth_awsize(eth_awsize),
//                                        .eth_awvalid(eth_awvalid),

//                                        .eth_bid(eth_wid),
//                                        .eth_bready(eth_bready),
//                                        .eth_bresp(eth_bresp),
//                                        .eth_bvalid(eth_bvalid),
//                                        .eth_rdata(eth_rdata),
//                                        .eth_rid(eth_rid),
//                                        .eth_rlast(eth_rlast),
//                                        .eth_rready(eth_rready),
//                                        .eth_rresp(eth_rresp),
//                                        .eth_rvalid(eth_rvalid),
//                                        .eth_wdata(eth_wdata),
//                                        .eth_wlast(eth_wlast),
//                                        .eth_wready(eth_wready),
//                                        .eth_wstrb(),
//                                        .eth_wvalid(eth_wvalid),
   
   aeths_interconnect u_xbar(.INTERCONNECT_ACLK(clk100),
			     .INTERCONNECT_ARESETN(interconnect_resetn),
			     .S00_AXI_ACLK(clk100),
			     .S00_AXI_ARADDR(axi_dm_mm2s_araddr),
			     .S00_AXI_ARREADY(axi_dm_mm2s_arready),
			     .S00_AXI_ARVALID(axi_dm_mm2s_arvalid),
			     .S00_AXI_ARBURST(axi_dm_mm2s_arburst),
			     .S00_AXI_ARCACHE(axi_dm_mm2s_arcache),
			     .S00_AXI_ARLEN(axi_dm_mm2s_arlen),
			     .S00_AXI_ARSIZE(axi_dm_mm2s_arsize),
                 .S00_AXI_ARPROT(3'h0),
                 .S00_AXI_ARLOCK(1'b0),
                 .S00_AXI_ARQOS(4'h0),
                 
			     .S00_AXI_RDATA(axi_dm_mm2s_rdata),
			     .S00_AXI_RREADY(axi_dm_mm2s_rready),
			     .S00_AXI_RVALID(axi_dm_mm2s_rvalid),
			     .S00_AXI_RRESP(axi_dm_mm2s_rresp),
			     .S00_AXI_RLAST(axi_dm_mm2s_rlast),
			     
			     .S00_AXI_AWVALID(1'b0),
			     .S00_AXI_WVALID(1'b0),
			     .S00_AXI_BREADY(1'b1),
			     
			     .S01_AXI_ACLK(clk100),
			     .S01_AXI_AWADDR(axi_dm_s2mm_awaddr),
			     .S01_AXI_AWREADY(axi_dm_s2mm_awready),
			     .S01_AXI_AWVALID(axi_dm_s2mm_awvalid),
			     .S01_AXI_AWBURST(axi_dm_s2mm_awburst),
			     .S01_AXI_AWCACHE(axi_dm_s2mm_awcache),
			     .S01_AXI_AWLEN(axi_dm_s2mm_awlen),
			     .S01_AXI_AWSIZE(axi_dm_s2mm_awsize),
			     .S01_AXI_AWLOCK(1'b0),
			     .S01_AXI_AWPROT(3'h0),
			     .S01_AXI_AWQOS(4'h0),
			     

			     .S01_AXI_BRESP(axi_dm_s2mm_bresp),
			     .S01_AXI_BREADY(axi_dm_s2mm_bready),
			     .S01_AXI_BVALID(axi_dm_s2mm_bvalid),
			     .S01_AXI_WDATA(axi_dm_s2mm_wdata),
			     .S01_AXI_WLAST(axi_dm_s2mm_wlast),
			     .S01_AXI_WREADY(axi_dm_s2mm_wready),
			     .S01_AXI_WVALID(axi_dm_s2mm_wvalid),
			     .S01_AXI_WSTRB(axi_dm_s2mm_wstrb),
			     
			     .S01_AXI_ARVALID(1'b0),
			     .S01_AXI_RREADY(1'b1),
			     
			     .S02_AXI_ACLK(clk100),
			     .S02_AXI_ARADDR({{19{1'b0}},pbaxi4_araddr}),
			     .S02_AXI_ARREADY(pbaxi4_arready),
			     .S02_AXI_ARVALID(pbaxi4_arvalid),
			     .S02_AXI_ARCACHE(pbaxi4_arcache),
			     .S02_AXI_ARBURST(pbaxi4_arburst),
			     .S02_AXI_ARLEN(pbaxi4_arlen),
			     .S02_AXI_ARSIZE(pbaxi4_arsize),
			     .S02_AXI_ARLOCK(pbaxi4_arlock),
			     .S02_AXI_ARPROT(pbaxi4_arprot),
			     .S02_AXI_ARQOS(pbaxi4_arqos),
			     .S02_AXI_AWADDR({{19{1'b0}},pbaxi4_awaddr}),
			     .S02_AXI_AWREADY(pbaxi4_awready),
			     .S02_AXI_AWVALID(pbaxi4_awvalid),
			     .S02_AXI_AWCACHE(pbaxi4_awcache),
			     .S02_AXI_AWBURST(pbaxi4_awburst),
			     .S02_AXI_AWLEN(pbaxi4_awlen),
			     .S02_AXI_AWSIZE(pbaxi4_awsize),
			     .S02_AXI_AWLOCK(pbaxi4_awlock),
			     .S02_AXI_AWPROT(pbaxi4_awprot),
			     .S02_AXI_AWQOS(pbaxi4_awqos),
			     .S02_AXI_AWID('b0),
			     .S02_AXI_ARID('b0),
			     .S02_AXI_BRESP(pbaxi4_bresp),
			     .S02_AXI_BREADY(pbaxi4_bready),
			     .S02_AXI_BVALID(pbaxi4_bvalid),
			     .S02_AXI_RDATA(pbaxi4_rdata),
			     .S02_AXI_RRESP(pbaxi4_rresp),
			     .S02_AXI_RLAST(pbaxi4_rlast),
			     .S02_AXI_RREADY(pbaxi4_rready),
			     .S02_AXI_RVALID(pbaxi4_rvalid),
			     .S02_AXI_WDATA(pbaxi4_wdata),
			     .S02_AXI_WLAST(pbaxi4_wlast),
			     .S02_AXI_WREADY(pbaxi4_wready),
			     .S02_AXI_WVALID(pbaxi4_wvalid),
			     .S02_AXI_WSTRB(pbaxi4_wstrb),

			     .M00_AXI_ACLK(clk100),
                 // 7 connections
			     .M00_AXI_ARADDR(eth_araddr),
			     .M00_AXI_ARREADY(eth_arready),
			     .M00_AXI_ARVALID(eth_arvalid),
			     .M00_AXI_ARBURST(eth_arburst),
			     .M00_AXI_ARCACHE(eth_arcache),
			     .M00_AXI_ARLEN(eth_arlen),
			     .M00_AXI_ARSIZE(eth_arsize),
			     .M00_AXI_ARID(eth_rid),
                 // 7 connections
			     .M00_AXI_AWADDR(eth_awaddr),
			     .M00_AXI_AWREADY(eth_awready),
			     .M00_AXI_AWVALID(eth_awvalid),
			     .M00_AXI_AWBURST(eth_awburst),
			     .M00_AXI_AWCACHE(eth_awcache),
			     .M00_AXI_AWLEN(eth_awlen),
			     .M00_AXI_AWSIZE(eth_awsize),
			     .M00_AXI_AWID(eth_wid),
                 // 3 connections
			     .M00_AXI_BRESP(eth_bresp),
			     .M00_AXI_BREADY(eth_bready),
			     .M00_AXI_BVALID(eth_bvalid),
			     .M00_AXI_BID(eth_wid),
			     // 5 connections
			     .M00_AXI_RDATA(eth_rdata),
			     .M00_AXI_RRESP(eth_rresp),
			     .M00_AXI_RREADY(eth_rready),
			     .M00_AXI_RVALID(eth_rvalid),
			     .M00_AXI_RLAST(eth_rlast),
			     .M00_AXI_RID(eth_rid),
			     // 4 connections
			     .M00_AXI_WDATA(eth_wdata),
			     .M00_AXI_WLAST(eth_wlast),
			     .M00_AXI_WREADY(eth_wready),
			     .M00_AXI_WVALID(eth_wvalid)
			     );
   
endmodule // axi_ethernet_streamer

			      
			      
			      
