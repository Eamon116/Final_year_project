-- ddr_to_sdr.vhd
--
-- converts a double data rate to a single data rate on the same clock
--	
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;


-------------------------------------------------------------------------------

ENTITY ddr_to_sdr IS
  GENERIC (
      
    DATA_WIDTH_IN       : INTEGER 
    );  
  PORT(

	 i_clk		             : IN  STD_LOGIC;
	 i_rst		             :	IN  STD_LOGIC;
  
   	 i_valid  		         :	IN  STD_LOGIC;				                          	        --input data valid
	 iv_data		         :	IN  STD_LOGIC_VECTOR (DATA_WIDTH_IN-1 DOWNTO 0);	               --input data
	 	
	 o_valid		           :	OUT STD_LOGIC;					                                  --output data valid
	 ov_data		           :	OUT STD_LOGIC_VECTOR ((DATA_WIDTH_IN*2)-1 DOWNTO 0)	                --output data
	
  );
END ddr_to_sdr;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF ddr_to_sdr IS
 

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------

-- ddr_to_sdr_reg -- signals
SIGNAL s_clk                   : STD_LOGIC;
SIGNAL s_rst                   : STD_LOGIC;

SIGNAL s_single_rate_valid     : STD_LOGIC;

SIGNAL sv_r_double_rate_date   : STD_LOGIC_VECTOR(DATA_WIDTH_IN-1 DOWNTO 0);
SIGNAL sv_f_double_rate_date   : STD_LOGIC_VECTOR(DATA_WIDTH_IN-1 DOWNTO 0);

SIGNAL s_valid                 : STD_LOGIC;
SIGNAL sv_single_rate_date     : STD_LOGIC_VECTOR((DATA_WIDTH_IN*2)-1 DOWNTO 0);


-------------------------------------------------------------------------------

BEGIN	-- rtl

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- register data on both edges of the clock and then re-register on then rising edge
-------------------------------------------------------------------------------
s_clk <= NOT(i_clk);

re_reg_reset_reg: PROCESS(i_clk)
 BEGIN
  IF (i_clk'event and i_clk = '1') THEN --rising
  
  s_rst <= i_rst;

  END IF;
 END PROCESS re_reg_reset_reg;
 
 
ddr_to_sdr_reg: PROCESS(i_clk,i_rst)

BEGIN

  IF i_rst = '1' THEN
    
    s_single_rate_valid       <= '0';
    sv_r_double_rate_date     <= (OTHERS => '0');
            
  ELSIF (i_clk'event and i_clk = '1') THEN --rising
  
    s_single_rate_valid       <= i_valid ;

      
      sv_r_double_rate_date   <=  iv_data;
  END IF;
 END PROCESS ddr_to_sdr_reg;
 
  ddr_to_sdr_f_reg: PROCESS(s_clk,s_rst)
  
  BEGIN   
  IF s_rst = '1' THEN
        
        sv_f_double_rate_date     <= (OTHERS => '0');
        
  ELSIF (s_clk'event and s_clk = '1') THEN --falling
    
            
      sv_f_double_rate_date   <= iv_data;
  END IF;
END PROCESS ddr_to_sdr_f_reg;

output_reg: PROCESS(i_clk,i_rst)

BEGIN

  IF i_rst = '1' THEN
    
    s_valid                   <= '0'; 
    sv_single_rate_date       <= (OTHERS => '0');
            
  ELSIF (i_clk'event and i_clk = '1') THEN --rising
  

    s_valid                   <= s_single_rate_valid;           

    sv_single_rate_date       <= sv_r_double_rate_date & sv_f_double_rate_date;
  END IF;
  END PROCESS output_reg;
      
o_valid <= s_valid;
ov_data <= sv_single_rate_date;
  

END ARCHITECTURE rtl;

--------------------------------------------------------------