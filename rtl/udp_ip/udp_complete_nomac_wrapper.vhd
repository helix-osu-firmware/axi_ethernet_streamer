-- This is just a wrapper around the UDP_Complete_nomac module to get rid of
-- the record interfaces.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.axi.all;
use work.ipv4_types.all;
use work.arp_types.all;

entity udp_complete_nomac_wrapper is
         generic (
                        CLOCK_FREQ                      : integer := 125000000;                                                 -- freq of data_in_clk -- needed to timout cntr
                        ARP_TIMEOUT                     : integer := 60;                                                                        -- ARP response timeout (s)
                        ARP_MAX_PKT_TMO : integer := 5;                                                                 -- # wrong nwk pkts received before set error
                        MAX_ARP_ENTRIES         : integer := 255                                                                        -- max entries in the ARP store
                        );
    Port (
                        -- UDP TX signals
                        udp_tx_start                    : in std_logic;                                                 -- indicates req to tx UDP
                        --
                        udp_tx_dst_ip_addr              : in std_logic_vector(31 downto 0);
                        udp_tx_dst_port                 : in std_logic_vector(15 downto 0);
                        udp_tx_src_port                 : in std_logic_vector(15 downto 0);
                        udp_tx_data_length              : in std_logic_vector(15 downto 0);
                        udp_tx_checksum                 : in std_logic_vector(15 downto 0);  
                        udp_tx_data_out                     : in std_logic_vector(7 downto 0);
                        udp_tx_data_out_valid            : in std_logic;
                        udp_tx_data_out_last             : in std_logic;
                        udp_tx_result                   : out std_logic_vector (1 downto 0);-- tx status (changes during transmission)
                        udp_tx_data_out_ready: out std_logic;                                                   -- indicates udp_tx is ready to take data
                        -- UDP RX signals
                        udp_rx_start                    : out std_logic;                                                        -- indicates receipt of udp header
                        -- 
                        udp_rx_is_valid                 : out std_logic;
                        udp_rx_src_ip_addr              : out std_logic_vector(31 downto 0);
                        udp_rx_src_port                 : out std_logic_vector(15 downto 0);
                        udp_rx_dst_port                 : out std_logic_vector(15 downto 0);
                        udp_rx_data_length              : out std_logic_vector(15 downto 0);
                        udp_rx_data_in                 : out std_logic_vector(7 downto 0);
                        udp_rx_data_in_valid           : out std_logic;
                        udp_rx_data_in_last            : out std_logic;
                        -- IP RX signals
                        ip_rx_hdr_data_length          : out std_logic_vector(15 downto 0);
                        ip_rx_hdr_is_broadcast         : out std_logic;
                        ip_rx_hdr_is_valid             : out std_logic;
                        ip_rx_hdr_last_error_code      : out std_logic_vector(3 downto 0);
                        ip_rx_hdr_num_frame_errors     : out std_logic_vector(7 downto 0);
                        ip_rx_hdr_protocol             : out std_logic_vector(7 downto 0);
                        ip_rx_hdr_src_ip_addr          : out std_logic_vector(31 downto 0);
--                        ip_rx_hdr                               : out ipv4_rx_header_type;
                        -- system signals
            			rx_clk					: in  STD_LOGIC;
                        tx_clk                    : in  STD_LOGIC;
                        reset                     : in  STD_LOGIC;
                        sec_timer               : out STD_LOGIC;
                        our_ip_address          : in STD_LOGIC_VECTOR (31 downto 0);
                        our_mac_address                 : in std_logic_vector (47 downto 0);
                        --
                        arp_clear_cache      : in std_logic;
                        -- status signals
                        arp_pkt_count                   : out STD_LOGIC_VECTOR(7 downto 0);                     -- count of arp pkts received
                        ip_pkt_count                    : out STD_LOGIC_VECTOR(7 downto 0);                     -- number of IP pkts received for us
            			-- MAC Transmitter
                        mac_tx_tdata         : out  std_logic_vector(7 downto 0);    -- data byte to tx
                        mac_tx_tvalid        : out  std_logic;                            -- tdata is valid
                        mac_tx_tready        : in std_logic;                            -- mac is ready to accept data
                        mac_tx_tfirst        : out  std_logic;                            -- indicates first byte of frame
                        mac_tx_tlast         : out  std_logic;                            -- indicates last byte of frame
                        -- MAC Receiver
                        mac_rx_tdata         : in std_logic_vector(7 downto 0);    -- data byte received
                        mac_rx_tvalid        : in std_logic;                            -- indicates tdata is valid
                        mac_rx_tready        : out  std_logic;                            -- tells mac that we are ready to take data
                        mac_rx_tlast         : in std_logic                                -- indicates last byte of the trame
                        );
end udp_complete_nomac_wrapper;
 
architecture Behavioral of udp_complete_nomac_wrapper is
  ------------------------------------------------------------------------------
  -- Component Declaration for the complete UDP layer
  ------------------------------------------------------------------------------
component UDP_Complete_nomac
         generic (
                        CLOCK_FREQ                      : integer := 125000000;                                                 -- freq of data_in_clk -- needed to timout cntr
                        ARP_TIMEOUT                     : integer := 60;                                                                        -- ARP response timeout (s)
                        ARP_MAX_PKT_TMO : integer := 5;                                                                 -- # wrong nwk pkts received before set error
                        MAX_ARP_ENTRIES         : integer := 255                                                                        -- max entries in the ARP store
                        );
    Port (
                        -- UDP TX signals
                        udp_tx_start                    : in std_logic;                                                 -- indicates req to tx UDP
                        udp_txi                                 : in udp_tx_type;                                                       -- UDP tx cxns
                        udp_tx_result                   : out std_logic_vector (1 downto 0);-- tx status (changes during transmission)
                        udp_tx_data_out_ready: out std_logic;                                                   -- indicates udp_tx is ready to take data
                        -- UDP RX signals
                        udp_rx_start                    : out std_logic;                                                        -- indicates receipt of udp header
                        udp_rxo                                 : out udp_rx_type;
                        -- IP RX signals
                        ip_rx_hdr                               : out ipv4_rx_header_type;
                        -- system signals
                        rx_clk               : in std_logic;
                        tx_clk               : in std_logic;
                        reset                                   : in  STD_LOGIC;
                        sec_timer           : out STD_LOGIC;
                        our_ip_address          : in STD_LOGIC_VECTOR (31 downto 0);
                        our_mac_address                 : in std_logic_vector (47 downto 0);
                        control                                 : in udp_control_type;
                        -- status signals
                        arp_pkt_count                   : out STD_LOGIC_VECTOR(7 downto 0);                     -- count of arp pkts received
                        ip_pkt_count                    : out STD_LOGIC_VECTOR(7 downto 0);                     -- number of IP pkts received for us
            			-- MAC Transmitter
                        mac_tx_tdata         : out  std_logic_vector(7 downto 0);    -- data byte to tx
                        mac_tx_tvalid        : out  std_logic;                            -- tdata is valid
                        mac_tx_tready        : in std_logic;                            -- mac is ready to accept data
                        mac_tx_tfirst        : out  std_logic;                            -- indicates first byte of frame
                        mac_tx_tlast         : out  std_logic;                            -- indicates last byte of frame
                        -- MAC Receiver
                        mac_rx_tdata         : in std_logic_vector(7 downto 0);    -- data byte received
                        mac_rx_tvalid        : in std_logic;                            -- indicates tdata is valid
                        mac_rx_tready        : out  std_logic;                            -- tells mac that we are ready to take data
                        mac_rx_tlast         : in std_logic                                -- indicates last byte of the trame
                        );
end component;

    signal  udp_txi : udp_tx_type;
    signal  udp_rxo : udp_rx_type;
    signal  control : udp_control_type;
    signal  ip_rx_hdr : ipv4_rx_header_type;
begin
    udp_txi.hdr.dst_ip_addr <= udp_tx_dst_ip_addr;
    udp_txi.hdr.dst_port <= udp_tx_dst_port;
    udp_txi.hdr.src_port <= udp_tx_src_port;
    udp_txi.hdr.data_length <= udp_tx_data_length;
    udp_txi.hdr.checksum <= udp_tx_checksum;
    udp_txi.data.data_out <= udp_tx_data_out;
    udp_txi.data.data_out_valid <= udp_tx_data_out_valid;
    udp_txi.data.data_out_last <= udp_tx_data_out_last;

    udp_rx_is_valid <= udp_rxo.hdr.is_valid;
    udp_rx_src_ip_addr <= udp_rxo.hdr.src_ip_addr;
    udp_rx_src_port <= udp_rxo.hdr.src_port;
    udp_rx_dst_port <= udp_rxo.hdr.dst_port;
    udp_rx_data_length <= udp_rxo.hdr.data_length;
    
    udp_rx_data_in <= udp_rxo.data.data_in;
    udp_rx_data_in_valid <= udp_rxo.data.data_in_valid;
    udp_rx_data_in_last <= udp_rxo.data.data_in_last;
    
    control.ip_controls.arp_controls.clear_cache <= arp_clear_cache;

    ip_rx_hdr_data_length <= ip_rx_hdr.data_length;
    ip_rx_hdr_is_broadcast <= ip_rx_hdr.is_broadcast;
    ip_rx_hdr_is_valid <= ip_rx_hdr.is_valid;
    ip_rx_hdr_last_error_code <= ip_rx_hdr.last_error_code;
    ip_rx_hdr_num_frame_errors <= ip_rx_hdr.num_frame_errors;
    ip_rx_hdr_protocol <= ip_rx_hdr.protocol;
    ip_rx_hdr_src_ip_addr <= ip_rx_hdr.src_ip_addr;
    
    UDP_block : UDP_Complete_nomac
                generic map (
                                ARP_TIMEOUT             => ARP_TIMEOUT,           -- timeout in seconds
                                CLOCK_FREQ              => CLOCK_FREQ,
                                ARP_MAX_PKT_TMO         => ARP_MAX_PKT_TMO,
                                MAX_ARP_ENTRIES         => MAX_ARP_ENTRIES
                         )
                PORT MAP (
                                -- UDP interface
                                udp_tx_start                    => udp_tx_start,
                                udp_txi                                         => udp_txi,
                                udp_tx_result                   => udp_tx_result,
                                udp_tx_data_out_ready=> udp_tx_data_out_ready,
                                udp_rx_start                    => udp_rx_start,
                                udp_rxo                                         => udp_rxo,
                                -- IP RX signals
                                ip_rx_hdr                               => ip_rx_hdr,
                                -- System interface
                                rx_clk              => rx_clk,
                                tx_clk             => tx_clk,
                                reset                                   => reset,
                                sec_timer          => sec_timer,
                                our_ip_address          => our_ip_address,
                                our_mac_address                 => our_mac_address,
                                control                                 => control,
                                -- status signals
                                arp_pkt_count                   => arp_pkt_count,
                                ip_pkt_count                    => ip_pkt_count,
                                        -- MAC Transmitter
                                  mac_tx_tready                 => mac_tx_tready,
                                  mac_tx_tvalid                 => mac_tx_tvalid,
                                  mac_tx_tfirst                  => mac_tx_tfirst,
                                  mac_tx_tlast                  => mac_tx_tlast,
                                  mac_tx_tdata                  => mac_tx_tdata,
                                            -- MAC Receiver
                                  mac_rx_tdata                  => mac_rx_tdata,
                                  mac_rx_tvalid                 => mac_rx_tvalid,
                                  mac_rx_tready                  => mac_rx_tready,
                                  mac_rx_tlast                  => mac_rx_tlast                                                         
        );

end Behavioral;
