`timescale 1ns/1ps
// Ethernet wrapper. Takes the streaming Ethernet core,
// and does:
// 16-bit tx path -> UDP flow buffer -> 8-bit tx path plus length
// 8-bit rx path -> 16-bit rx path
// It also generates tuser on the inbound path.
module arty_ethernet_wrap( input aclk,
                          input 	aresetn,
                          input 	ethclk,
                          input 	ethresetn,
                          input 	refclk,
                                                    
                          input [15:0] 	s_axis_tdata,
                          input 	s_axis_tvalid,
                          input 	s_axis_tlast,
                          input 	s_axis_tuser,
                          output 	s_axis_tready,
                          
                          output [15:0] m_axis_tdata,
                          output 	m_axis_tvalid,
                          output 	m_axis_tlast,
                          output 	m_axis_tuser,
                          input 	m_axis_tready,
			  
			  input 	MII_COL,
			  input 	MII_CRS,
			  output 	MII_RST_N,

			  input 	MII_RX_DV,
			  input 	MII_RX_ER,
			  input 	MII_RX_CLK,
			  input [3:0] 	MII_RXD,

			  input 	MII_TX_CLK,
			  output [3:0] 	MII_TXD,
			  output 	MII_TX_EN,

                          output 	MDIO_MDC,
                          inout 	MDIO_MDIO
                          );
                          
    parameter [47:0] MAC_ADDRESS = {48{1'b0}};                          
    parameter DEBUG = "TRUE";
                          

    wire [57:0] device_dna;
    wire stream_linked;                          
    (* ASYNC_REG = "TRUE" *)
    reg stream_linked_aclk_sync = 0;
    (* ASYNC_REG = "TRUE" *)
    reg stream_linked_aclk = 0;
    reg stream_active = 0;
    reg feed_transmit_data = 0;
    reg in_a_packet = 0;
   
    reg eth_rx_tuser = 0;
    
    // if stream's not linked, we just dump everything. When stream becomes linked, we make sure we're not in a packet,
    // and then we let things flow. Note that this can cause a partial packet at termination, which is why we fake generate
    // a 'tlast' at the end, by delaying stream linking by a clock.
    wire        allow_data = (feed_transmit_data || (stream_linked_aclk && !in_a_packet));
    wire [15:0] flowin_tdata = s_axis_tdata;
    wire        flowin_tvalid = s_axis_tvalid && allow_data;
    wire        flowin_tready;
    wire        flowin_tlast = s_axis_tlast || !stream_linked_aclk;
    wire        flowin_tuser = s_axis_tuser;
    assign      s_axis_tready = (allow_data) ? flowin_tready : 1'b1;
    
    wire [15:0] flowout_tdata;
    wire        flowout_tvalid;
    wire        flowout_tready;
    wire        flowout_tlast;

    wire [7:0]   eth_rx_tdata;
    wire         eth_rx_tready;
    wire         eth_rx_tvalid;
    wire         eth_rx_tlast;
    
    wire [7:0] eth_tx_tdata;
    wire       eth_tx_tvalid;
    wire       eth_tx_tlast;
    wire        eth_tx_tready;
    
    always @(posedge aclk) begin
        stream_linked_aclk_sync <= stream_linked;
        stream_linked_aclk <= stream_linked_aclk_sync;
        stream_active <= stream_linked_aclk;
        
        if (!aresetn) in_a_packet <= 0;
        else if (m_axis_tvalid && m_axis_tready) in_a_packet <= !m_axis_tlast;
        
        if (stream_active && !in_a_packet) feed_transmit_data <= 1;
        else if (!stream_active) feed_transmit_data <= 0;        

        // start of frame begins with first outgoing data, then only restarts
        // by the end.
        if (!stream_active) eth_rx_tuser <= 1;
        else if (eth_rx_tvalid && eth_rx_tready) eth_rx_tuser <= eth_rx_tlast;
    end        

    tof_udp_flow_buffer u_flow(.s_axis_aclk(aclk),
                               .s_axis_aresetn(aresetn),
                               .s_axis_tdata(flowin_tdata),
                               .s_axis_tvalid(flowin_tvalid),
                               .s_axis_tuser(flowin_tuser),
                               .s_axis_tlast(flowin_tlast),
                               .s_axis_tready(flowin_tready),
                               
                               .m_axis_aclk(ethclk),
                               .m_axis_tdata(flowout_tdata),
                               .m_axis_tvalid(flowout_tvalid),
                               .m_axis_tready(flowout_tready),
                               .m_axis_tuser(),
                               .m_axis_tlast(flowout_tlast));
    eth_streamout_converter u_out_convert(  .aclk(ethclk),.aresetn(ethresetn),
                                            .s_axis_tdata(flowout_tdata),
                                            .s_axis_tvalid(flowout_tvalid),
                                            .s_axis_tready(flowout_tready),
                                            .s_axis_tlast(flowout_tlast),
                                            .m_axis_tdata(eth_tx_tdata),
                                            .m_axis_tvalid(eth_tx_tvalid),
                                            .m_axis_tready(eth_tx_tready),
                                            .m_axis_tlast(eth_tx_tlast));
    
    wire [1:0] eth_convert_tuser;
    eth_streamin_converter u_in_convert( .aclk(ethclk),.aresetn(ethresetn),
                                         .s_axis_tdata(eth_rx_tdata),
                                         .s_axis_tvalid(eth_rx_tvalid),
                                         .s_axis_tready(eth_rx_tready),
                                         .s_axis_tlast(eth_rx_tlast),
                                         .s_axis_tuser(eth_rx_tuser),
                                         .m_axis_tdata(m_axis_tdata),
                                         .m_axis_tvalid(m_axis_tvalid),
                                         .m_axis_tready(m_axis_tready),
                                         .m_axis_tuser(eth_convert_tuser),
                                         .m_axis_tkeep(), // do NOT care
                                         .m_axis_tlast(m_axis_tlast));
    assign m_axis_tuser = |eth_convert_tuser;
    
    wire [31:0] my_ip_address;
    wire        my_ip_valid;
    wire        do_dhcp;
    wire [7:0]  ethstreamer_rx_tdata;
    wire        ethstreamer_rx_tready;
    wire        ethstreamer_rx_tvalid;
    wire        ethstreamer_rx_tlast;
    wire [7:0]  ethstreamer_tx_tdata;
    wire        ethstreamer_tx_tready;
    wire        ethstreamer_tx_tvalid;
    wire        ethstreamer_tx_tlast;
    streaming_udp_ip_wrapper #(.DEBUG("TRUE"),.MAC_ADDRESS(MAC_ADDRESS)) u_udp_streamer( .s_axis_aclk(ethclk), .s_axis_aresetn(ethresetn),
                              .s_axis_rx_tdata(ethstreamer_rx_tdata),
                              .s_axis_rx_tready(ethstreamer_rx_tready),
                              .s_axis_rx_tvalid(ethstreamer_rx_tvalid),
                              .s_axis_rx_tlast(ethstreamer_rx_tlast),
                              .m_axis_aclk(ethclk),.m_axis_aresetn(ethresetn),
                              .m_axis_tx_tdata(ethstreamer_tx_tdata),
                              .m_axis_tx_tready(ethstreamer_tx_tready),
                              .m_axis_tx_tvalid(ethstreamer_tx_tvalid),
                              .m_axis_tx_tlast(ethstreamer_tx_tlast),
                              .my_ip_address(my_ip_address),
                              .my_ip_valid(my_ip_valid),
                              .do_dhcp(do_dhcp),
                              .device_dna(device_dna),
                              .stream_aclk(ethclk),.stream_aresetn(ethresetn),.stream_linked(stream_linked),
                              .stream_axis_rx_tdata(eth_rx_tdata),
                              .stream_axis_rx_tvalid(eth_rx_tvalid),
                              .stream_axis_rx_tready(eth_rx_tready),
                              .stream_axis_rx_tlast(eth_rx_tlast),
                              .stream_axis_tx_tdata(eth_tx_tdata),
                              .stream_axis_tx_tvalid(eth_tx_tvalid),
                              .stream_axis_tx_tready(eth_tx_tready),
                              .stream_axis_tx_tlast(eth_tx_tlast));
    wire mdio_mdio_i;
    wire mdio_mdio_o;
    wire mdio_mdio_t;
    axi_ethernet_streamer u_ethernet_axi_stream( .clk100(ethclk),
                           .locked(ethresetn),
                           .resetn(ethresetn),
                           .reset_out(),
                           .m_axis_eth_rx_tdata(ethstreamer_rx_tdata),
                           .m_axis_eth_rx_tvalid(ethstreamer_rx_tvalid),
                           .m_axis_eth_rx_tready(ethstreamer_rx_tready),
                           .m_axis_eth_rx_tlast(ethstreamer_rx_tlast),
                           .s_axis_eth_tx_tdata(ethstreamer_tx_tdata),
                           .s_axis_eth_tx_tlast(ethstreamer_tx_tlast),
                           .s_axis_eth_tx_tvalid(ethstreamer_tx_tvalid),
                           .s_axis_eth_tx_tready(ethstreamer_tx_tready),
                           .mac_address(MAC_ADDRESS),
                           .mdio_mdc(MDIO_MDC),
                           .mdio_mdio_i(mdio_mdio_i),
                           .mdio_mdio_o(mdio_mdio_o),
                           .mdio_mdio_t(mdio_mdio_t),
                           .mii_col(MII_COL),
                           .mii_crs(MII_CRS),
                           .mii_rst_n(MII_RST_N),
                           .mii_rx_clk(MII_RX_CLK),
                           .mii_rx_dv(MII_RX_DV),
                           .mii_rx_er(MII_RX_ER),
                           .mii_rxd(MII_RXD),
                           .mii_tx_clk(MII_TX_CLK),
                           .mii_tx_en(MII_TX_EN),
                           .mii_txd(MII_TXD));
    IOBUF u_mdio(.I(mdio_mdio_o),.O(mdio_mdio_i),.T(mdio_mdio_t),.IO(MDIO_MDIO));

endmodule                          
