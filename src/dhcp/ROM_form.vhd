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

ROM_form.vhd

Production template for a 1K program for KCPSM6 in a 7-Series device using a 
RAMB18E1 primitive.

Ken Chapman (Xilinx Ltd)

5th August 2011 - First Release
14th March 2013 - Unused address inputs on BRAMs connected High to reflect 
                  descriptions UG473.



This is a VHDL template file for the KCPSM6 assembler.

This VHDL file is not valid as input directly into a synthesis or a simulation tool.
The assembler will read this template and insert the information required to complete
the definition of program ROM and write it out to a new '.vhd' file that is ready for 
synthesis and simulation.

This template can be modified to define alternative memory definitions. However, you are 
responsible for ensuring the template is correct as the assembler does not perform any 
checking of the VHDL.

The assembler identifies all text enclosed by {} characters, and replaces these
character strings. All templates should include these {} character strings for 
the assembler to work correctly. 


--
Modified by P.S. Allison. Modified to allow for 8-bit read/write access into the BRAM
through the auxiliary port. Obviously this has the potential to do Horrible Things.
So be careful.

The next line is used to determine where the template actually starts.
{begin template}
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
-- Program defined by '{psmname}.psm'.
--
-- Generated by KCPSM6 Assembler: {timestamp}. 
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
entity {name} is
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
    end {name};
--
architecture low_level_definition of {name} is
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
                INIT_00 => X"{INIT_00}",
                INIT_01 => X"{INIT_01}",
                INIT_02 => X"{INIT_02}",
                INIT_03 => X"{INIT_03}",
                INIT_04 => X"{INIT_04}",
                INIT_05 => X"{INIT_05}",
                INIT_06 => X"{INIT_06}",
                INIT_07 => X"{INIT_07}",
                INIT_08 => X"{INIT_08}",
                INIT_09 => X"{INIT_09}",
                INIT_0A => X"{INIT_0A}",
                INIT_0B => X"{INIT_0B}",
                INIT_0C => X"{INIT_0C}",
                INIT_0D => X"{INIT_0D}",
                INIT_0E => X"{INIT_0E}",
                INIT_0F => X"{INIT_0F}",
                INIT_10 => X"{INIT_10}",
                INIT_11 => X"{INIT_11}",
                INIT_12 => X"{INIT_12}",
                INIT_13 => X"{INIT_13}",
                INIT_14 => X"{INIT_14}",
                INIT_15 => X"{INIT_15}",
                INIT_16 => X"{INIT_16}",
                INIT_17 => X"{INIT_17}",
                INIT_18 => X"{INIT_18}",
                INIT_19 => X"{INIT_19}",
                INIT_1A => X"{INIT_1A}",
                INIT_1B => X"{INIT_1B}",
                INIT_1C => X"{INIT_1C}",
                INIT_1D => X"{INIT_1D}",
                INIT_1E => X"{INIT_1E}",
                INIT_1F => X"{INIT_1F}",
                INIT_20 => X"{INIT_20}",
                INIT_21 => X"{INIT_21}",
                INIT_22 => X"{INIT_22}",
                INIT_23 => X"{INIT_23}",
                INIT_24 => X"{INIT_24}",
                INIT_25 => X"{INIT_25}",
                INIT_26 => X"{INIT_26}",
                INIT_27 => X"{INIT_27}",
                INIT_28 => X"{INIT_28}",
                INIT_29 => X"{INIT_29}",
                INIT_2A => X"{INIT_2A}",
                INIT_2B => X"{INIT_2B}",
                INIT_2C => X"{INIT_2C}",
                INIT_2D => X"{INIT_2D}",
                INIT_2E => X"{INIT_2E}",
                INIT_2F => X"{INIT_2F}",
                INIT_30 => X"{INIT_30}",
                INIT_31 => X"{INIT_31}",
                INIT_32 => X"{INIT_32}",
                INIT_33 => X"{INIT_33}",
                INIT_34 => X"{INIT_34}",
                INIT_35 => X"{INIT_35}",
                INIT_36 => X"{INIT_36}",
                INIT_37 => X"{INIT_37}",
                INIT_38 => X"{INIT_38}",
                INIT_39 => X"{INIT_39}",
                INIT_3A => X"{INIT_3A}",
                INIT_3B => X"{INIT_3B}",
                INIT_3C => X"{INIT_3C}",
                INIT_3D => X"{INIT_3D}",
                INIT_3E => X"{INIT_3E}",
                INIT_3F => X"{INIT_3F}",
               INITP_00 => X"{INITP_00}",
               INITP_01 => X"{INITP_01}",
               INITP_02 => X"{INITP_02}",
               INITP_03 => X"{INITP_03}",
               INITP_04 => X"{INITP_04}",
               INITP_05 => X"{INITP_05}",
               INITP_06 => X"{INITP_06}",
               INITP_07 => X"{INITP_07}")
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
-- END OF FILE {name}.vhd
--
------------------------------------------------------------------------------------
