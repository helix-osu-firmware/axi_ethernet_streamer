#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "hxlib.h"

#define MAX_FPGAS 16

#define ntohll(x) ((1==ntohl(1)) ? (x) : ((uint64_t)ntohl((x) & 0xFFFFFFFF) << 32) | ntohl((x) >> 32))

#define TYPE_NOP 0
#define TYPE_WRITE 1
#define TYPE_READ 2
#define TYPE_UPDATE 3
void helix_send_control_packet(ip_path_t *path,
			       ip_fpga_t *fpga,
			       uint8_t type,
			       uint32_t address,
			       uint16_t data);

// these are super-sleazy
void helix_update(ip_path_t *hw, ip_fpga_t *fpga,
		  uint32_t address,
		  uint16_t data);
void helix_write(ip_path_t *hw, ip_fpga_t *fpga,
		  uint32_t address,
		  uint16_t data);
uint16_t helix_read(ip_path_t *hw, ip_fpga_t *fpga,
		    uint32_t address);

// reading means:
// send control packet with TYPE_READ (helix_send_control_packet(..))
// get response (n = hxlib_get_response(&hw, rxbuf, 4, 5000))
// parse control packet (val = helix_parse_status_packet(rxbuf))

uint16_t helix_parse_status_packet(uint8_t *buf);

ip_fpga_t found_fpgas[MAX_FPGAS];

int main(int argc, char *argv[]) {
  unsigned char *rxbuf;
  ip_path_t hz;
  ip_path_t hw;
  int i,n,len,nfound;
  char *ipaddr="255.255.255.255";

  if (argc==2)
    ipaddr=argv[1];
  
  initialize_hz_path(&hz);
  initialize_hw_path(&hw);

  rxbuf = (unsigned char *) malloc(sizeof(unsigned char)*2048);
  
  // perform discovery procedure
  printf("Discovering... ");
  nfound = discover_fpgas_at_addr(inet_addr(ipaddr),&hz, found_fpgas, MAX_FPGAS);
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

  printf("ID: %4.4x\n", helix_read(&hw, &found_fpgas[0], 0));
  printf("Version: %4.4x\n", helix_read(&hw, &found_fpgas[0], 1));
  printf("Date: %4.4x\n", helix_read(&hw, &found_fpgas[0], 2));
  printf("DNA: ");
  for (i=0;i<4;i=i+1) {
    // write the DNA pointer
    helix_write(&hw, &found_fpgas[0], 3, 3-i);
    printf("%4.4x", helix_read(&hw, &found_fpgas[0], 3));
  }
  printf("\n");
  stream_close(&hz, &found_fpgas[0]);
  
 close_sockets:
  free(rxbuf);
  close_path(&hz);
  close_path(&hw);
  return 0;
}

// these are super-sleazy
void helix_update(ip_path_t *hw, ip_fpga_t *fpga,
		  uint32_t address,
		  uint16_t data) {
  helix_send_control_packet(hw, fpga, TYPE_UPDATE, address, data);
}

void helix_write(ip_path_t *hw, ip_fpga_t *fpga,
		 uint32_t address,
		 uint16_t data) {
  helix_send_control_packet(hw, fpga, TYPE_WRITE, address, data);
}

uint16_t helix_read(ip_path_t *hw, ip_fpga_t *fpga,
		    uint32_t address) {
  unsigned int n;
  unsigned char rxbuf[8];
  helix_send_control_packet(hw, fpga, TYPE_READ, address, 0);
  // and watch for a response.
  n = hxlib_get_response(hw, rxbuf, 8, 5000);
  return helix_parse_status_packet(rxbuf);
}


// these are the underlying functions

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

uint16_t helix_parse_status_packet(uint8_t *buf) {
  uint16_t header;
  uint16_t ctrl_word1;
  uint16_t ctrl_word2;
  uint16_t ctrl_word3;
  uint16_t data;

  // byte ordering is LITTLE ENDIAN, not network byte order
  header = (buf[1] << 8) | buf[0];
  ctrl_word1 = (buf[3] << 8) | buf[2];
  ctrl_word2 = (buf[5] << 8) | buf[4];
  ctrl_word3 = (buf[7] << 8) | buf[6];
  if (header != 0x57A7) {
    fprintf(stderr, "error, header %4.4x not 57A7\n", header);
    return 0xFFFF;
  }
  if ((ctrl_word1 & 0xF000) != 0xF000) {
    fprintf(stderr, "error, SOF %1.1x not 0xF\n", (ctrl_word1 >> 12) & 0xF);
    return 0xFFFF;
  }
  if ((ctrl_word3 & 0x000F) != 0x0008) {
    fprintf(stderr, "error, EOF %1.1x not 0x8\n", ctrl_word3 & 0xF);
    return 0xFFFF;
  }
  // sigh
  data = ((ctrl_word2 & 0xF) << 12) | ((ctrl_word3 & 0xFFF0)>>4);
  return data;
}
