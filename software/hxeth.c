#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "hxlib.h"

#define MAX_FPGAS 16

#define ntohll(x) ((1==ntohl(1)) ? (x) : ((uint64_t)ntohl((x) & 0xFFFFFFFF) << 32) | ntohl((x) >> 32))

void helix_send_control_packet(ip_path_t *path,
			       ip_fpga_t *fpga,
			       uint8_t type,
			       uint32_t address,
			       uint16_t data);

ip_fpga_t found_fpgas[MAX_FPGAS];

int main() {
  ip_path_t hz;
  ip_path_t hw;
  int n,len,nfound;
  
  initialize_hz_path(&hz);
  initialize_hw_path(&hw);

  // perform discovery procedure
  printf("Discovering... ");
  nfound = discover_fpgas(&hz, found_fpgas, MAX_FPGAS);
  printf("found %d FPGA", nfound);  
  if (nfound>1) printf("s");
  printf(".\n");
  for (int i=0;i<nfound;i++) {
    printf("FPGA %8.8x%8.8x at %s (via %d)\n", found_fpgas[i].dna[1],
	   found_fpgas[i].dna[0],
	   inet_ntoa(found_fpgas[i].addr.sin_addr),
	   found_fpgas[i].ifindex);
  }
  if (!nfound) goto close_sockets;

  // open the stream link on FPGA #0
  stream_open(&hz, &found_fpgas[0]);

  // note the switch to the HW socket - that's the stream socket
  helix_send_control_packet(&hw, &found_fpgas[0], 
			    0, // no-op, for fun
			    0x123456,
			    0x789A);

  sleep(5);
  
  // close the stream link on FPGA #0
  stream_close(&hz, &found_fpgas[0]);
  
 close_sockets:
  close_path(&hz);
  close_path(&hw);
  return 0;
}

void helix_send_control_packet(ip_path_t *hw,
			       ip_fpga_t *fpga,
			       uint8_t type,
			       uint32_t address,
			       uint16_t data) {
  // Construct a control packet. It's 8 bytes long, 4 16-bit packets.
  uint8_t buf[8];
  // Because we're outputting an AXI4-Stream, the byte ordering is
  // little endian, because ARM is evil.
  // header
  buf[0] = 0x51;
  buf[1] = 0xC7;
  // control_word1[7:0]
  buf[2] = (address & 0xFF000)>>12;
  // 15:8
  buf[3] = 0xF0 | ((type & 0x3)<<2) | ((address & 0x300000)>>20);
  // control_word2 - top 4 bits of data, bottom 4 bits of addr
  buf[4] = ((data & 0xF000)>>12) | ((address & 0xF) << 4);  
  buf[5] = (address & 0xFF0)>>4;
  // control_word3 - bottom 12 bits of data, EOF
  buf[6] = 0x8 | ((data & 0xF)<<4);
  buf[7] = (data & 0xFF0)>>4;
  hxlib_send_packet(hw, buf, 8, fpga);
}
