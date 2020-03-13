`timescale 1ns/1ps
// this module implements an 8-bit streaming input/output via UDP
module streaming_udp_ip_wrapper( // Ethernet receive
			   input 	 s_axis_aclk,
			   input 	 s_axis_aresetn,
			   input [7:0] 	 s_axis_rx_tdata,
			   output 	 s_axis_rx_tready,
			   input 	 s_axis_rx_tvalid,
			   input 	 s_axis_rx_tlast,
			   // Ethernet transmit
			   input 	 m_axis_aclk,
			   input 	 m_axis_aresetn,
			   output [7:0]  m_axis_tx_tdata,
			   input 	 m_axis_tx_tready,
			   output 	 m_axis_tx_tvalid,
			   output 	 m_axis_tx_tlast,
			   input 	 mac_address_valid,
			   input [47:0]  mac_address,
			   output [56:0] device_dna,
			   output 	 device_dna_valid,		       				   output [31:0] my_ip_address,
			   output 	 my_ip_valid,
			   input 	 do_dhcp,
			   // Stream path
			   input 	 stream_aclk,
			   input 	 stream_aresetn,
			   output 	 stream_linked,
			   output [7:0]  stream_axis_rx_tdata,
			   output 	 stream_axis_rx_tvalid,
			   input 	 stream_axis_rx_tready,
			   output 	 stream_axis_rx_tlast,
			   input [7:0] 	 stream_axis_tx_tdata,
			   input 	 stream_axis_tx_tvalid,
			   output 	 stream_axis_tx_tready,
			   input 	 stream_axis_tx_tlast );
   
   parameter DEBUG = "TRUE";

   reg [31:0] 				 destination_ip = {32{1'b0}};
   reg [15:0] 				 destination_port = {16{1'b0}};
   wire [15:0] 				 source_port = 16'd1060;
   wire [15:0] 				 data_length = 16'd1;

   wire [7:0] 				 arp_packet_count;
   wire [7:0] 				 ip_packet_count;   

   wire [15:0] 				 ip_rx_hdr_data_length;
   wire 				 ip_rx_hdr_is_broadcast;
   wire 				 ip_rx_hdr_is_valid;
   wire [3:0] 				 ip_rx_hdr_last_error_code;
   wire [7:0] 				 ip_rx_hdr_num_frame_errors;
   wire [31:0] 				 ip_rx_hdr_src_ip_addr;


   wire 				 udp_rx_data_in_start;
   wire [7:0] 				 udp_rx_data_in;
   wire 				 udp_rx_data_in_valid;
   wire 				 udp_rx_data_in_last;
   wire [15:0] 				 udp_rx_src_port;
   wire [15:0] 				 udp_rx_dst_port;
   wire [31:0] 				 udp_rx_src_ip_addr;
   wire 				 udp_rx_is_valid;   
   
   wire [1:0]           grant_idx;
   
   wire [15:0] 				 udp_tx_length_vec[3:0];
   wire [15:0] 				 udp_tx_dst_port_vec[3:0];
   wire [15:0] 				 udp_tx_src_port_vec[3:0];
   wire [31:0] 				 udp_tx_dst_ip_addr_vec[3:0];
   wire  				 udp_tx_data_out_valid_vec[3:0];
   wire  				 udp_tx_data_out_last_vec[3:0];
   wire [7:0] 				 udp_tx_data_out_vec[3:0];
   
   // multiplex... (3 -> 1)
   wire [15:0] 				 udp_tx_length = udp_tx_length_vec[grant_idx];
   wire [15:0] 				 udp_tx_dst_port = udp_tx_dst_port_vec[grant_idx];
   wire [15:0] 				 udp_tx_src_port = udp_tx_src_port_vec[grant_idx];
   wire [31:0] 				 udp_tx_dst_ip_addr = udp_tx_dst_ip_addr_vec[grant_idx];
   wire 				 udp_tx_data_out_valid = udp_tx_data_out_valid_vec[grant_idx];
   wire 				 udp_tx_data_out_last = udp_tx_data_out_last_vec[grant_idx];
   wire [7:0] 				 udp_tx_data_out = udp_tx_data_out_vec[grant_idx];
   // and demultiplex (1->3). We handle ready, the arbiter handles start and result.
   wire 				 udp_tx_data_out_ready;
   wire 				 udp_tx_start;
   wire [1:0] 				 udp_tx_result;   
   
   // UDP/IP core for a fake stream interface.
   wire [8:0] 				 dhcp_out_length;
   wire [15:0] 				 dhcp_out_dst_port;
   wire [15:0] 				 dhcp_out_src_port = 68;
   wire [31:0] 				 dhcp_out_dst_ip_addr;
   // out has data/last/valid/ready (AXI-Stream type), plus start/grant/result
   wire 				 dhcp_out_ready;
   wire 				 dhcp_out_last;
   wire [7:0] 				 dhcp_out_data;
   wire 				 dhcp_out_valid;
   wire 				 dhcp_out_grant;   
   wire 				 dhcp_out_start;
   wire [1:0] 				 dhcp_out_result;
   // in just has data/last/valid (no ready), plus start
   wire 				 dhcp_in_valid;
   wire [7:0] 				 dhcp_in_data;
   wire 				 dhcp_in_last;   
   wire 				 dhcp_in_start;
   
   // 'HY' port handler (control port)
   wire [6:0] 				 control_out_length;
   wire [15:0] 				 control_out_dst_port;
   wire [15:0] 				 control_out_src_port = 18521;
   wire [31:0] 				 control_out_dst_ip_addr;
   // out has data/last/valid/ready (AXI-Stream type), plus start/grant/result
   wire 				 control_out_last;
   wire [7:0] 				 control_out_data;
   wire 				 control_out_valid;
   wire 				 control_out_ready;
   wire 				 control_out_grant;
   wire 				 control_out_start;   
   wire [1:0] 				 control_out_result;
   // in just has data/last/valid (no ready), plus start
   wire 				 control_in_start;   
   wire 				 control_in_valid;
   wire 				 control_in_last;
   wire [7:0] 				 control_in_data;

   // 'HX' port handler (stream port)
   wire [9:0] 				 stream_out_length;
   wire [15:0] 				 stream_out_dst_port;
   wire [15:0] 				 stream_out_src_port = 18520;
   wire [31:0] 				 stream_out_dst_ip_addr;
   wire [1:0] 				 stream_ready;
   // out has data/last/valid/ready (AXI-Stream type), plus start/grant/result
   wire 				 stream_out_last;
   wire [7:0] 				 stream_out_data;
   wire 				 stream_out_valid;
   wire 				 stream_out_ready;
   wire 				 stream_out_grant;   
   wire 				 stream_out_start;
   wire [1:0] 				 stream_out_result;
   // in just has data/last/valid (no ready), plus start   
   wire 				 stream_in_start;   
   wire 				 stream_in_valid;
   wire 				 stream_in_last;
   wire [7:0] 				 stream_in_data;
   
   wire 				 second_timer;
   // want to demultiplex UDP, so generate an index.
   // dhcp = 0, control = 1, stream = 2 (and stream duplicated at 3, not that it matters)
   assign grant_idx =  { stream_out_grant, control_out_grant };

`define UDP_MUX( idx , prefix , length_nbits ) \
   assign udp_tx_length_vec[ idx ] = {{(16 - length_nbits ) {1'b0}}, prefix``out_length }; \
   assign udp_tx_dst_port_vec[ idx ] = prefix``out_dst_port;                               \
   assign udp_tx_src_port_vec[ idx ] = prefix``out_src_port;                               \
   assign udp_tx_dst_ip_addr_vec[ idx ] = prefix``out_dst_ip_addr;                         \
   assign udp_tx_data_out_valid_vec[ idx ] = prefix``out_valid;                        \
   assign udp_tx_data_out_last_vec[ idx ] = prefix``out_last;                          \
   assign udp_tx_data_out_vec[ idx ] = prefix``out_data

`define UDP_DEMUX( portno , prefix ) \
   assign prefix``in_data = udp_rx_data_in;                                           \
   assign prefix``in_valid = udp_rx_data_in_valid && (udp_rx_dst_port == portno);     \
   assign prefix``in_last = udp_rx_data_in_last && (udp_rx_dst_port == portno);       \
   assign prefix``in_start = udp_rx_data_in_start && (udp_rx_dst_port == portno)   
   
   
   `UDP_MUX( 0 , dhcp_ , 9 );
   `UDP_DEMUX( 68 , dhcp_ );   
   assign dhcp_out_ready = (dhcp_out_grant) && udp_tx_data_out_ready;

   
   `UDP_MUX( 1 , control_ , 7 );
   `UDP_DEMUX( 18521 , control_ );   
   assign control_out_ready = (control_out_grant) && udp_tx_data_out_ready;
   
   `UDP_MUX( 2 , stream_ , 10 );
   `UDP_DEMUX( 18520 , stream_ );   
   assign stream_out_ready = (stream_out_grant) && udp_tx_data_out_ready;   

   // This is fake, it just covers the (impossible) grant_idx = 11 case
   `UDP_MUX( 3, stream_ , 10 );   

   // just start a damn dhcp process a few seconds after power on
   reg 					 auto_dhcp = 0;
   reg 					 auto_dhcp_done = 0;
   reg [2:0] 				 auto_dhcp_timer = {3{1'b0}};
   wire [3:0] 				 auto_dhcp_timer_plus_one = auto_dhcp_timer + 1;
   wire 				 dhcp_reset;
   wire                  hycontrol_dhcp_reset;
   
   always @(posedge m_axis_aclk) begin
      if (!m_axis_aresetn) auto_dhcp_done <= 0;
      else if (auto_dhcp_timer_plus_one[3] && second_timer) auto_dhcp_done <= 1;

      auto_dhcp <= auto_dhcp_timer_plus_one[3] && second_timer;

      if (!m_axis_aresetn) auto_dhcp_timer <= {4{1'b0}};
      else if (!auto_dhcp_done && second_timer) auto_dhcp_timer <= auto_dhcp_timer_plus_one;
   end
   
   wire [31:0] dhcp_ip_address;
   wire        dhcp_ip_valid;
   wire [31:0] vio_ip_address;
   wire        vio_ip_force;
   assign      dhcp_reset = (vio_ip_force || hycontrol_dhcp_reset);

   dhcp_top u_dhcp(.clk(m_axis_aclk),
						.do_dhcp(do_dhcp || auto_dhcp),
						.reset(!m_axis_aresetn || dhcp_reset || !mac_address_valid),
						.second(second_timer),
						// data/valid/last plus start
						.udp_in_start(dhcp_in_start),
						.udp_in_data(dhcp_in_data),
						.udp_in_valid(dhcp_in_valid),
						.udp_in_last(dhcp_in_last),
						// data/valid/ready/last plus start/result
						.udp_out_ready(dhcp_out_ready),
						.udp_out_data(dhcp_out_data),
						.udp_out_last(dhcp_out_last),
						.udp_out_valid(dhcp_out_valid),
						.udp_out_length(dhcp_out_length),
						.udp_out_result(dhcp_out_result),
						.udp_out_start(dhcp_out_start),	
						.udp_out_dst_ip_addr(dhcp_out_dst_ip_addr),
						.udp_out_dst_port(dhcp_out_dst_port),
						.mac_address(mac_address),
						.ip_address(dhcp_ip_address),
						.ip_address_valid(dhcp_ip_valid));
   wire [31:0] static_ip_address;
   wire        static_ip_valid;
   wire [31:0] stream_ip_addr;
   wire [15:0] stream_port;
   
   hycontrol_top u_control(.clk(m_axis_aclk),.reset(!m_axis_aresetn),.second(second_timer),.device_dna_o(device_dna),.device_dna_valid_o(device_dna_valid),
			   .dhcp_reset(hycontrol_dhcp_reset),
			   .ext_ip_address((vio_ip_force) ? vio_ip_address : dhcp_ip_address),
			   .ext_ip_force(vio_ip_force),
			   .static_ip_address(static_ip_address),
			   .static_ip_valid(static_ip_valid),
			   // data/valid/last plus start
			   .udp_in_start(control_in_start),
			   .udp_in_data(control_in_data),
			   .udp_in_valid(control_in_valid),
			   .udp_in_last(control_in_last),
			   .udp_in_src_ip_addr(udp_rx_src_ip_addr),
               .udp_in_src_port(udp_rx_src_port),
			   // data/valid/ready/last plus start/result			   
			   .udp_out_ready(control_out_ready),
			   .udp_out_data(control_out_data),
			   .udp_out_last(control_out_last),
			   .udp_out_valid(control_out_valid),
			   .udp_out_start(control_out_start),
			   .udp_out_result(control_out_result),
			   .udp_out_dst_ip_addr(control_out_dst_ip_addr),
			   .udp_out_dst_port(control_out_dst_port),
			   .udp_out_length(control_out_length),
			   .stream_linked(stream_linked),
			   .stream_ip_address(stream_ip_addr),
			   .stream_udp_port(stream_port));

   ethstream_top u_stream(.clk(m_axis_aclk),.reset(!m_axis_aresetn),
			  .stream_linked(stream_linked),
			  .stream_ip_addr(stream_ip_addr),
			  .stream_port(stream_port),
			  .udp_in_start(stream_in_start),
			  .udp_in_data(stream_in_data),
			  .udp_in_valid(stream_in_valid),
			  .udp_in_last(stream_in_last),
			  // data/valid/ready/last plus start/result
			  .udp_out_ready(stream_out_ready),
			  .udp_out_data(stream_out_data),
			  .udp_out_last(stream_out_last),
			  .udp_out_valid(stream_out_valid),
			  .udp_out_start(stream_out_start),
			  .udp_out_result(stream_out_result),
			  .udp_out_dst_ip_addr(stream_out_dst_ip_addr),
			  .udp_out_dst_port(stream_out_dst_port),
			  .udp_out_length(stream_out_length),

			  .m_axis_tdata(stream_axis_rx_tdata),
			  .m_axis_tvalid(stream_axis_rx_tvalid),
			  .m_axis_tready(stream_axis_rx_tready),
			  .m_axis_tlast(stream_axis_rx_tlast),
			  .s_axis_tdata(stream_axis_tx_tdata),
			  .s_axis_tvalid(stream_axis_tx_tvalid),
			  .s_axis_tready(stream_axis_tx_tready),
			  .s_axis_tlast(stream_axis_tx_tlast)
			  );

   udp_port_arbiter u_arbiter(.clk(m_axis_aclk),.reset(!m_axis_aresetn),
			      .req_A(dhcp_out_start),.gnt_A(dhcp_out_grant),.status_A(dhcp_out_result),
			      .req_B(control_out_start),.gnt_B(control_out_grant),.status_B(control_out_result),
			      .req_C(stream_out_start),.gnt_C(stream_out_grant),.status_C(stream_out_result),
			      .req_Y(udp_tx_start), .status_Y(udp_tx_result));


    generate
        if (DEBUG == "TRUE" || DEBUG == "ALL" || DEBUG == "ILA") begin : ILA
            // The VIO's pretty useful all the time and it's a lightweight core.
            // The ILA's not that useful once things are working, so we allow them to be enabled separately.
            wire [2:0] udp_start = { dhcp_out_start, control_out_start, stream_out_start };
            wire [2:0] udp_grant = { dhcp_out_grant, control_out_grant, stream_out_grant };
            stream_debug_ila u_ila(.clk(m_axis_aclk),
                                    .probe0(udp_tx_data_out),
                                    .probe1(udp_tx_data_out_valid),
                                    .probe2(udp_tx_data_out_ready),
                                    .probe3(udp_tx_data_out_last),
                                    .probe4(udp_tx_dst_port),
                                    .probe5(udp_rx_data_in),
                                    .probe6(udp_rx_data_in_valid),
                                    .probe7(udp_rx_data_in_start),
                                    .probe8(udp_rx_data_in_last),
                                    .probe9(udp_rx_dst_port),
                                    .probe10(stream_axis_rx_tdata),
                                    .probe11(stream_in_valid),
                                    .probe12(stream_axis_rx_tready),
                                    .probe13(udp_start),
                                    .probe14(udp_grant),
                                    .probe15(udp_tx_result));
        end
        if (DEBUG == "TRUE" || DEBUG == "ALL" || DEBUG == "VIO") begin : VIO
            stream_debug_vio u_vio(.clk(m_axis_aclk),
                                    .probe_out0(vio_ip_address),
                                    .probe_out1(vio_ip_force),
                                    .probe_in0(dhcp_ip_valid),
                                    .probe_in1(my_ip_address),
                                    .probe_in2(stream_linked),
                                    .probe_in3(stream_ip_addr),
                                    .probe_in4(stream_port),
                                    .probe_in5(device_dna));
        end else begin : DUM
            assign vio_ip_address = {32{1'b0}};
            assign vio_ip_force = 0;
        end
   endgenerate

    // sigh, shrink the crap out of this
   udp_complete_nomac_wrapper #(.MAX_ARP_ENTRIES(32),.CLOCK_FREQ(100000000)) u_udp(.rx_clk(m_axis_aclk),.tx_clk(m_axis_aclk),.reset(!m_axis_aresetn || !mac_address_valid),
				    .sec_timer(second_timer),
				    .mac_tx_tdata(m_axis_tx_tdata),
				    .mac_tx_tready(m_axis_tx_tready),
				    .mac_tx_tvalid(m_axis_tx_tvalid),
				    .mac_tx_tlast(m_axis_tx_tlast),
				    .mac_rx_tdata(s_axis_rx_tdata),
				    .mac_rx_tready(s_axis_rx_tready),
				    .mac_rx_tvalid(s_axis_rx_tvalid),
				    .mac_rx_tlast(s_axis_rx_tlast),

				    .our_ip_address(my_ip_address),
				    .our_mac_address(mac_address),
				    .arp_pkt_count(arp_packet_count),
				    .ip_pkt_count(ip_packet_count),

				    .ip_rx_hdr_data_length(ip_rx_hdr_data_length),
				    .ip_rx_hdr_is_broadcast(ip_rx_hdr_is_broadcast),
				    .ip_rx_hdr_is_valid(ip_rx_hdr_is_valid),
				    .ip_rx_hdr_last_error_code(ip_rx_hdr_last_error_code),
				    .ip_rx_hdr_num_frame_errors(ip_rx_hdr_num_frame_errors),
				    .ip_rx_hdr_src_ip_addr(ip_rx_hdr_src_ip_addr),

				    .udp_tx_dst_ip_addr(udp_tx_dst_ip_addr),
				    .udp_tx_dst_port(udp_tx_dst_port),
				    .udp_tx_src_port(udp_tx_src_port),
				    .udp_tx_data_length(udp_tx_length),
				    .udp_tx_checksum('b0),

				    .udp_tx_start(udp_tx_start),
				    .udp_tx_result(udp_tx_result),

				    .udp_tx_data_out(udp_tx_data_out),
				    .udp_tx_data_out_ready(udp_tx_data_out_ready),
				    .udp_tx_data_out_valid(udp_tx_data_out_valid),
				    .udp_tx_data_out_last(udp_tx_data_out_last),

				    .udp_rx_start(udp_rx_data_in_start),
				    .udp_rx_data_in(udp_rx_data_in),
				    .udp_rx_data_in_valid(udp_rx_data_in_valid),
				    .udp_rx_data_in_last(udp_rx_data_in_last),
				    .udp_rx_src_port(udp_rx_src_port),
				    .udp_rx_dst_port(udp_rx_dst_port),
				    .udp_rx_src_ip_addr(udp_rx_src_ip_addr),
				    .udp_rx_is_valid(udp_rx_is_valid));

   // VIO IP Force overrides DHCP and the static IP assignment.
   assign my_ip_address = (vio_ip_force) ? vio_ip_address : ((dhcp_reset) ? static_ip_address : dhcp_ip_address);
   assign my_ip_valid = (vio_ip_force) ? 1'b1 : ((dhcp_reset) ? static_ip_valid : dhcp_ip_valid);
   
endmodule
			   
