`timescale 1ns / 1ps

// The TOF UDP flow buffer takes in variable-length
// packets and prepends the total length out to another
// clock domain. This requires 2 FIFOs, one for the
// data, and another for the packet length.
// The data buffer is 4096 bytes long (1 BRAM)
// and the length buffer is 32 entries deep (implemented
// in slices). 
//
// The way this works is relatively simple, it selects
// the flow buffer unless tuser=1 && !wrote_length.
// which of course means no single-word packets, either.
// This literally will flat-out break with packets
// longer than 2048 words or 1 word packets. So like,
// don't do that. (Our shortest packets are 4 words)
//
//
// NOTE: This ONLY works with the HELIX AXI4-Stream framing
// (tuser=1 on the first word). 
module tof_udp_flow_buffer( input         s_axis_aclk,			    
			    input 	  s_axis_aresetn,
			    input [15:0]  s_axis_tdata,
			    output 	  s_axis_tready,
			    input 	  s_axis_tvalid,
			    input 	  s_axis_tlast,
			    input 	  s_axis_tuser, 

			    input 	  m_axis_aclk,
			    output [15:0] m_axis_tdata,
			    output 	  m_axis_tvalid,
			    input 	  m_axis_tready,
			    output 	  m_axis_tuser,
			    output 	  m_axis_tlast );
    // can't exceed 2048 words anyway, this trims the register slices used			    
    localparam MAX_LENGTH_BITS = 11;			    
    // "s_" prefixed regs are in slave clock domain (sysclk)
    // "m_" prefixed regs are in master clock domain (ethclk)
                
    reg [MAX_LENGTH_BITS-1:0]    s_packet_length_counter = {MAX_LENGTH_BITS{1'b0}};
    reg          s_capture_length = 0;
    reg          m_wrote_length = 0;   
    // inbound to flow buffer            
    wire [15:0]  flow_tdata;
    wire         flow_tready;
    wire         flow_tvalid;
    wire         flow_tlast;
    wire         flow_tuser;
    // inbound to length buffer
    wire [15:0]  length_tdata;
    wire         length_tready;
    wire         length_tvalid;
    
    // outbound from flow buffer (ethclk)
    wire [15:0]  flowout_tdata;
    wire         flowout_tready;
    wire         flowout_tvalid;
    wire         flowout_tlast;
    wire         flowout_tuser;
    // outbound from length buffer (ethclk)
    wire [15:0]  lengthout_tdata;
    wire         lengthout_tready;
    wire         lengthout_tvalid;
    
    // couple the streams, only flows if both can accept data
    assign       flow_tdata = s_axis_tdata;
    assign       flow_tvalid = (s_axis_tvalid && length_tready);
    assign       s_axis_tready = flow_tready && length_tready;
    assign       flow_tlast = s_axis_tlast;
    assign       flow_tuser = s_axis_tuser;
    
    assign       length_tdata = {{(16-MAX_LENGTH_BITS-1){1'b0}},s_packet_length_counter,1'b0};
    assign       length_tvalid = s_capture_length;
    // length_tready is merged with flow_tready
    
    assign       m_axis_tdata = (flowout_tuser && !m_wrote_length) ? lengthout_tdata : flowout_tdata;
    assign       m_axis_tvalid = (flowout_tuser && !m_wrote_length) ? lengthout_tvalid : flowout_tvalid;
    assign       lengthout_tready = (flowout_tuser && !m_wrote_length) ? m_axis_tready : 1'b0;
    assign       flowout_tready = (flowout_tuser && !m_wrote_length) ? 1'b0 : m_axis_tready;
    assign       m_axis_tlast = flowout_tlast;
    assign       m_axis_tuser = flowout_tuser && !m_wrote_length;

    always @(posedge m_axis_aclk) begin
        if (flowout_tuser) begin
            if (lengthout_tready && lengthout_tvalid) m_wrote_length <= 1;
        end else m_wrote_length <= 0;
    end

    always @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) s_packet_length_counter <= {MAX_LENGTH_BITS{1'b0}};
        else if (s_axis_tready && s_axis_tvalid) begin
            if (s_axis_tuser) s_packet_length_counter <= 'd1;
            else s_packet_length_counter <= s_packet_length_counter + 1;
        end
        
        s_capture_length <= (s_axis_tready && s_axis_tvalid && s_axis_tlast);
    end
    wire udp_flow_read = flowout_tvalid && flowout_tready;
    wire udp_flow_full;
    assign flow_tready = !udp_flow_full;
    wire udp_flow_write = flow_tready && flow_tvalid;
    udp_flow_buffer u_flow( .wr_clk(s_axis_aclk),
                            .rst(!s_axis_aresetn),
                            .din({flow_tuser,flow_tlast,flow_tdata}),
                            .full(udp_flow_full),
                            .wr_en(udp_flow_write),
                            .dout({flowout_tuser,flowout_tlast,flowout_tdata}),
                            .valid(flowout_tvalid),
                            .rd_en(udp_flow_read),
                            .rd_clk(m_axis_aclk));
    udp_length_buffer u_length( .s_aclk(s_axis_aclk),
                                .s_aresetn(s_axis_aresetn),
                                .wr_rst_busy(),.rd_rst_busy(),
                                .s_axis_tdata(length_tdata),
                                .s_axis_tready(length_tready),
                                .s_axis_tvalid(length_tvalid),
                                
                                .m_aclk(m_axis_aclk),
                                
                                .m_axis_tdata(lengthout_tdata),
                                .m_axis_tready(lengthout_tready),
                                .m_axis_tvalid(lengthout_tvalid));
   // then on the output, when tuser=1 the length is peeled
   // off and the remaining data is shoved into the stream
   // resizer to go from 2 bytes->8 bytes, and out the Ethernet
endmodule			    
