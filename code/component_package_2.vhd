library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_unsigned.all;
      
package component_package is

COMPONENT ddr_to_sdr
  GENERIC (
      
    DATA_WIDTH_IN       : INTEGER 
    );  
  PORT(

	 i_clk		             : IN  STD_LOGIC;
	 i_rst		             :	IN  STD_LOGIC;
  
   	i_valid  		         :	IN  STD_LOGIC;				                          	        --input data valid
	 iv_data		           :	IN  STD_LOGIC_VECTOR (DATA_WIDTH_IN-1 DOWNTO 0);	               --input data
	 	
	 o_valid		           :	OUT STD_LOGIC;					                                  --output data valid
	 ov_data		           :	OUT STD_LOGIC_VECTOR ((DATA_WIDTH_IN*2)-1 DOWNTO 0)	                --output data
	
  );
END COMPONENT;

COMPONENT xgmii_decoder
 
  PORT(

	 i_clk		             : IN  STD_LOGIC;
	 i_rst		             :	IN  STD_LOGIC;
  
   	i_valid  		         :	IN  STD_LOGIC;				                          	        --input data valid
	 iv_cntrl	 	         :	IN  STD_LOGIC_VECTOR (4-1  DOWNTO 0);	               --input xgmii control   	
	 iv_data		           :	IN  STD_LOGIC_VECTOR (32-1 DOWNTO 0);	               --input data
	 	
	 o_valid		           :	OUT STD_LOGIC;					                                  --output data valid
	 ov_data		           :	OUT STD_LOGIC_VECTOR (64-1 DOWNTO 0);                --output data
	 
	 ov_sof		            :	OUT STD_LOGIC_VECTOR (2-1  DOWNTO 0);		              --output start of frame
	 o_err		             :	OUT STD_LOGIC;					                                  --output frame error	 
	 o_eof		             :	OUT STD_LOGIC                                        --output end of frame
	 	
  );
END COMPONENT;

COMPONENT ether_decode   
  PORT(

	 i_clk		             : IN  STD_LOGIC;
	 i_rst		             :	IN  STD_LOGIC;
  
   	i_valid  		         :	IN  STD_LOGIC;				                          	        --input data valid
	 iv_data		           :	IN  STD_LOGIC_VECTOR (64-1 DOWNTO 0);	               --input data
	 
	 iv_sof		            :	IN  STD_LOGIC_VECTOR (2-1 DOWNTO 0);	                --input start of frame	 
   	i_err  		           :	IN  STD_LOGIC;				                          	        --input error signal, used to reset the state machine and barrel shifter
	 i_eof		             :	IN  STD_LOGIC;	                                      --input end of frame	 
	 
	 iv_vlan_defned_tag  : IN  STD_LOGIC_VECTOR (16-1 DOWNTO 0);                --input defined vlan tag which can be set in a cpu register
	
	 o_valid             : OUT STD_LOGIC;
	 ov_data             :	OUT STD_LOGIC_VECTOR (64-1 DOWNTO 0);
	 o_t_err             : OUT STD_LOGIC; 

	 o_sof        		     :	OUT STD_LOGIC;					                                  --output start of frame to indicate to 5 tuple fsm to start
	 o_fr_err            : OUT STD_LOGIC;                                       --output error signal, used to indicate a ether-type field error
	 o_mpls_err          : OUT STD_LOGIC;                                       --output error signal, used to indicate a mpls label error	 
	 o_eof        		     :	OUT STD_LOGIC 					                                  --output end of frame to indicate to 5 tuple fsm to end	 
	
  );
END COMPONENT;

COMPONENT barrel_shifter  
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
END COMPONENT;

COMPONENT tuple_extract 
 
  PORT(

	 i_clk		             : IN  STD_LOGIC;
	 i_rst		             :	IN  STD_LOGIC;
  
   	i_valid  		         :	IN  STD_LOGIC;				                          	        --input data valid
	 iv_data		           :	IN  STD_LOGIC_VECTOR (64-1 DOWNTO 0);	               --input data
	 
	 i_sof               :	IN  STD_LOGIC;	
	 i_t_err             :	IN  STD_LOGIC;
	 i_eof               :	IN  STD_LOGIC;
	 
	 ov_five_tuple       : OUT STD_LOGIC_VECTOR (104-1 DOWNTO 0);
	 
	 o_valid             : OUT STD_LOGIC;
	 ov_data             :	OUT STD_LOGIC_VECTOR (64-1 DOWNTO 0);
	 
	 o_t_err             : OUT STD_LOGIC;
	 
	 o_sof		             :	OUT STD_LOGIC;		                                     --output start of frame
	 o_ihl_err           :	OUT STD_LOGIC;					                                  --output internet header length error	 	 
	 o_ip_err            :	OUT STD_LOGIC; 					                                 --output ip protocol error	 
	 o_eof		             :	OUT STD_LOGIC                                        --output end of frame
	 	
  );
END COMPONENT;
    
end;
 
package body component_package is
    

end package body;