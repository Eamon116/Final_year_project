-- tuple_extract_top_level.vhd
--
-- extracts the 5 tuple and outputs it with the ip packet
--	
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use IEEE.numeric_bit.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;
use work.component_package.all;

-------------------------------------------------------------------------------

ENTITY tuple_extract_top_level IS
 
  PORT(

	 
	 i_clk		             : IN  STD_LOGIC;
	 i_rst		             :	IN  STD_LOGIC;
  
   	i_valid  		         :	IN  STD_LOGIC;				                          	        --input data valid
	 iv_cntrl	 	         :	IN  STD_LOGIC_VECTOR (4-1  DOWNTO 0);	               --input xgmii control   	
	 iv_data		           :	IN  STD_LOGIC_VECTOR (32-1 DOWNTO 0);	               --input data
	 
	 iv_vlan_defned_tag  : IN  STD_LOGIC_VECTOR (16-1 DOWNTO 0);                --input defined vlan tag which can be set in a cpu register
	 	
	 ov_five_tuple       : OUT STD_LOGIC_VECTOR (104-1 DOWNTO 0);               -- output 5 tuple
	 
	 o_valid		           :	OUT STD_LOGIC;					                                  --output data valid
	 ov_data		           :	OUT STD_LOGIC_VECTOR (64-1 DOWNTO 0);                --output data
	
	 o_sof		             :	OUT STD_LOGIC;		                                     --output start of frame	 
	 o_eof		             :	OUT STD_LOGIC;                                       --output end of frame
	 
	 ov_status_reg       : OUT STD_LOGIC_VECTOR (5-1 DOWNTO 0)                  --output status register, used to signal errors to the next module
	 	

  );
END tuple_extract_top_level;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF tuple_extract_top_level IS
 

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- xgmii to ether-type fsm -- signals
SIGNAL s_fr_valid              : STD_LOGIC;
SIGNAL sv_fr_data              : STD_LOGIC_VECTOR(64-1 DOWNTO 0);

SIGNAL sv_sof		                : STD_LOGIC_VECTOR(2-1 DOWNTO 0);
SIGNAL s_eof		                 : STD_LOGIC;
SIGNAL s_t_err                 : STD_LOGIC;

SIGNAL s_tuple_t_err           : STD_LOGIC;

SIGNAL s_tuple_sof		           : STD_LOGIC;
SIGNAL s_fr_err		              : STD_LOGIC;
SIGNAL s_mpls_err		            : STD_LOGIC;
SIGNAL s_tuple_eof		           : STD_LOGIC;

SIGNAL s_tuple_valid           : STD_LOGIC;
SIGNAL sv_tuple_data           : STD_LOGIC_VECTOR(64-1 DOWNTO 0);

-- signal_delay_reg -- signals
SIGNAL s_tuple_sof_1q		        : STD_LOGIC;
SIGNAL s_tuple_t_err_1q	       : STD_LOGIC;
SIGNAL s_tuple_eof_1q			       : STD_LOGIC;

SIGNAL sv_five_tuple           : STD_LOGIC_VECTOR(104-1 DOWNTO 0); 

SIGNAL s_pkt_t_err             : STD_LOGIC; 

SIGNAL s_pkt_sof		             : STD_LOGIC;
SIGNAL s_ihl_err		             : STD_LOGIC;
SIGNAL s_ip_err		              : STD_LOGIC;
SIGNAL s_pkt_eof		             : STD_LOGIC;

SIGNAL s_pkt_valid             : STD_LOGIC;
SIGNAL sv_pkt_data             : STD_LOGIC_VECTOR(64-1 DOWNTO 0);

-- signal_delay_2_reg -- signals
SIGNAL sv_status_reg           : STD_LOGIC_VECTOR(5-1 DOWNTO 0); 
SIGNAL sv_five_tuple_out       : STD_LOGIC_VECTOR(104-1 DOWNTO 0); 
SIGNAL s_pkt_sof_out		         : STD_LOGIC;
SIGNAL s_pkt_eof_out	          : STD_LOGIC;


-------------------------------------------------------------------------------

BEGIN	-- rtl

-------------------------------------------------------------------------------
xgmii_decoder_inst : xgmii_decoder
 
  PORT MAP(

	 i_clk		             => i_clk,
	 i_rst		             => i_rst,
  
   	i_valid  		         => i_valid,
	 iv_cntrl	 	         => iv_cntrl,
	 iv_data		           => iv_data,
	 	
	 o_valid		           => s_fr_valid, 
	 ov_data		           => sv_fr_data,
	 
	 ov_sof		            => sv_sof,
	 o_err		             => s_t_err,
	 o_eof		             => s_eof
	 	
  );

ether_decode_inst : ether_decode   
  PORT MAP(

	 i_clk		             => i_clk,
	 i_rst		             => i_rst,
  
   	i_valid  		         => s_fr_valid,
	 iv_data		           => sv_fr_data,
	 
	 iv_sof		            => sv_sof,
   	i_err  		           => s_t_err,
	 i_eof		             => s_eof,
	 
	 iv_vlan_defned_tag  => iv_vlan_defned_tag, 
	
	 o_valid             => s_tuple_valid,
	 ov_data             => sv_tuple_data,
	 
	 o_t_err             => s_tuple_t_err,

	 o_sof        		     => s_tuple_sof,
	 o_fr_err            => s_fr_err,
	 o_mpls_err          => s_mpls_err,
	 o_eof        		     => s_tuple_eof
	
  );


-------------------------------------------------------------------------------
-- register sof,eof and tuple frame error so match up with barrel output


tuple_extract_inst : tuple_extract 
 
  PORT MAP(

	 i_clk		             => i_clk,
	 i_rst		             => i_rst,
  
   	i_valid  		         => s_tuple_valid,
	 iv_data		           => sv_tuple_data,
	 
	 i_sof               => s_tuple_sof,
	 i_t_err             => s_tuple_t_err,
	 i_eof               => s_tuple_eof,
	 
	 ov_five_tuple       => sv_five_tuple,
	 
	 o_valid             => s_pkt_valid,
	 ov_data             => sv_pkt_data,
	 
	 o_t_err             => s_pkt_t_err,
	 
	 o_sof		             => s_pkt_sof, 
	 o_ihl_err           => s_ihl_err,
	 o_ip_err            => s_ip_err, 
	 o_eof		             => s_pkt_eof
	 	
  );
  
-------------------------------------------------------------------------------
-- register sof,eof and tuple frame error so match up with barrel output
-------------------------------------------------------------------------------
signal_delay_2_reg: PROCESS(i_clk, i_rst)

BEGIN

  IF (i_rst      = '1') THEN
    
    
    sv_status_reg             <= (OTHERS => '0');

  ELSIF (i_clk'event and i_clk = '1') THEN
    
    sv_status_reg             <= s_pkt_t_err & s_fr_err & s_mpls_err & s_ihl_err & s_ip_err;

  END IF;
END PROCESS signal_delay_2_reg;


ov_five_tuple       <= sv_five_tuple;
	 
o_valid		           <= s_pkt_valid;
ov_data		           <= sv_pkt_data;
	
o_sof		             <= s_pkt_sof;
o_eof		             <= s_pkt_eof;

ov_status_reg       <= sv_status_reg;
	   
END ARCHITECTURE rtl;

------------------------------------------- 