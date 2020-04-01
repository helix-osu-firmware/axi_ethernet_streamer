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
		      
   parameter DEBUG = "FALSE";

    localparam [1:0] UDPTX_RESULT_NONE = 2'b00;
    localparam [1:0] UDPTX_RESULT_SENDING = 2'b01;
    localparam [1:0] UDPTX_RESULT_SENT = 2'b11;
    localparam [1:0] UDPTX_RESULT_ERR = 2'b10;

   // this is actually a pretty darn easy state machine,
   // and yet I still managed to screw it up. yay me.
   reg [15:0] 			    udp_length = {16{1'b0}};
   localparam FSM_BITS = 3;
   localparam [FSM_BITS-1:0] IDLE = 0;
   localparam [FSM_BITS-1:0] MSB_LENGTH = 1;
   localparam [FSM_BITS-1:0] REQUEST = 2;
   localparam [FSM_BITS-1:0] STREAM = 3;   
   localparam [FSM_BITS-1:0] FINISH = 4;   
   reg [FSM_BITS-1:0] 		    state = IDLE;

   reg udp_out_start_reg = 0;

   always @(posedge clk) begin
      if (reset) state <= IDLE;      
      case (state)
        IDLE: if (s_axis_tvalid && stream_linked) state <= MSB_LENGTH;
        MSB_LENGTH: if (s_axis_tvalid) state <= REQUEST;
        REQUEST: state <= STREAM;
        STREAM: if (s_axis_tlast && s_axis_tvalid && s_axis_tready) state <= FINISH;
        FINISH: state <= IDLE;
      endcase // case (state)

      if (state == IDLE && s_axis_tvalid) udp_length[0 +: 8] <= s_axis_tdata;
      if (state == MSB_LENGTH && s_axis_tvalid) udp_length[8 +: 8] <= s_axis_tdata;      
      
      // Start goes high when we set the request, and then it clears when we actually get the indication
      // that we're sending. That happens a bit later, but we don't want to hold it through the end.
      if (state == REQUEST) udp_out_start_reg <= 1;
      else if (udp_out_result == UDPTX_RESULT_SENDING) udp_out_start_reg <= 0;
   end // always @ (posedge clk)

   assign udp_out_length = udp_length;
   assign udp_out_dst_ip_addr = stream_ip_addr;
   assign udp_out_dst_port = stream_port;
   assign udp_out_start = udp_out_start_reg;
   assign udp_out_valid = (state == STREAM) && s_axis_tvalid;
   assign s_axis_tready = (state == IDLE || state == MSB_LENGTH 
			   || (state == STREAM && udp_out_ready));
   assign udp_out_last = (s_axis_tlast && state == STREAM);
   assign udp_out_data = s_axis_tdata;

   generate
        if (DEBUG == "TRUE") begin : DBG
            ethstream_tx_debug ila(.clk(clk),
                                   .probe0(s_axis_tdata),
                                   .probe1(s_axis_tvalid),
                                   .probe2(s_axis_tready),
                                   .probe3(s_axis_tlast),
                                   .probe4(state),
                                   .probe5(udp_out_last),
                                   .probe6(udp_out_ready));
        end
   endgenerate
   
   // The inbound path is just buffered via a FIFO. 
   wire fifo_full;
   wire fifo_read = m_axis_tvalid && m_axis_tready;
   wire fifo_write = udp_in_valid && !fifo_full;
   ethstream_rx_fifo u_rxfifo(.clk(clk),.rst(!stream_linked),
                    .din( {udp_in_last,udp_in_data} ),
                    .wr_en(fifo_write),
                    .full(fifo_full),
                    .rd_en(fifo_read),
                    .valid(m_axis_tvalid),
                    .dout( {m_axis_tlast, m_axis_tdata } ));
   
endmodule // ethstream_top
