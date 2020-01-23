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
