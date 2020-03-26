#include <stdio.h> 
#include <stdlib.h> 
#include <unistd.h> 
#include <string.h> 
#include <sys/select.h>
#include <sys/types.h>
#include <unistd.h>
#include <ifaddrs.h>

#include "hxlib.h"

// These two need to match the FPGA's
// port handlers.
#define STREAM_OUT_PORT 18520 // 'HX'
#define OUT_PORT 18521  // 'HY'

// These two are arbitrary.
#define IN_PORT 18522 // 'HZ'
#define STREAM_IN_PORT 18519 // 'HW'

int hxlib_send_packet(ip_path_t *path, char *buf, ssize_t nbytes,
		      ip_fpga_t *fpga) {
  struct sockaddr_in dest = fpga->addr;
  dest.sin_port = path->port;
  return sendto(path->sockfd, buf, nbytes, 0,
		(const struct sockaddr *) &dest,
		sizeof(struct sockaddr_in));
}

// timeout in microseconds
int hxlib_get_response(ip_path_t *path, char *buf, ssize_t nbytes,
			 uint32_t timeout) {
  int sockfd = path->sockfd;
  fd_set readfds;
  struct timeval timeout_val;
  timeout_val.tv_sec = (unsigned int) timeout/1000000;
  timeout_val.tv_usec = timeout % 1000000;
  FD_ZERO(&readfds);
  FD_SET(sockfd, &readfds);
  if (select(sockfd+1, &readfds, NULL, NULL, &timeout_val) < 0) {
    perror("on select");
    exit(1);
  }
  if (FD_ISSET(sockfd, &readfds)) {
    struct sockaddr_in cliaddr;
    socklen_t addrlen = sizeof(cliaddr);
    ssize_t recvlen;
    recvlen = recvfrom(sockfd, buf, nbytes, 0, (struct sockaddr *) &cliaddr,
		       &addrlen);
    return recvlen;
  }
  return 0;  
}

int initialize_hz_path(ip_path_t *path) {
  int sockfd;
  sockfd = create_hz_socket();
  bind_hz(sockfd);
  path->sockfd = sockfd;
  path->port = htons(OUT_PORT);
}

int initialize_hw_path(ip_path_t *path) {
  int sockfd;
  sockfd = create_hw_socket();
  bind_hw(sockfd);
  path->sockfd = sockfd;
  path->port = htons(STREAM_OUT_PORT);
}

void close_path(ip_path_t *path) {
  close(path->sockfd);
}

int create_hw_socket() {
  int sockfd;
  int ret;
  if ((sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
    perror("socket creation failed");
    exit(EXIT_FAILURE);
  }
  return sockfd;
}

int bind_hw(int sockfd) {
  struct sockaddr_in servaddr;
  
  memset(&servaddr, 0, sizeof(servaddr));
  servaddr.sin_family = AF_INET;
  servaddr.sin_addr.s_addr = INADDR_ANY;
  servaddr.sin_port = htons(STREAM_IN_PORT);
  // Bind the socket.
  if (bind(sockfd, (const struct sockaddr *)&servaddr,
	   sizeof(servaddr))<0) {
    perror("bind failed");
    exit(EXIT_FAILURE);
  }
  return 0;
}

int create_hz_socket() {
  int sockfd;
  int broadcastEnable=1;
  int pktinfoEnable=1;
  int ret;
  if ((sockfd = socket(AF_INET, SOCK_DGRAM, 0))<0) {
    perror("socket creation failed");
    exit(EXIT_FAILURE);
  }
  ret=setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable,
		     sizeof(broadcastEnable));
  if (ret<0) {
    perror("socket broadcast failed");
    exit(EXIT_FAILURE);
  }
  ret=setsockopt(sockfd, IPPROTO_IP, IP_PKTINFO, &pktinfoEnable,
		 sizeof(pktinfoEnable));
  if (ret<0) {
    perror("socket info failed");
    exit(EXIT_FAILURE);
  }

  return sockfd;
}

int bind_hz(int sockfd) {
  struct sockaddr_in servaddr;
  
  memset(&servaddr, 0, sizeof(servaddr));
  servaddr.sin_family = AF_INET;
  servaddr.sin_addr.s_addr = INADDR_ANY;
  servaddr.sin_port = htons(IN_PORT);
  // Bind the socket.
  if (bind(sockfd, (const struct sockaddr *)&servaddr,
	   sizeof(servaddr))<0) {
    perror("bind failed");
    exit(EXIT_FAILURE);
  }
  return 0;
}

int broadcast_id(ip_path_t *path, in_addr_t bcast_addr) {
  struct sockaddr_in cliaddr;
  char rxbuf[3];

  memset(&cliaddr, 0, sizeof(cliaddr));
  // send a broadcast message 
  cliaddr.sin_family = AF_INET;
  cliaddr.sin_port = htons(OUT_PORT);
  // TEMPORARY HACK
  cliaddr.sin_addr.s_addr = bcast_addr;
  //cliaddr.sin_addr.s_addr = htonl(INADDR_BROADCAST);
  rxbuf[0] = 'I';
  rxbuf[1] = 'D';
  rxbuf[2] = 0;
  ssize_t rn;
  rn = sendto(path->sockfd, rxbuf, 3, 0, (const struct sockaddr *) &cliaddr,
	      sizeof(cliaddr));
  if (rn < 0) {
    perror("error sending");
    exit(EXIT_FAILURE);
  }
  return 0;
}

int stream_close(ip_path_t *path, ip_fpga_t *fpga) {
  char rxbuf[3];

  rxbuf[0] = 'C';
  rxbuf[1] = 'L';
  rxbuf[2] = 0;
  ssize_t rn;
  rn = hxlib_send_packet(path, rxbuf, 3, fpga);  
  if (rn < 0) {
    perror("error sending");
    exit(EXIT_FAILURE);
  }
  if (hxlib_get_response(path, rxbuf, 3, 5000) < 3) {
    printf("stream_close: no response from %s\n",
	   inet_ntoa(fpga->addr.sin_addr));
    return -1;
  }  
  return 0;
}

int stream_open(ip_path_t *path, ip_fpga_t *fpga) {
  char rxbuf[5];
  uint16_t target_port;

  target_port = htons(STREAM_IN_PORT);
  rxbuf[0] = 'O';
  rxbuf[1] = 'P';
  rxbuf[2] = 0;
  memcpy((unsigned char *) (&rxbuf[3]), &target_port, 2);
  ssize_t rn;
  rn = hxlib_send_packet(path, rxbuf, 5, fpga);    
  if (rn < 0) {
    perror("error sending");
    exit(EXIT_FAILURE);
  }
  
  if (hxlib_get_response(path, rxbuf, 3, 5000) < 3) {
    printf("stream_open: no response from %s\n",
	   inet_ntoa(fpga->addr.sin_addr));
    return -1;
  }  
  return 0;
}


// Note, this is way harder than a normal UDP receive is.
// I was previously trying to find a way to find what IP address
// a packet was sent to, because an earlier version of OP
// required the IP address of the stream partner. I got rid
// of that because there's no way to do it OS-independently.

// needs to iterate over them.
// It appears the best way to do that is to use getifaddrs
// and look for IFF_RUNNING | IFF_UP | IFF_BROADCAST as well as
// sin_family = 2.

int discover_fpgas(ip_path_t *hzpath, ip_fpga_t *found, int max) {
  int total;
  struct ifaddrs *ifap;
  total = 0;
  if (getifaddrs(&ifap) == 0) {
    struct ifaddrs *p = ifap;
    while (p) {
      struct sockaddr_in *sap;
      struct in_addr *ap;
      struct sockaddr_in *bap;
      int foundhere;

      foundhere = 0;
      sap = (struct sockaddr_in *) p->ifa_addr;
      ap = &sap->sin_addr;
      bap = (struct sockaddr_in *) p->ifa_broadaddr;
      if ((p->ifa_flags & (IFF_RUNNING | IFF_UP | IFF_BROADCAST)) ==
	  (IFF_RUNNING | IFF_UP | IFF_BROADCAST) &&
	  (sap->sin_family == AF_INET)) {
	printf("trying address %s\n", inet_ntoa(bap->sin_addr));
	foundhere = discover_fpgas_at_addr(bap->sin_addr.s_addr,
				   hzpath, found+total, max-total);
	if (foundhere != 0) {
	  printf("found %d FPGAs with address %s\n",
		 inet_ntoa(bap->sin_addr));
	  total += foundhere;
	}	
      }
      p = p->ifa_next;
    }
    return total;
  } else {
    perror("getifaddrs():");
    return 0;
  }
}
			
// We now take the address to broadcast to. Use discover_all_fpgas
// to find any on any interface
int discover_fpgas_at_addr(in_addr_t bcast_addr,
		   ip_path_t *hzpath, ip_fpga_t *found, int max) {
  struct timeval timeout;
  socklen_t slen;  
  fd_set readfds, masterfds;
  int nfound = 0;
  int sockfd = hzpath->sockfd;
  broadcast_id(hzpath, bcast_addr);

  FD_ZERO(&masterfds);
  FD_SET(sockfd, &masterfds);
  do {
    timeout.tv_sec = 0;
    timeout.tv_usec = 50000;
    memcpy(&readfds, &masterfds, sizeof(fd_set));
    if (select(sockfd+1, &readfds, NULL, NULL, &timeout) < 0) {
      perror("error selecting");
      exit(1);      
    }
    if (FD_ISSET(sockfd, &readfds)) {
      uint8_t txbuf[16];
      char cbuf[512];
      
      struct sockaddr_in cliaddr;

      struct iovec iov[1];
      iov[0].iov_base = txbuf;
      iov[0].iov_len = sizeof(txbuf);
      struct msghdr message;
      struct cmsghdr *cmsg;
      uint32_t ifindex;
      
      message.msg_name = &cliaddr;
      message.msg_namelen=sizeof(cliaddr);
      message.msg_iov= iov;
      message.msg_iovlen = 1;
      message.msg_control=cbuf;
      message.msg_controllen=sizeof(cbuf);
      
      ssize_t rn;
      rn = recvmsg(sockfd, &message, 0);
      if (rn == 15) {
	if (txbuf[0] == 'I' && txbuf[1] == 'D' && !txbuf[2]) {
	  // Drop the entire attempt of finding out which interface
	  // it came on.
	  /*
	  for (cmsg=CMSG_FIRSTHDR(&message);
	       cmsg!= NULL;
	       cmsg = CMSG_NXTHDR(&message, cmsg)) {
	    if (cmsg->cmsg_level == IPPROTO_IP && cmsg->cmsg_type == IP_PKTINFO) {
	      ifindex = ((struct in_pktinfo*)CMSG_DATA(cmsg))->ipi_ifindex;
	      found[nfound].ifindex = ifindex;
	    }
	  }
	  */
	  // just fill it with zero
	  found[nfound].ifindex = 0;
	  uint32_t tmp;
	  // this is an ID packet
	  // extract the device DNA
	  // 3/4/5/6 are nominally the IP address
	  tmp = (txbuf[7] << 24) |
	    (txbuf[8] << 16) |
	    (txbuf[9] << 8) |
	    (txbuf[10]);
	  found[nfound].dna[1] = tmp;
	  tmp = (txbuf[11] << 24) |
	    (txbuf[12] << 16) |
	    (txbuf[13] << 8) |
	    (txbuf[14]);
	  found[nfound].dna[0] = tmp;
	  found[nfound].addr = cliaddr;
	  nfound++;
	}	
      }
    } else {
      break;
    }
  } while(1);
  return nfound;
}

