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

# UDP/IP Core

This module uses the UDP/IP core from OpenCores:

https://opencores.org/projects/udp_ip__core

Instead of using the (non-free) Ethernet Tri-Mode MAC
from Xilinx, this module uses the AXI EthernetLite
module adapted to provide a Tri-Mode MAC like interface
using a PicoBlaze and a few DataMover cores.