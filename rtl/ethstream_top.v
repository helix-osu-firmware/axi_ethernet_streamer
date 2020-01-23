`timescale 1ns/1ps

module ethstream_top( input clk,
		      input 	    reset,
		      input 	    stream_linked,
		      input [31:0]  stream_ip_addr,
		      input [15:0]  stream_port,

		      input 	    udp_in_start,
		      input [7:0]   udp_in_data,
		      input 	    udp_in_valid,
		      input 	    udp_in_last,

		      input 	    udp_out_ready,
		      output [7:0]  udp_out_data,
		      output 	    udp_out_last,
		      output 	    udp_out_valid,
		      output 	    udp_out_start,
		      input [1:0]   udp_out_result,
		      output [31:0] udp_out_dst_ip_addr,
		      output [15:0] udp_out_dst_port,
		      output [15:0] udp_out_length,
		      // I guess nominally this could be
		      // asynchronous or something but for now it's not.
		      output [7:0]  m_axis_tdata,
		      output 	    m_axis_tvalid,
		      output 	    m_axis_tlast,
		      input 	    m_axis_tready,

		      input [7:0]   s_axis_tdata,
		      input 	    s_axis_tvalid,
		      output 	    s_axis_tready,
		      input 	    s_axis_tlast
		      );

   // this is actually a pretty darn easy state machine
   reg [15:0] 			    udp_length = {16{1'b0}};
   localparam FSM_BITS = 3;
   localparam [FSM_BITS-1:0] IDLE = 0;
   localparam [FSM_BITS-1:0] LSB_LENGTH = 1;
   localparam [FSM_BITS-1:0] MSB_LENGTH = 2;
   localparam [FSM_BITS-1:0] REQUEST = 3;
   localparam [FSM_BITS-1:0] STREAM = 4;   
   localparam [FSM_BITS-1:0] FINISH = 5;   
   reg [FSM_BITS-1:0] 		    state = IDLE;

   always @(posedge clk) begin
      if (reset) state <= IDLE;      
      case (state)
        IDLE: if (s_axis_tvalid && stream_linked) state <= LSB_LENGTH;
        LSB_LENGTH: if (s_axis_tvalid) state <= MSB_LENGTH;
        MSB_LENGTH: if (s_axis_tvalid) state <= REQUEST;
        REQUEST: state <= STREAM;
        STREAM: if (s_axis_tlast && s_axis_tvalid && s_axis_tready) state <= FINISH;
        FINISH: if (udp_out_result == 2'b01) state <= IDLE;
      endcase // case (state)

      if (state == LSB_LENGTH && s_axis_tvalid) udp_length[0 +: 8] <= s_axis_tdata;
      if (state == MSB_LENGTH && s_axis_tvalid) udp_length[8 +: 8] <= s_axis_tdata;      
   end // always @ (posedge clk)

   assign udp_out_length = udp_length;
   assign udp_out_dst_ip_addr = stream_ip_addr;
   assign udp_out_dst_port = stream_port;
   assign udp_out_start = (state == REQUEST || state == STREAM || state == FINISH);
   assign udp_out_valid = (state == STREAM) && s_axis_tvalid;
   assign s_axis_tready = (state == LSB_LENGTH || state == MSB_LENGTH 
			   || (state == STREAM && udp_out_ready));
   assign udp_out_last = (s_axis_tlast && state == STREAM);
   assign udp_out_data = s_axis_tdata;

   // The inbound path is just buffered via a FIFO.
   ethstream_rx_fifo u_rxfifo(.s_aclk(clk),
			      .s_aresetn(!stream_linked),
			      .s_axis_tdata(udp_in_data),
			      .s_axis_tvalid(udp_in_valid),			      
			      .s_axis_tready(), // if we overflow the buffer, it's just lost
			      .s_axis_tlast(udp_in_last),
			      .m_axis_tdata(m_axis_tdata),
			      .m_axis_tready(m_axis_tready),
			      .m_axis_tvalid(m_axis_tvalid),
			      .m_axis_tlast(m_axis_tlast));   
   
endmodule // ethstream_top
