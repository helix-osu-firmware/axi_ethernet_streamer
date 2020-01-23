`timescale 1ns/1ps
// 32x8 buffer for accepting HY packets.
module hycontrol_buffer( input clk,
			 input [4:0]  addr,
			 input [7:0]  dat_i,
			 output [7:0] dat_o,
			 input 	      write,
			 input 	      read );

   reg [7:0] 			      out_data = {8{1'b0}};
   wire [7:0] 			      ram_out;
   
   RAM32M u_ram(.WCLK(clk),.WE(write),
		.DIA(dat_i[1:0]),.DOA(ram_out[1:0]),
		.DIB(dat_i[3:2]),.DOB(ram_out[3:2]),
		.DIC(dat_i[5:4]),.DOC(ram_out[5:4]),
		.DID(dat_i[7:6]),.DOD(ram_out[7:6]),
		.ADDRA(addr),
		.ADDRB(addr),
		.ADDRC(addr),
		.ADDRD(addr));		
   always @(posedge clk) out_data <= ram_out;

   assign dat_o = out_data;   
   
endmodule // hycontrol_buffer
