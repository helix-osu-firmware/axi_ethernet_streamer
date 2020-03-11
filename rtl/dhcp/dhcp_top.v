module dhcp_top(
    input udp_in_start,
    input [7:0] udp_in_data,
    input udp_in_valid,
    input udp_in_last,
    
    input  udp_out_ready,
    output [7:0] udp_out_data,
    output udp_out_last,
    output udp_out_valid,
    output [8:0] udp_out_length,
    output [31:0] udp_out_dst_ip_addr,
    output [15:0] udp_out_dst_port,
    
    input [1:0] udp_out_result,
    output udp_out_start,
    
    input [47:0] mac_address,
    output [31:0] ip_address,
    output ip_address_valid,
    
    input do_dhcp,
    input reset,
    input second,
    input clk
    );

    reg do_dhcp_seen = 0;
    
    reg second_seen = 0;

    // OK, new approach here. Simple UDP port handler.
    // When PicoBlaze says it's OK, data that comes in is streamed into a 512-byte buffer (note that this is 1/4 of the program space)
    // inside the program ROM. Otherwise that data's tossed.
    // Address in BRAM is 11x xxxx xxxx = 0x600 for the 8-bit address. The 16-bit address is therefore 11 xxxx xxxx = 0x300 which means
    // that the program has space for 768 instructions.
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
    //% Partial packet completed (enough to get the transaction ID).
    reg partial_packet_done = 0;
    //% We only need 8 bytes to check to see if it's for us (transaction ID check).
    localparam [9:0] PARTIAL_PACKET_THRESHOLD = 8;

    //% Transaction ID capture.
    reg [31:0] transaction_id = {32{1'b0}};
    localparam [9:0] TRANSACTION_ID_0 = 9'd4;
    localparam [9:0] TRANSACTION_ID_1 = 9'd5;
    localparam [9:0] TRANSACTION_ID_2 = 9'd6;
    localparam [9:0] TRANSACTION_ID_3 = 9'd7;

    //% Bytes to transmit, minus 1.
    reg [8:0] transmit_packet_length = {9{1'b0}};
    //% Currently transmitting.
    reg transmitting_packet = 0;
    reg transmit_packet_start = 0;
    reg transmitting_packet_data_valid = 0;
    reg [8:0] packet_byte_address = {9{1'b0}};

    reg [31:0] my_ip = {32{1'b0}};
    reg my_ip_valid = 0;

    assign ip_address = my_ip;
    assign ip_address_valid = my_ip_valid;

    wire [7:0] packet_control = {my_ip_valid, do_dhcp_seen, 1'b0,transmitting_packet,1'b0, partial_packet_done,accepting_packet, accept_next_packet};

    // picoblaze
    wire [11:0] address;
    wire [17:0] instruction;
    wire [7:0] out_port;
    wire [7:0] in_port;
    wire [7:0] port_id;
    wire write_strobe;
    wire k_write_strobe;
    wire read_strobe;
    wire bram_enable;
    wire interrupt = second_seen;
    wire interrupt_ack;
    
    wire [7:0] inout_port = (read_strobe) ? in_port : out_port;
    

    // The BRAM needs to be banked into four groups of 128.
    reg [1:0] picoblaze_bram_bank = 2'b00;    
    wire [8:0] picoblaze_bram_address = {picoblaze_bram_bank, port_id[6:0]};
    wire picoblaze_bram_access = (port_id[7]);
    wire [10:0] bram_address = {2'b11, (transmitting_packet || (accepting_packet || going_to_accept_packet)) ? packet_byte_address : picoblaze_bram_address};
    wire [8:0] bram_write_data = (accepting_packet || going_to_accept_packet) ? {1'b0,udp_in_data} : {1'b0,out_port};
    wire bram_write = ((accepting_packet || going_to_accept_packet) && udp_in_valid) || (!(accepting_packet || going_to_accept_packet) && !transmitting_packet && write_strobe && picoblaze_bram_access);
    wire bram_read = !bram_write;
    wire [8:0] bram_read_data;

//    ila_0 u_ila(.clk(clk),.probe0(port_id),.probe1(inout_port),.probe2(address),.probe3(write_strobe),.probe4(read_strobe),.probe5(accept_next_packet),.probe6(accepting_packet),.probe7(udp_in_valid),
//                          .probe8(udp_in_last), .probe9(udp_in_start),.probe10(udp_in_data),.probe11(packet_byte_address));
    
    dhcp_picoblaze_rom u_rom(.address(address),.instruction(instruction),.clk(clk),.enable(bram_enable),
                             .bram_adr_i(bram_address),.bram_dat_i(bram_write_data),.bram_dat_o(bram_read_data),
                             .bram_we_i(bram_write),.bram_rd_i(bram_read));

    kcpsm6 #(.interrupt_vector(12'h2FF)) u_picoblaze(.address(address),.instruction(instruction),.clk(clk),.bram_enable(bram_enable),
                       .sleep(1'b0),.reset(reset),.port_id(port_id),.in_port(in_port),.out_port(out_port),
                       .write_strobe(write_strobe),.read_strobe(read_strobe),.k_write_strobe(k_write_strobe),
                       .interrupt(interrupt), .interrupt_ack(interrupt_ack));

    assign going_to_accept_packet = (accept_next_packet && udp_in_start && !udp_in_start_reg && !transmitting_packet);

    always @(posedge clk) begin        
        if (reset) do_dhcp_seen <= 0;
        else if (do_dhcp) do_dhcp_seen <= 1;

        if (second) second_seen <= 1;
        else if (interrupt_ack) second_seen <= 0;

        udp_in_start_reg <= udp_in_start;

        // Accept next packet goes high when set.
        // Gets cleared when accepting_packet will be set, at beginning of reception.
        if (reset) accept_next_packet <= 0;
        else if (write_strobe && !port_id[7] && (port_id[4:0] == 5'h00) && out_port[0]) accept_next_packet <= 1;
        else if ((udp_in_start && !udp_in_start_reg) && !transmitting_packet) accept_next_packet <= 0;
    
        // Begin accepting packet at packet starts only. Terminate at packet end. Don't even go there if we only receive one byte.
        if (reset) accepting_packet <= 0;
        else if (going_to_accept_packet && !udp_in_last) accepting_packet <= 1;
        else if (accepting_packet && udp_in_last && udp_in_valid) accepting_packet <= 0;
        
        // Partial packet checking. Allows us to go check the XID while the data is still being streamed in.
        // If we see accept_next_packet go high that means we're no longer interested in this one, and this one goes away.
        if (reset) partial_packet_done <= 0;
        else if (!accepting_packet || accept_next_packet) partial_packet_done <= 0;
        else if (accepting_packet && (packet_byte_address == PARTIAL_PACKET_THRESHOLD) && udp_in_valid) partial_packet_done <= 1;                
        
        // XID capture.
        if (packet_byte_address == TRANSACTION_ID_0 && udp_in_valid) transaction_id[0 +: 8] = udp_in_data;
        if (packet_byte_address == TRANSACTION_ID_1 && udp_in_valid) transaction_id[8 +: 8] = udp_in_data;
        if (packet_byte_address == TRANSACTION_ID_2 && udp_in_valid) transaction_id[16 +: 8] = udp_in_data;
        if (packet_byte_address == TRANSACTION_ID_3 && udp_in_valid) transaction_id[24 +: 8] = udp_in_data;
        
        if (reset) packet_byte_address <= {9{1'b0}};
        else if (!(accepting_packet || going_to_accept_packet) && !transmitting_packet) packet_byte_address <= {9{1'b0}};
        else if ((going_to_accept_packet || accepting_packet) && udp_in_valid) packet_byte_address <= packet_byte_address + 1;
        else if (transmitting_packet && udp_out_ready && transmitting_packet_data_valid) packet_byte_address <= packet_byte_address + 1;
        
        if (!transmitting_packet) transmitting_packet_data_valid <= 0;
        else if (transmitting_packet && !transmitting_packet_data_valid) transmitting_packet_data_valid <= 1;
        else if (transmitting_packet && transmitting_packet_data_valid && udp_out_ready) transmitting_packet_data_valid <= 0;        
    
        if (reset) transmitting_packet <= 0;
        else if (write_strobe && !port_id[7] && (port_id[4:0] == 5'h00) && out_port[4]) transmitting_packet <= 1;
        else if (transmitting_packet && (packet_byte_address == transmit_packet_length) && transmitting_packet_data_valid && udp_out_ready) transmitting_packet <= 0;

        if (reset) transmit_packet_start <= 0;
        else if (write_strobe && !port_id[7] && (port_id[4:0] == 5'h00) && out_port[4]) transmit_packet_start <= 1;
        else if (transmit_packet_start && (udp_out_result == 2'b01)) transmit_packet_start <= 0;

        if (reset) transmit_packet_length <= {9{1'b0}};
        else if (write_strobe && !port_id[7] && ({port_id[4:1],1'b0} == 5'h02)) begin
            if (!port_id[0]) transmit_packet_length[7:0] <= out_port[7:0];
            else transmit_packet_length[8] <= out_port[0];
        end                

        if (reset) my_ip_valid <= 0;
        else if (write_strobe && !port_id[7] && (port_id[4:0] == 5'h00) && out_port[7]) my_ip_valid <= ~my_ip_valid;
        
        if (reset) my_ip <= {32{1'b0}};
        else if (write_strobe && !port_id[7] && ({port_id[4:2],2'b00} == 5'h04)) begin
            case(port_id[1:0])
                2'b00: my_ip[0 +: 8] <= out_port;
                2'b01: my_ip[8 +: 8] <= out_port;
                2'b10: my_ip[16 +: 8] <= out_port;
                2'b11: my_ip[24 +: 8] <= out_port;
            endcase
        end
        
        if (reset) picoblaze_bram_bank <= 2'b00;
        else if (write_strobe && !port_id[7] && (port_id[4:0] == 5'h01)) picoblaze_bram_bank <= out_port[1:0];
        
    end
    
    assign udp_out_valid = (transmitting_packet_data_valid);
    assign udp_out_last = (packet_byte_address == transmit_packet_length) && transmitting_packet;
    assign udp_out_data = (bram_read_data);
    assign udp_out_start = transmit_packet_start;
    assign udp_out_length = transmit_packet_length + 1;
    
    assign udp_out_dst_ip_addr = 32'hFFFFFFFF;
    assign udp_out_dst_port = 16'd67;
        
    function [7:0] get_mac_byte;
        input integer inbyte;
        input [47:0] mac;
        begin
            get_mac_byte = mac[(5-inbyte)*8 +: 8];
        end
    endfunction
    
    wire [7:0] picoblaze_control_registers[31:0];
    assign picoblaze_control_registers[0] = packet_control;
    assign picoblaze_control_registers[1] = picoblaze_bram_bank;
    assign picoblaze_control_registers[2] = transmit_packet_length[7:0];
    assign picoblaze_control_registers[3] = {{7{1'b0}},transmit_packet_length[8]};
    assign picoblaze_control_registers[4] = my_ip[0 +: 8];
    assign picoblaze_control_registers[5] = my_ip[8 +: 8];    
    assign picoblaze_control_registers[6] = my_ip[16 +: 8];
    assign picoblaze_control_registers[7] = my_ip[24 +: 8];
    assign picoblaze_control_registers[8] = get_mac_byte(0,  mac_address);
    assign picoblaze_control_registers[9] = get_mac_byte(1,  mac_address);
    assign picoblaze_control_registers[10] = get_mac_byte(2, mac_address);
    assign picoblaze_control_registers[11] = get_mac_byte(3, mac_address);
    assign picoblaze_control_registers[12] = get_mac_byte(4, mac_address);
    assign picoblaze_control_registers[13] = get_mac_byte(5, mac_address);
    assign picoblaze_control_registers[14] = picoblaze_control_registers[10]; // simplify decode to 1x10
    assign picoblaze_control_registers[15] = picoblaze_control_registers[11]; // simplify decode to 1x11
    assign picoblaze_control_registers[16] = transaction_id[0 +: 8];
    assign picoblaze_control_registers[17] = transaction_id[8 +: 8];
    assign picoblaze_control_registers[18] = transaction_id[16 +: 8];
    assign picoblaze_control_registers[19] = transaction_id[24 +: 8];
    assign picoblaze_control_registers[20] = picoblaze_control_registers[4];    
    assign picoblaze_control_registers[21] = picoblaze_control_registers[5];    
    assign picoblaze_control_registers[22] = picoblaze_control_registers[6];    
    assign picoblaze_control_registers[23] = picoblaze_control_registers[7];    
    assign picoblaze_control_registers[24] = picoblaze_control_registers[8];    
    assign picoblaze_control_registers[25] = picoblaze_control_registers[9];    
    assign picoblaze_control_registers[26] = picoblaze_control_registers[10];    
    assign picoblaze_control_registers[27] = picoblaze_control_registers[11];    
    assign picoblaze_control_registers[28] = picoblaze_control_registers[12];    
    assign picoblaze_control_registers[29] = picoblaze_control_registers[13];    
    assign picoblaze_control_registers[30] = picoblaze_control_registers[14];    
    assign picoblaze_control_registers[31] = picoblaze_control_registers[15];    

    assign in_port = (picoblaze_bram_access) ? bram_read_data[7:0] : picoblaze_control_registers[port_id[4:0]];

/*
    // UDP packet = 253 bytes
    // UDP header = 8 bytes
    // IP header = 20 bytes
    // should be 281 total bytes
    // ethernet adds 6+6+2 = 14
    // should be 295 bytes on wire (there are!)

    // DHCP sequence needs 2 packets: DISCOVER and REQUEST.
    // It receives 2 as well: OFFER and ACK.
    // We embed the two required packets into a single block RAM.        
    reg [7:0] dhcp_packets[511:0];
    integer i,j,k,l,m;
    initial begin
        dhcp_packets[0] = 8'h01; // OP
        dhcp_packets[1] = 8'h01; // HTYPE (Ethernet)
        dhcp_packets[2] = 8'h06; // HLEN (Ethernet)
        dhcp_packets[3] = 8'h00; // HOPS
        dhcp_packets[4] = 8'hDE; // XID3
        dhcp_packets[5] = 8'hAD; // XID2
        dhcp_packets[6] = 8'hBE; // XID1
        dhcp_packets[7] = 8'hEF; // XID0
        dhcp_packets[8] = 8'h00; // SEC0
        dhcp_packets[9] = 8'h00;
        dhcp_packets[10] = 8'h80;
        dhcp_packets[11] = 8'h00;
        // Now need 16 bytes of 0s
        for (i=12;i<28;i=i+1) dhcp_packets[i] = 8'h00;
        // Now insert MAC address, in big-endian format
        for (j=28;j<34;j=j+1) dhcp_packets[j] = get_mac_byte(j-28, MAC_ADDRESS);
        // Now we need 10+192=202 0s.
        for (k=34;k<236;k=k+1) dhcp_packets[k] = 8'h00;
        dhcp_packets[236] = 8'd99;  // 0x63
        dhcp_packets[237] = 8'd130; // 0x82
        dhcp_packets[238] = 8'd83;  // 0x53
        dhcp_packets[239] = 8'd99;  // 0x63
        dhcp_packets[240] = 8'd53;  // 0x35
        dhcp_packets[241] = 8'd1;   // 0x01
        dhcp_packets[242] = 8'd1;   // 0x01
        dhcp_packets[243] = 8'd61;  // 0x3D
        dhcp_packets[244] = 8'd7;   // 0x07
        dhcp_packets[245] = 8'd1;   // 0x01
        for (l=246;l<252;l=l+1) dhcp_packets[l] = get_mac_byte(l-246, MAC_ADDRESS);
        dhcp_packets[252] = 8'hFF;
        for (m=253;m<512;m=m+1) dhcp_packets[m] = 8'h00;
    end
    reg [7:0] packet_counter = {8{1'b0}};
    
    localparam FSM_BITS = 3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] DHCPDISCOVER_START = 1;
    localparam [FSM_BITS-1:0] DHCPDISCOVER_DATA = 2;
    localparam [FSM_BITS-1:0] DHCPDISCOVER_ACK = 3;
    localparam [FSM_BITS-1:0] DHCPDISCOVER_FINISH = 4;
    reg [FSM_BITS-1:0] state = IDLE;
    reg [7:0] udp_out_data_reg = {8{1'b0}};
    
    reg [1:0] do_dhcp_detect = {2{1'b0}};
    
    always @(posedge clk) begin
        if (reset) do_dhcp_detect <= {2{1'b0}};
        else do_dhcp_detect <= {do_dhcp_detect[0], do_dhcp};
    
        if (reset) state <= IDLE;
        else begin case (state)
            IDLE: if (do_dhcp_detect == 2'b01) state <= DHCPDISCOVER_START;
            DHCPDISCOVER_START: if (udp_out_result == 2'b01) state <= DHCPDISCOVER_DATA;
            DHCPDISCOVER_DATA: if (udp_out_ready) state <= DHCPDISCOVER_ACK;
            DHCPDISCOVER_ACK: if (packet_counter == 252) state <= DHCPDISCOVER_FINISH; 
                              else state <= DHCPDISCOVER_DATA;
            DHCPDISCOVER_FINISH: if (udp_out_ready) state <= IDLE;
            endcase
        end
        udp_out_data_reg <= dhcpdiscover[{1'b0,packet_counter}];
        if (state == IDLE) packet_counter <= 0;
        else if (state == DHCPDISCOVER_DATA && udp_out_ready) packet_counter <= packet_counter + 1;
    end
    assign udp_out_start = (state == DHCPDISCOVER_START);
    assign udp_out_valid = (state == DHCPDISCOVER_DATA || state == DHCPDISCOVER_FINISH);    
    assign udp_out_last = (state == DHCPDISCOVER_FINISH);            
    assign udp_out_data = udp_out_data_reg;
*/
endmodule