-------------------------------------------------------------------------------
-- barrel_shifter.vhd
--
-- delays signals for a set number of clock cycles
--	
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use IEEE.numeric_bit.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

-------------------------------------------------------------------------------

ENTITY barrel_shifter IS  
  PORT(

	 i_clk		             : IN  STD_LOGIC;
	 i_rst		             :	IN  STD_LOGIC;
  
   	i_valid  		         :	IN  STD_LOGIC;				                          	        --input data valid
	 iv_data		           :	IN  STD_LOGIC_VECTOR (64-1 DOWNTO 0);	               --input data
	 
	 iv_byte_num         :	IN  STD_LOGIC_VECTOR (12-1 DOWNTO 0);	               --input start of frame	 
   	i_read_enable  		   :	IN  STD_LOGIC;				                          	        --input error signal, used to reset the state machine and barrel shifter
	 i_clear_reg         :	IN  STD_LOGIC;	                                      --input end of frame	 

	 o_valid       	     :	OUT STD_LOGIC;					                                  --output read enable to enable reading from the barrel shifter
	 ov_data             :	OUT STD_LOGIC_VECTOR (64-1  DOWNTO 0)                --output byte number to indicate to the barrel shifter where to read from next
	
  );
END barrel_shifter;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF barrel_shifter IS
 

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------

-- input_store_reg -- MTU is 1526 bytes for a simple IP packet including preammble and SFD
--                 -- with PBB VLAN and max MPLS MTU is 1578 bytes
SIGNAL sv_store_count          : STD_LOGIC_VECTOR(6-1 DOWNTO 0);
SIGNAL sv_frame_capture        : STD_LOGIC_VECTOR(64*198-1 DOWNTO 0); -- 1578 * 8 

-- output_data_reg
SIGNAL s_valid                 : STD_LOGIC;
SIGNAL sv_data_out             : STD_LOGIC_VECTOR(64-1 DOWNTO 0);

-------------------------------------------------------------------------------

BEGIN	-- rtl

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- capture the input data into the barrel
-------------------------------------------------------------------------------
input_store_reg: PROCESS(i_clk, i_rst)

BEGIN

  IF (i_rst                    = '1') THEN
   
    sv_store_count            <= (OTHERS => '0');  
    sv_frame_capture          <= (OTHERS => '0');        
    
  ELSIF (i_clk'event and i_clk = '1') THEN
        
    IF    (i_clear_reg       = '1') THEN
        
      sv_store_count        <= (OTHERS => '0');
      sv_frame_capture      <= (OTHERS => '0');
      
    ELSE
      IF    (i_valid         = '1') THEN
            
        sv_store_count      <= sv_store_count + 1;
          
        sv_frame_capture((((198-CONV_INTEGER(sv_store_count))*64)-1) DOWNTO (((198-CONV_INTEGER(sv_store_count))-1)*64))   <= iv_data;
      ELSE 
    
        sv_store_count      <= sv_store_count;
        sv_frame_capture    <= sv_frame_capture;
      END IF;     
    END IF;      
  END IF;
END PROCESS input_store_reg;

-------------------------------------------------------------------------------
-- output from barrel starting at byte sv_byte_num when read enable is high
-------------------------------------------------------------------------------
output_data_reg: PROCESS(i_clk, i_rst)

BEGIN

  IF (i_rst                    = '1') THEN
   
    s_valid                   <= '0'; 
    sv_data_out               <= (OTHERS => '0'); 
   
  ELSIF (i_clk'event and i_clk = '1') THEN
    
    s_valid                   <= '0';
    sv_data_out               <= (OTHERS => '0'); 
    
    IF    (i_read_enable       = '1') THEN
      
      s_valid                 <= '1';    
      sv_data_out             <= sv_frame_capture((((1584 - CONV_INTEGER(iv_byte_num))*8)-1) DOWNTO ((1576 - CONV_INTEGER(iv_byte_num))*8));

    END IF;     
      
  END IF;
END PROCESS output_data_reg;

o_valid <= s_valid;
ov_data <= sv_data_out;

END ARCHITECTURE rtl;

--------------------------------------------------------------