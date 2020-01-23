--
-------------------------------------------------------------------------------------------
-- Copyright � 2010-2013, Xilinx, Inc.
-- This file contains confidential and proprietary information of Xilinx, Inc. and is
-- protected under U.S. and international copyright and other intellectual property laws.
-------------------------------------------------------------------------------------------
--
-- Disclaimer:
-- This disclaimer is not a license and does not grant any rights to the materials
-- distributed herewith. Except as otherwise provided in a valid license issued to
-- you by Xilinx, and to the maximum extent permitted by applicable law: (1) THESE
-- MATERIALS ARE MADE AVAILABLE "AS IS" AND WITH ALL FAULTS, AND XILINX HEREBY
-- DISCLAIMS ALL WARRANTIES AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY,
-- INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-INFRINGEMENT,
-- OR FITNESS FOR ANY PARTICULAR PURPOSE; and (2) Xilinx shall not be liable
-- (whether in contract or tort, including negligence, or under any other theory
-- of liability) for any loss or damage of any kind or nature related to, arising
-- under or in connection with these materials, including for any direct, or any
-- indirect, special, incidental, or consequential loss or damage (including loss
-- of data, profits, goodwill, or any type of loss or damage suffered as a result
-- of any action brought by a third party) even if such damage or loss was
-- reasonably foreseeable or Xilinx had been advised of the possibility of the same.
--
-- CRITICAL APPLICATIONS
-- Xilinx products are not designed or intended to be fail-safe, or for use in any
-- application requiring fail-safe performance, such as life-support or safety
-- devices or systems, Class III medical devices, nuclear facilities, applications
-- related to the deployment of airbags, or any other applications that could lead
-- to death, personal injury, or severe property or environmental damage
-- (individually and collectively, "Critical Applications"). Customer assumes the
-- sole risk and liability of any use of Xilinx products in Critical Applications,
-- subject only to applicable laws and regulations governing limitations on product
-- liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS PART OF THIS FILE AT ALL TIMES.
--
-------------------------------------------------------------------------------------------
--
--
-- Production definition of a 1K program for KCPSM6 in a 7-Series device using a 
-- RAMB18E1 primitive.
--
-- Note: The complete 12-bit address bus is connected to KCPSM6 to facilitate future code 
--       expansion with minimum changes being required to the hardware description. 
--       Only the lower 10-bits of the address are actually used for the 1K address range
--       000 to 3FF hex.  
--
-- Program defined by 'C:\Users\allison.122.ASC\Box\firmware\tof_bootload\ethernet\src\dhcp\dhcp_picoblaze_rom.psm'.
--
-- Generated by KCPSM6 Assembler: 15 Jan 2020 - 01:33:25. 
--
-- Assembler used ROM_form template: ROM_form_7S_1K_14March13.vhd
--
--
-- Standard IEEE libraries
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
--
-- The Unisim Library is used to define Xilinx primitives. It is also used during
-- simulation. The source can be viewed at %XILINX%\vhdl\src\unisims\unisim_VCOMP.vhd
--  
library unisim;
use unisim.vcomponents.all;
--
--
entity dhcp_picoblaze_rom is
    Port (      address : in std_logic_vector(11 downto 0);
            instruction : out std_logic_vector(17 downto 0);
                 enable : in std_logic;
                    clk : in std_logic;
		    bram_adr_i : in std_logic_vector(10 downto 0);
		    bram_dat_o : out std_logic_vector(8 downto 0);
		    bram_dat_i : in std_logic_vector(8 downto 0);
		    bram_we_i : in std_logic;
		    bram_rd_i : in std_logic;
		    bram_ack_o : out std_logic);
    end dhcp_picoblaze_rom;
--
architecture low_level_definition of dhcp_picoblaze_rom is
--
signal  address_a : std_logic_vector(13 downto 0);
signal  data_in_a : std_logic_vector(17 downto 0);
signal data_out_a : std_logic_vector(17 downto 0);
signal  address_b : std_logic_vector(13 downto 0);
signal  data_in_b : std_logic_vector(17 downto 0);
signal data_out_b : std_logic_vector(17 downto 0);
signal   enable_b : std_logic;
signal      clk_b : std_logic;
signal       we_b : std_logic_vector(3 downto 0);
signal	     ack  : std_logic;
--
begin
--
  -- The 'address' input is really only 10 bits. Concatenate with 1s per BRAM guide (use 13:4)
  address_a <= address(9 downto 0) & "1111";
  instruction <= data_out_a(17 downto 0);
  -- dunno WTF this is here for.
  data_in_a <= "0000000000000000" & address(11 downto 10);
  -- The 'address' input here is 11 bits. Add 3 more to hit the 14-bit ADDR bus.
  address_b <= bram_adr_i & "111";
  -- The "0"s here are unused. They're fed into DIP(1) and DI(15:8).
  data_in_b <= "0" & bram_dat_i(8) & "00000000" & bram_dat_i(7 downto 0);
  bram_dat_o <= data_out_b(16) & data_out_b(7 downto 0);
  enable_b <= bram_we_i or bram_rd_i;
  we_b <= "000" & bram_we_i;
  clk_b <= clk;
  bram_ack_o <= ack;
  ack_process : process (clk)
  begin
	if (rising_edge(clk)) then
	   ack <= bram_we_i or bram_rd_i;
	end if;
  end process;
  --
  --
  -- 
  kcpsm6_rom: RAMB18E1
  generic map ( READ_WIDTH_A => 18,
                WRITE_WIDTH_A => 18,
                DOA_REG => 0,
                INIT_A => "000000000000000000",
                RSTREG_PRIORITY_A => "REGCE",
                SRVAL_A => X"000000000000000000",
                WRITE_MODE_A => "WRITE_FIRST",
                READ_WIDTH_B => 9,
                WRITE_WIDTH_B => 9,
                DOB_REG => 0,
                INIT_B => X"000000000000000000",
                RSTREG_PRIORITY_B => "REGCE",
                SRVAL_B => X"000000000000000000",
                WRITE_MODE_B => "WRITE_FIRST",
                INIT_FILE => "NONE",
                SIM_COLLISION_CHECK => "ALL",
                RAM_MODE => "TDP",
                RDADDR_COLLISION_HWCONFIG => "DELAYED_WRITE",
                SIM_DEVICE => "7SERIES",
                INIT_00 => X"2027DE012016DE00F003F002F001F00010001E009D0D9C0C9B0B9A0A99099808",
                INIT_01 => X"D0008001B303B202B101B0008000200CD0409000200C1E0020E2DE032052DE02",
                INIT_02 => X"1107D1F3113DD1F2D1F11101D1F011350127200C1E01200C2025F300F200F100",
                INIT_03 => X"1010D103D002110010FCD0FC10FFDDFBDCFADBF9DAF8D9F7D8F6D1F51101D1F4",
                INIT_04 => X"F303F202F101F000800013001200110010031E02D00010016041D0109000D000",
                INIT_05 => X"D00010012061F3EFF2BEF1ADD0DE931392129111901020D2D0049000200C8001",
                INIT_06 => X"D136812012F31301605ED00290F2605ED03590F0D0011001606130079000200C",
                INIT_07 => X"1407605ED1048120A05E011C1101206EA05E011C11018120A05E011C11012079",
                INIT_08 => X"D106D0079393929291919090D00110006080D4039401E1408120A05E011C1101",
                INIT_09 => X"D1F51101D1F41107D1F3113DD1F21103D1F11101D1F01135D0011001D304D205",
                INIT_0A => X"D0011002D1FF9106D1FE9107D1FD1104D1FC1132DDFBDCFADBF9DAF8D9F7D8F6",
                INIT_0B => X"D187B104D186B105D185B106D184B107D1831104D1821136D1819104D1809105",
                INIT_0C => X"D000100160CBD0109000D0001010D103D002110110080127D0011000D18811FF",
                INIT_0D => X"F300F200F100D0008001B303B202B101B0008000205E60D630079000200C1E03",
                INIT_0E => X"D000100120F1F3EFF2BEF1ADD0DE9313921291119010210CD00490001E00600C",
                INIT_0F => X"10806101D080900060EED00590F260EED03590F0D001100160F130039000200C",
                INIT_10 => X"20EE6110300790001E008001F303F202F101F00080001300120011A810C0D000",
                INIT_11 => X"D3041301D00002101E00600CF300F200F100D0008001B303B202B101B0008000",
                INIT_12 => X"11DED083D1821106D181D1801101D00110005000D305211ED0001280D3012125",
                INIT_13 => X"613CD29C1201C020128BD18A1180D089D088D18711EFD18611BED18511ADD184",
                INIT_14 => X"1201C0201280D20112016147D2001201C02012A2DDA1DCA0DB9FDA9ED99DD89C",
                INIT_15 => X"B303B202B101B00070015000D4EFD3EED2EDD1EC1463135312821163614ED2EC",
                INIT_16 => X"0000000000000000000090017000F303F202F101F000A169B300B200B1009001",
                INIT_17 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_18 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_19 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_1A => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_1B => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_1C => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_1D => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_1E => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_1F => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_20 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_21 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_22 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_23 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_24 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_25 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_26 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_27 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_28 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_29 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_2A => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_2B => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_2C => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_2D => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_2E => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_2F => X"215B000000000000000000000000000000000000000000000000000000000000",
                INIT_30 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_31 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_32 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_33 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_34 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_35 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_36 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_37 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_38 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_39 => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_3A => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_3B => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_3C => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_3D => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_3E => X"0000000000000000000000000000000000000000000000000000000000000000",
                INIT_3F => X"0000000000000000000000000000000000000000000000000000000000000000",
               INITP_00 => X"34E2E4E340D348C28D54030AAA8008C22822AAA22288A2D5600B08DDDDAA0000",
               INITP_01 => X"30D348C28D54030355802B088C2282888888888888888AAA8888888AA008D638",
               INITP_02 => X"00000000002EAB5500EAA00D62358AAAD622A22228A226DB5D355802B02AA802",
               INITP_03 => X"0000000000000000000000000000000000000000000000000000000000000000",
               INITP_04 => X"0000000000000000000000000000000000000000000000000000000000000000",
               INITP_05 => X"8000000000000000000000000000000000000000000000000000000000000000",
               INITP_06 => X"0000000000000000000000000000000000000000000000000000000000000000",
               INITP_07 => X"0000000000000000000000000000000000000000000000000000000000000000")
  port map(   ADDRARDADDR => address_a,
                  ENARDEN => enable,
                CLKARDCLK => clk,
                    DOADO => data_out_a(15 downto 0),
                  DOPADOP => data_out_a(17 downto 16), 
                    DIADI => data_in_a(15 downto 0),
                  DIPADIP => data_in_a(17 downto 16), 
                      WEA => "00",
              REGCEAREGCE => '0',
            RSTRAMARSTRAM => '0',
            RSTREGARSTREG => '0',
              ADDRBWRADDR => address_b,
                  ENBWREN => enable_b,
                CLKBWRCLK => clk_b,
                    DOBDO => data_out_b(15 downto 0),
                  DOPBDOP => data_out_b(17 downto 16), 
                    DIBDI => data_in_b(15 downto 0),
                  DIPBDIP => data_in_b(17 downto 16), 
                    WEBWE => we_b,
                   REGCEB => '0',
                  RSTRAMB => '0',
                  RSTREGB => '0');
--
--
end low_level_definition;
--
------------------------------------------------------------------------------------
--
-- END OF FILE dhcp_picoblaze_rom.vhd
--
------------------------------------------------------------------------------------
