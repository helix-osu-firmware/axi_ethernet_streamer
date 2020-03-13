`timescale 1ns / 1ps
// UDP control port handler (for the HY port, so stream control)
module hycontrol_top(
        input 	      udp_in_start,
        input [7:0]   udp_in_data,
        input 	      udp_in_valid,
        input 	      udp_in_last,
        input [31:0]  udp_in_src_ip_addr,
        input [15:0]  udp_in_src_port,
        
        input 	      udp_out_ready,
        output [7:0]  udp_out_data,
        output 	      udp_out_last,
        output 	      udp_out_valid,
        output [6:0]  udp_out_length,
        output [31:0] udp_out_dst_ip_addr,
        output [15:0] udp_out_dst_port,
        
        input [1:0]   udp_out_result,
        output 	      udp_out_start,

        // IP address control.
        // The "SI" command assigns a static IP address, overriding any previous DHCP address,
        // and also placing the DHCP port handler into reset.
        // The "DI" command deassigns a static IP address, and asserts/deasserts the DHCP reset
        // so that the DHCP process takes over.
        // Note that both of these are qualified by the device DNA.
        // If ext_ip_force is high, the external IP overrides any internal static.
        // This is for when a VIO sets it.
        input [31:0]  ext_ip_address,
        input 	      ext_ip_force,
        output 	      dhcp_reset,
        output [31:0] static_ip_address,
        output 	      static_ip_valid, 
        
	output 	      stream_linked,
	output [31:0] stream_ip_address,
	output [15:0] stream_udp_port,

	output [56:0] device_dna_o,
	output 	      device_dna_valid_o,
		     
        input 	      clk,
        input 	      reset,
        input 	      second
    );

    parameter DEBUG = "FALSE";

    reg [56:0] device_dna = {57{1'b0}};
    reg device_dna_valid = 0;
   
    // This is the storage for any IP address received by PicoBlaze.
    reg [31:0] my_ip_address = {32{1'b0}};
    // This is the storage when PicoBlaze reads in the IP address. It either comes from
    // the value written before, or the ext_ip_address.
    reg [7:0] ip_addr_byte = {8{1'b0}};
    // Determines whether or not the IP address we send back is our static IP or the external IP.
    // This can be overridden using the ext_ip_force.
    reg use_static_ip = 0;
    // Indicates whether or not the IP is valid.
    reg static_ip_valid_reg = 0;
    
    wire [7:0] ip_control_register = {{6{1'b0}}, static_ip_valid, use_static_ip};
    reg ip_control_access = 0;
    reg [3:0] ip_address_access = {4{1'b0}};
    // OK, new approach here. Simple UDP port handler.
    // When PicoBlaze says it's OK, data that comes in is streamed into a 128-byte buffer (note that this is 1/16 of the program space)
    // inside the program ROM. Otherwise that data's tossed.
    // Address in BRAM is 111 1xxx xxxx = 0x780 for the 8-bit address. The 16-bit address is therefore 11 11xx xxxx = 0x3C0 which means
    // that the program has space for 960 instructions.
    // PicoBlaze can also write into that same buffer, and then have it streamed out to the UDP handler.
    // This should be pretty generically useful for any back/forth UDP handler.

    //% We are going to accept a packet.
    wire going_to_accept_packet;
    //% We are currently accepting a packet.
    reg accepting_packet = 0;
    //% Will accept next packet.
    reg accept_next_packet = 0;
    //% UDP was valid last clock.
    reg udp_in_valid_reg = 0;
    //% UDP start was valid last clock.
    reg udp_in_start_reg = 0;

    //% Packet IP address (either destination, for transmit, or source, for receive)
    reg [31:0] packet_ip_addr = {32{1'b0}};
    //% Packet port (either destination, for transmit, or source, for receive)
    reg [15:0] packet_port = {16{1'b0}};

    //% Bytes to transmit, minus 1, or the final address received (same thing).
    reg [6:0] transmit_packet_length = {7{1'b0}};
    //% Currently transmitting.
    reg transmitting_packet = 0;
    reg transmit_packet_start = 0;
    reg transmitting_packet_data_valid = 0;
    reg [6:0] packet_byte_address = {7{1'b0}};

    wire [7:0] packet_control = {3'b000,transmitting_packet,2'b00, accepting_packet, accept_next_packet};

    reg 	       stream_linked_reg = 0;
    reg [31:0]  stream_ip_address_reg = {32{1'b0}};
    reg [15:0]  stream_udp_port_reg = {16{1'b0}};   
   
    // picoblaze
    wire [11:0] address;
    wire [17:0] instruction;
    wire [7:0] out_port;
    wire [7:0] in_port;
    wire [7:0] port_id;
    wire write_strobe;
    wire k_write_strobe;
    wire [7:0] k_port_id = { (k_write_strobe) ? {4{1'b0}} : port_id[7:4], port_id[3:0] };
    wire read_strobe;
    wire bram_enable;
    wire interrupt = 0;
    wire interrupt_ack;
    
    wire [7:0] inout_port = (read_strobe) ? in_port : out_port;
    

    // The BRAM needs to be banked into four groups of 128.
    wire [6:0] picoblaze_bram_address = port_id[6:0];
    wire picoblaze_bram_access = (port_id[7]);
    wire [10:0] bram_address = {4'b1111, (transmitting_packet || (accepting_packet || going_to_accept_packet)) ? packet_byte_address : picoblaze_bram_address};
    wire [8:0] bram_write_data = (accepting_packet || going_to_accept_packet) ? {1'b0,udp_in_data} : {1'b0,out_port};
    wire bram_write = ((accepting_packet || going_to_accept_packet) && udp_in_valid) || (!(accepting_packet || going_to_accept_packet) && !transmitting_packet && write_strobe && picoblaze_bram_access);
    wire bram_read = !bram_write;
    wire [8:0] bram_read_data;

    // DNA port. This probably doesn't want to go here, but whatever. Works for now.
    reg dna_read;
    reg dna_shift;
    wire dna_dout;
    wire [7:0] dna_register = {{7{1'b0}},dna_dout};

    DNA_PORT u_dna(.DIN(1'b0),.READ(dna_read),.SHIFT(dna_shift),.CLK(clk),.DOUT(dna_dout));
    
    hycontrol_picoblaze_rom_v2 u_rom(.address(address),.instruction(instruction),.clk(clk),.enable(bram_enable));

    hycontrol_buffer u_buf(.clk(clk),.addr(bram_address[4:0]),.dat_i(bram_write_data[7:0]),.dat_o(bram_read_data[7:0]),.write(bram_write),.read(bram_read));
    assign bram_read_data[8] = 1'b0;

    kcpsm6 u_picoblaze(.address(address),.instruction(instruction),.clk(clk),.bram_enable(bram_enable),
                       .sleep(1'b0),.reset(reset),.port_id(port_id),.in_port(in_port),.out_port(out_port),
                       .write_strobe(write_strobe),.read_strobe(read_strobe),.k_write_strobe(k_write_strobe),
                       .interrupt(interrupt), .interrupt_ack(interrupt_ack));

    assign going_to_accept_packet = (accept_next_packet && udp_in_start && !udp_in_start_reg && !transmitting_packet);

    // PORT ASSIGNMENTS 
    // I am super-positive there's a better way to do this, but hey.
    // stream_link       00 0000_x000 
    localparam [7:0] stream_link_mask = 8'b1111_0111;
    localparam [7:0] stream_link_addr = 8'b0000_0000;
    // packet_control    01 0000_x001
    localparam [7:0] packet_control_mask = 8'b1111_0111;
    localparam [7:0] packet_control_addr = 8'b0000_0001;
    // ip_control        02 0000_x010
    localparam [7:0] ip_control_mask = 8'b1111_0111;
    localparam [7:0] ip_control_addr = 8'b0000_0010;    
    // packet_txlen      03 0000_x011
    localparam [7:0] packet_txlen_mask = 8'b1111_0111;
    localparam [7:0] packet_txlen_addr = 8'b0000_0011;
    // packet_port[15:8] 04 0000_x1x0
    localparam [7:0] packet_port_mask = 8'b1111_0100;
    localparam [7:0] packet_port_addr = 8'b0000_0100;
    // packet_port[7:0]  05 0000_x1x1
    // stream_ip[31:24]  10 0001_x000
    localparam [7:0] stream_ip_mask = 8'b1111_0100;
    localparam [7:0] stream_ip_addr = 8'b0001_0000;
    // stream_ip[23:16]  11 0001_x001
    // stream_ip[15:8]   12 0001_xx10
    // stream_ip[7:0]    13 0001_xx11
    // stream_udp[15:8]  14 0001_x100
    localparam [7:0] stream_udp_mask = 8'b1111_0100;
    localparam [7:0] stream_udp_addr = 8'b0001_0100;
    // stream_udp[7:0]   15 0001_x101
    // packet_ip[31:24]  20 0010_xx00
    // we never actually use this though
    localparam [7:0] pkt_ip_mask = 8'b1111_0000;
    localparam [7:0] pkt_ip_addr = 8'b0010_0000;
    // packet_ip[23:16]  21 0010_xx01
    // packet_ip[15:8]   22 0010_xx10
    // packet_ip[7:0]    23 0010_xx11
    // bottom two bits are for selection
    localparam [7:0] my_ip_mask = 8'b1111_0000;
    localparam [7:0] my_ip_addr = 8'b0011_0000;
    // my_ip[31:24]      30 0011_xx00
    // my_ip[23:16]      31 0011_xx01
    // my_ip[15:8]       32 0011_xx10
    // my_ip[7:0]        33 0011_xx11
    localparam [7:0] dna_mask = 8'b1110_0000;
    localparam [7:0] dna_addr = 8'b0100_0000;
    // dna               40 010x_xxxx
    localparam [7:0] dna_out_mask = 8'b1110_0000;
    localparam [7:0] dna_out_addr = 8'b0110_0000;
    // dna_out           60 011x_xxxx
    // buffer            80 1xxx_xxxx


    // IN_PORT
    // The only actual inputs we read are
    // dna               40
    // packet_control    01
    // bram              80-9F
    // packet_txlen      03
    // my_ip             30-33
    // so this becomes
    // 1xxx_xxxx (80-9F)
    //  1xx_xxxx (40)
    //   0x_xxxx (01/03)
    //   1x_xxxx (30-33)
    reg [7:0] inport_mux;
    always @(*) begin
        if (port_id[7]) inport_mux <= bram_read_data[7:0]; // 80-9F
        else if (port_id[6]) inport_mux <= dna_register;   // 40
        else if (port_id[5] == 0) begin                    // 01 and 03
            if (port_id[1]) inport_mux <= transmit_packet_length;
            else inport_mux <= packet_control;
        end else begin                                     // 30-33
            inport_mux <= ip_addr_byte;
        end
    end
    assign in_port = inport_mux;
                                
    integer ip_i;
    always @(posedge clk) begin : IP_ADDRESS_LOGIC
        ip_control_access <= (k_port_id & ip_control_mask) == ip_control_addr;
        if (reset) begin
            use_static_ip <= 0;
            static_ip_valid_reg <= 0;
        end
        else if ((write_strobe || k_write_strobe) && ip_control_access) begin : IP_CONTROL_LOGIC
            use_static_ip <= out_port[0];
            static_ip_valid_reg <= out_port[1];
        end
        for (ip_i=0;ip_i<4;ip_i=ip_i+1) begin : IP_BYTE_DECODE_LOGIC
            // Big endian ordering. Swap it around, so 0 -> 3, 1->2, 2->1, 3->0.
            ip_address_access[ip_i] <= (((port_id & my_ip_mask) == my_ip_addr) && (port_id[1:0] == 3-ip_i));
            if (ip_address_access[ip_i] && write_strobe) my_ip_address[8*ip_i +: 8] <= out_port;
        end
        case(port_id[1:0])
            2'b00: ip_addr_byte <= (!use_static_ip || ext_ip_force) ? ext_ip_address[24 +: 8] : my_ip_address[24 +: 8];
            2'b01: ip_addr_byte <= (!use_static_ip || ext_ip_force) ? ext_ip_address[16 +: 8] : my_ip_address[16 +: 8];
            2'b10: ip_addr_byte <= (!use_static_ip || ext_ip_force) ? ext_ip_address[8 +: 8] : my_ip_address[8 +: 8];
            2'b11: ip_addr_byte <= (!use_static_ip || ext_ip_force) ? ext_ip_address[0 +: 8] : my_ip_address[0 +: 8];
        endcase
    end                    

    always @(posedge clk) begin        
        dna_read <= ((port_id & dna_mask) == dna_addr) && write_strobe;
        dna_shift <= ((port_id & dna_mask) == dna_addr) && read_strobe;
        
        udp_in_start_reg <= udp_in_start;

        // Accept next packet goes high when set.
        // Gets cleared when accepting_packet will be set, at beginning of reception.
        if (reset) accept_next_packet <= 0;
        else if ((write_strobe || k_write_strobe) && ((k_port_id & packet_control_mask) == packet_control_addr) && out_port[0]) accept_next_packet <= 1;
        else if ((udp_in_start && !udp_in_start_reg) && !transmitting_packet) accept_next_packet <= 0;
    
        // Begin accepting packet at packet starts only. Terminate at packet end.
        // Don't even go there if we only receive one byte.
        if (reset) accepting_packet <= 0;
        else if (going_to_accept_packet && !udp_in_last) accepting_packet <= 1;
        else if (accepting_packet && udp_in_last && udp_in_valid) accepting_packet <= 0;
        
        if (reset) packet_byte_address <= {9{1'b0}};
        else if (!(accepting_packet || going_to_accept_packet) && !transmitting_packet) packet_byte_address <= {9{1'b0}};
        else if ((going_to_accept_packet || accepting_packet) && udp_in_valid) packet_byte_address <= packet_byte_address + 1;
        else if (transmitting_packet && udp_out_ready && transmitting_packet_data_valid) packet_byte_address <= packet_byte_address + 1;
        
        if (!transmitting_packet) transmitting_packet_data_valid <= 0;
        else if (transmitting_packet && !transmitting_packet_data_valid) transmitting_packet_data_valid <= 1;
        else if (transmitting_packet && transmitting_packet_data_valid && udp_out_ready) transmitting_packet_data_valid <= 0;        
    
        if (reset) transmitting_packet <= 0;
        else if ((write_strobe || k_write_strobe) && ((k_port_id & packet_control_mask) == packet_control_addr) && out_port[4]) transmitting_packet <= 1;
        else if (transmitting_packet && (packet_byte_address == transmit_packet_length) && transmitting_packet_data_valid && udp_out_ready) transmitting_packet <= 0;

        if (reset) transmit_packet_start <= 0;
        else if ((write_strobe || k_write_strobe) && ((k_port_id & packet_control_mask) == packet_control_addr) && out_port[4]) transmit_packet_start <= 1;
        else if (transmit_packet_start && (udp_out_result == 2'b01)) transmit_packet_start <= 0;

        if (reset) transmit_packet_length <= {9{1'b0}};
        else if (accepting_packet && udp_in_last && udp_in_valid) begin
            transmit_packet_length <= packet_byte_address;
        end else if ((write_strobe || k_write_strobe) && ((k_port_id & packet_txlen_mask) == packet_txlen_addr)) begin
            transmit_packet_length <= out_port[6:0];
        end                

        if (reset) packet_ip_addr <= {32{1'b0}};
        else if (going_to_accept_packet) packet_ip_addr <= udp_in_src_ip_addr;
//        else if (write_strobe && ((port_id & pkt_ip_mask) == pkt_ip_addr)) begin
//            // big endian
//            case(port_id[1:0])
//                2'b11: packet_ip_addr[0  +: 8] <= out_port;
//                2'b10: packet_ip_addr[8  +: 8] <= out_port;
//                2'b01: packet_ip_addr[16 +: 8] <= out_port;
//	            2'b00: packet_ip_addr[24 +: 8] <= out_port;	      
//            endcase
//        end
        
        if (reset) packet_port <= {16{1'b0}};
        else if (going_to_accept_packet) packet_port <= udp_in_src_port;
        else if (write_strobe && ((port_id & packet_port_mask) == packet_port_addr)) begin
            // big endian
            case(port_id[0])
                1'b1: packet_port[0 +: 8] <= out_port;
                1'b0: packet_port[8 +: 8] <= out_port;
            endcase
        end

       if (reset) stream_udp_port_reg <= {16{1'b0}};
       else if (write_strobe && ((port_id & stream_udp_mask) == stream_udp_addr)) begin
            // big endian
            case(port_id[0])
                1'b1: stream_udp_port_reg[0 +: 8] <= out_port;
                1'b0: stream_udp_port_reg[8 +: 8] <= out_port;
            endcase // case (port_id[0])
       end
       // we just autocopy when a write occurs
       if (reset) stream_ip_address_reg <= {32{1'b0}};
       else if (write_strobe && ((port_id & stream_ip_mask) == stream_ip_addr)) begin
            stream_ip_address_reg <= packet_ip_addr;
//            // big endian
//            case (port_id[1:0])
//                2'b11: stream_ip_address_reg[0 +: 8] <= out_port;
//                2'b10: stream_ip_address_reg[8 +: 8] <= out_port;
//                2'b01: stream_ip_address_reg[16 +: 8] <= out_port;
//                2'b00: stream_ip_address_reg[24 +: 8] <= out_port;
//            endcase // case (port_id[1:0])
       end
       if (reset) stream_linked_reg <= 1'b0;
       else if ((k_write_strobe || write_strobe) && ((k_port_id & stream_link_mask) == stream_link_addr) ) begin
           stream_linked_reg <= out_port[0];
       end

       if (write_strobe && ((port_id & dna_out_mask) == dna_out_addr)) begin
            // shift up by 8, but it's only 57 bits.
            // so grab 48
            device_dna <= { device_dna[48],
                            device_dna[40 +: 8],
                            device_dna[32 +: 8],
                            device_dna[24 +: 8],
                            device_dna[16 +: 8],
                            device_dna[8 +: 8],
                            device_dna[0 +: 8],
                            out_port };
       end
       if (reset) device_dna_valid <= 0;
       else if (accept_next_packet) device_dna_valid <= 1;              
    end
    
    generate
        if (DEBUG == "TRUE") begin : PBILA
            // this is the minimal information needed for debugging a PicoBlaze, mostly. Sleep/interrupt would help but you can
            // basically figure that out from address.
            picoblaze_ila pb_ila(.clk(clk),.probe0(address),.probe1(inout_port),.probe2(port_id),.probe3(packet_byte_address),.probe4(transmit_packet_length),.probe5(udp_in_last && udp_in_valid));
        end
    endgenerate
    assign udp_out_valid = (transmitting_packet_data_valid);
    assign udp_out_last = (packet_byte_address == transmit_packet_length) && transmitting_packet;
    assign udp_out_data = (bram_read_data);
    assign udp_out_start = transmit_packet_start;
    assign udp_out_length = transmit_packet_length + 1;
    
    assign udp_out_dst_ip_addr = packet_ip_addr;
    assign udp_out_dst_port = packet_port;
    
    // FIXME FIXME FIXME
//    wire [7:0] picoblaze_control_registers[15:0];
//    assign picoblaze_control_registers[0] = packet_control;
//    assign picoblaze_control_registers[1] = picoblaze_control_registers[0];
//    assign picoblaze_control_registers[2] = {1'b0,transmit_packet_length[6:0]};
//    assign picoblaze_control_registers[3] = picoblaze_control_registers[2];
//    assign picoblaze_control_registers[4] = packet_ip_addr[0 +: 8];
//    assign picoblaze_control_registers[5] = packet_ip_addr[8 +: 8];    
//    assign picoblaze_control_registers[6] = packet_ip_addr[16 +: 8];
//    assign picoblaze_control_registers[7] = packet_ip_addr[24 +: 8];
//    assign picoblaze_control_registers[8] = packet_port[0 +: 8];
//    assign picoblaze_control_registers[9] = packet_port[8 +: 8];
//    assign picoblaze_control_registers[10] = dna_register;
//    assign picoblaze_control_registers[11] = ip_control_register;
//    assign picoblaze_control_registers[12] = my_ip_address[0 +: 8];
//    assign picoblaze_control_registers[13] = my_ip_address[8 +: 8];
//    assign picoblaze_control_registers[14] = my_ip_address[16 +: 8];
//    assign picoblaze_control_registers[15] = my_ip_address[24 +: 8];
    // FIXME FIXME FIXME
//    assign in_port = (picoblaze_bram_access) ? bram_read_data[7:0] : ((port_id[5]) ? picoblaze_control_registers[port_id[3:0]] : stream_port[port_id[2:0]]);
    
    assign static_ip_address = my_ip_address;
    
    assign dhcp_reset = use_static_ip;
    assign static_ip_valid = static_ip_valid_reg;

   assign stream_udp_port = stream_udp_port_reg;
   assign stream_ip_address = stream_ip_address_reg;
   assign stream_linked = stream_linked_reg;

   assign device_dna_o = device_dna;
   assign device_dna_valid_o = device_dna_valid;   
endmodule
