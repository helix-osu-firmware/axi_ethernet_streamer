# AXI Ethernet Streamer

This module acts to provide an AXI4-Stream interface
via a UDP/IP connection.

The module supports device discovery (using broadcast
addresses), dynamic IP addresses (using DHCP) as well
as static addresses.

It currently does not support routing - the partner
must be on the same Ethernet subnet. This will 
change in the future, handling a routing table in
hardware is easy (outbound IP = router if
(dest IP & subnet mask != my IP & subnet mask)),
I just haven't done it yet.

# TL;DR (too long, didn't read)

* `cd software; make`
* Plug the thing into a network with a DHCP server that you're connected to directly.
* Wait like, 3 seconds or something
* `hxeth`


# Setting the device IP

There are 3 ways to set the device IP.

* Dynamically, using DHCP, just like any other network device
* Statically, via the control port. This can only be done if the device
  currently has an IP address _or_ if the device's DNA is known.
* Forcibly, using the stream_debug_vio's "vio_ip_address" and "vio_ip_force"
  ports.

Note that the device's DNA can be obtained via the Hardware Manager
under the Device Properties->Register->EFUSE->DNA_PORT property.
See Xilinx Answer Record #64178

https://www.xilinx.com/support/answers/64178.html

although the value desired is the DNA_PORT property, not the FUSE_DNA
property (which contains the full 64-bit unique device DNA, rather than
the 57-bit version accessible via DNA_PORT).

# Commanding the core

The streamer uses 2 UDP ports, one for control
and one for data passing.

## Control port ('HY', 18521)

The control port allows for device discovery, enabling
incoming/outgoing data, and setting a static IP
address. There are 5 total commands: identify (ID),
open (OP), close (CL), static IP (SI), and dynamic IP (DI).

***Note*** : the reason for having an open/close setup
is to indicate to the rest of the firmware when data should
be broadcast out to Ethernet (and when it should be accepted
as well). This allows the Ethernet streamer to be used as a
"spy" using an AXI4-Stream Broadcaster IP, and also an
auxiliary input using an AXI4-Stream Switch.

If an AXI4-Stream Broadcaster is used, the only downside
to leaving the stream open accidentally is that the outgoing
data will be rate-limited by Ethernet (because the AXI4-Stream
Broadcaster waits until both ports are able to accept data).

All commands consist of 2 bytes plus a terminating null byte,
plus any additional data. All arguments are in network byte order
(big endian).

### Identify (ID)

Command: 3 bytes.

|  0  |  1  |  2  |
|:---:|:---:|:---:|
| 'I' | 'D' | 0x0 |


Response: 15 bytes.

|  0  |  1  |  2  |       [3:6]      |   [7:14]   |
|:---:|:---:|:---:|:----------------:|:----------:|
| 'I' | 'D' | 0x0 |  FPGA IP Address | Device DNA |

The identify command allows for using a UDP broadcast to locate
a device on the network. Device DNA is used for identification
in the static IP (SI) and dynamic IP (DI) commands.

### Static IP (SI)

Command : 15 bytes.

|  0  |  1  |  2  |       [3:10]     |     [11:14]       |
|:---:|:---:|:---:|:----------------:|:-----------------:|
| 'S' | 'I' | 0x0 |Target Device DNA | Target IP Address |

Response: 3 bytes

|  0  |  1  |  2  |
|:---:|:---:|:---:|
| 'S' | 'I' | 0x0 |

The static IP command allows assigning an IP address to
a device via the network (without a DHCP server). To do this,
you must already know the device DNA since without an
IP address, the device's response to a broadcast will
be dropped by the network. The command should then
be sent to the broadcast IP address (or to the device's
current IP address if you want to change it).


### Dynamic IP (DI)

Command : 11 bytes.

|  0  |  1  |  2  |       [3:10]     |
|:---:|:---:|:---:|:----------------:|
| 'D' | 'I' | 0x0 |Target Device DNA |

Response: None (no IP address!)

The dynamic IP command tells the device to drop its current
IP address and begin the DHCP process. Note that this isn't
needed to start the process, as the device begins a DHCP
attempt a few seconds after startup by default.

### Open (OP)

Command : 5 bytes.

|  0  |  1  |  2  |       [3:4]      |
|:---:|:---:|:---:|:----------------:|
| 'O' | 'P' | 0x0 | Destination Port |

Response : 3 bytes.

|  0  |  1  |  2  |
|:---:|:---:|:---:|
| 'O' | 'P' | 0x0 |

The open command begins streaming outbound data from the HX
(18520) port to the Destination Port specified in the command,
and similarly accepts inbound streaming data from that port
on the HX (18520) port.

### Close (CL)

Command/Response : 3 bytes.

|  0  |  1  |  2  |
|:---:|:---:|:---:|
| 'C' | 'L' | 0x0 |

The close command terminates streaming data and no
longer accepts any streaming data.

## Stream port ('HX', 18520)

The stream port merely converts UDP datagrams to AXI4-Stream
packets and vice versa. The maximum size outbound UDP datagram
is a bit under 2048 bytes, because the AXI EthernetLite core
only has 2048 byte buffers.

Note that the AXI4-Stream input must have the total length
of the packet as the first two bytes (_little endian_ since
AXI4-Stream is evil). This may require an additional flow
buffer to store a full packet and count the bytes. An example
of this (tof_udp_flow_buffer.v) is shown in the helper
directory, accepting a 16-bit stream input which then
would be converted to 8-bit via an AXI Width Converter
core.

# Integrating the AXI Ethernet Streamer

There are two main modules provided here:

* axi_ethernet_streamer.v
* streaming_udp_ip_wrapper.v

axi_ethernet_streamer provides a pure AXI4-Stream output interface
with no UDP or IP layer.

streaming_udp_ip_wrapper integrates a UDP/IP core, a DHCP port handler,
the HY port handler, and the HX port handler.

The two modules should be connected together (streaming_udp_ip_wrapper's
m_axis_tx -> axi_ethernet_streamer's s_axis_eth_tx_ , and likewise
for the rx path).

## Helper modules

A full wrapper integrating to a HELIX-style AXI4-Stream is located
in helper/ along with the IP used there (arty_eth_wrap.v). An additional
adapter may be needed if the MAC interface does not use MII.

# Software

Simple interface software is located under software/, with
functions in hxlib.c for generic communication, and an
example (showing HELIX control packets) in hxeth.c.

# UDP/IP Core

This module uses the UDP/IP core from OpenCores:

https://opencores.org/projects/udp_ip__core

Instead of using the (non-free) Ethernet Tri-Mode MAC
from Xilinx, this module uses the AXI EthernetLite
module adapted to provide a Tri-Mode MAC like interface
using a PicoBlaze and a few DataMover cores.
