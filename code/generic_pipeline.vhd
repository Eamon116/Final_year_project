--------------------------------------------------------------
-- generic_pipeline.vhd
--
-- delays signals for a set number of clock cycles
--	
--------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;


--------------------------------------------------------------

ENTITY generic_pipeline IS
GENERIC(
	
	DATA_WIDTH	:	INTEGER;	
	NUM_OF_DELAYS	:	INTEGER		-- must be for a pipeline greater than 1
);
PORT(

	i_clk		  : IN  STD_LOGIC;
	i_rst		  :	IN  STD_LOGIC;

	i_valid		:	IN  STD_LOGIC;					--input data valid
	iv_data		:	IN  STD_LOGIC_VECTOR (DATA_WIDTH-1 DOWNTO 0);	--input data
	o_valid		:	OUT STD_LOGIC;					--output data valid
	ov_data		:	OUT STD_LOGIC_VECTOR (DATA_WIDTH-1 DOWNTO 0)	--output data
	
);
END generic_pipeline;

--------------------------------------------------------------

ARCHITECTURE rtl OF generic_pipeline IS
 
COMPONENT generic_register IS
GENERIC(
	
	DATA_WIDTH	:	INTEGER	
);
PORT(

	i_clk		  : IN  STD_LOGIC;
	i_rst		  :	IN  STD_LOGIC;

	i_valid		:	IN  STD_LOGIC;					--input data valid
	iv_data		:	IN  STD_LOGIC_VECTOR (DATA_WIDTH-1 DOWNTO 0);	--input data
	o_valid		:	OUT STD_LOGIC;					--output data valid
	ov_data		:	OUT STD_LOGIC_VECTOR (DATA_WIDTH-1 DOWNTO 0)	--output data
	
);
END COMPONENT;
--------------------------------------------------------------


TYPE	PIPELINE_SORT		IS ARRAY (NUM_OF_DELAYS DOWNTO 0) OF STD_LOGIC_VECTOR (DATA_WIDTH DOWNTO 0);	-- array type to store data for specified delay
 

--------------------------------------------------------------


SIGNAL 	sv_pipeline_array	: 	PIPELINE_SORT;			-- array used to register data

BEGIN	--arch begin

sv_pipeline_array(0)		<= (i_valid & iv_data);		-- concatenate valid with data
    
register_array_gen : FOR k IN 0 TO NUM_OF_DELAYS-1 GENERATE    
   generic_register_init : generic_register
   GENERIC MAP(
	
   	DATA_WIDTH	=> DATA_WIDTH+1
   )
   PORT MAP(

   	i_clk		  => i_clk,
   	i_rst		 	=> i_rst,

   	i_valid		=> sv_pipeline_array(k)(DATA_WIDTH),
   	iv_data		=> sv_pipeline_array(k),
   	o_valid		=> sv_pipeline_array(k+1)(DATA_WIDTH),
   	ov_data		=> sv_pipeline_array(k+1)
	
   );	        				
  
END GENERATE;


o_valid		<= sv_pipeline_array(NUM_OF_DELAYS)(DATA_WIDTH);		-- output data valid
ov_data		<= sv_pipeline_array(NUM_OF_DELAYS)(DATA_WIDTH-1 DOWNTO 0);	-- output data

END ARCHITECTURE rtl;

--------------------------------------------------------------