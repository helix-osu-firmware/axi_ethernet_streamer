#ifndef HXLIB_H
#define HXLIB_H

// oh I have no idea
#define __USE_MISC
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <sys/types.h> 
#include <sys/socket.h> 

// combined socket/port
typedef struct ip_path {
  int sockfd;
  uint16_t port;
} ip_path_t;

typedef struct ip_fpga {
  // IP address of the FPGA.
  struct sockaddr_in addr;
  // Interface address that the FPGA sent to.
  // This allows us to tell the FPGA to link to *us*.
  uint32_t ifindex;
  uint32_t dna[2];
} ip_fpga_t;


int initialize_hz_path(ip_path_t *path);

int initialize_hw_path(ip_path_t *path);

void close_path(ip_path_t *path);

// Broadcast an ID packet (via HZ path) to the broadcast address given.
int broadcast_id(ip_path_t *hzpath, in_addr_t bcast_addr);

// Discover network attached FPGAs (via HZ path) on all IPv4-broadcastable interfaces
int discover_fpgas(ip_path_t *hzpath, ip_fpga_t *found, int max);

// Discover network attached FPGAs. 
int discover_fpgas_at_addr(in_addr_t bcast_addr,
			   ip_path_t *hzpath, ip_fpga_t *found, int max);

// Open the stream (sockfd = HZ).
int stream_open(ip_path_t *hzpath, ip_fpga_t *fpga);

// Close the stream (sockfd = HZ).
int stream_close(ip_path_t *hzpath, ip_fpga_t *fpga);

// sleazeball function for getting a response
// use the right path! Data uses hw_path!
int hxlib_get_response(ip_path_t *path,
		       char *buf,
		       ssize_t nbytes,
		       uint32_t timeout);

// sleazeball function for sending something
// use the right path! Data uses hw_path!
int hxlib_send_packet(ip_path_t *path,
		      char *buf,
		      ssize_t nbytes,
		      ip_fpga_t *fpga);

//// These are lower-level functions, don't use that.

// create socket for the HW (data) port. Fills the path pointer.
int create_hw_socket();

// create socket for the HZ (control) port. Fills the path pointer.
int create_hz_socket();

// bind the HW (data) port.
int bind_hw(int sockfd);

// bind the HZ (data) port.
int bind_hz(int sockfd);


#endif
