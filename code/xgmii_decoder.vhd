------------------------------------------------------------------------------- 
--
--  xgmii_decoder.vhd
--
-- converts a double data rate to a single data rate on the same clock
--	
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use work.component_package.all;

-------------------------------------------------------------------------------

ENTITY xgmii_decoder IS
 
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
END xgmii_decoder;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF xgmii_decoder IS
 

-------------------------------------------------------------------------------



-------------------------------------------------------------------------------
TYPE XGMII_SM_TYPE        IS  (INIT, IN_FRAME, END_FRAME);
TYPE FCS_REMOVAL_SM_TYPE  IS  (INIT_EOF, SECOND_EOF, REMOVEL);

-- ddr_to_sdr_reg -- signals
SIGNAL s_valid_in              : STD_LOGIC;
SIGNAL sv_data_in	             : STD_LOGIC_VECTOR (64-1 DOWNTO 0);	               -- double input data
SIGNAL sv_cntrl_in             : STD_LOGIC_VECTOR (8-1  DOWNTO 0);	               -- double input xgmii control   	

SIGNAL sv_xgmii_statemachine   : XGMII_SM_TYPE;

SIGNAL s_valid_out             : STD_LOGIC;
SIGNAL sv_data_out             : STD_LOGIC_VECTOR (64-1 DOWNTO 0);	               -- output data
SIGNAL sv_cntrl_out            : STD_LOGIC_VECTOR (8-1  DOWNTO 0);	               -- xgmii control used to remove FCS

SIGNAL sv_sof                  : STD_LOGIC_VECTOR (2-1  DOWNTO 0);
SIGNAL s_err                   : STD_LOGIC;
SIGNAL s_eof                   : STD_LOGIC;

-- delay_sigals_reg -- signals
SIGNAL s_valid_1q              : STD_LOGIC;
SIGNAL sv_data_1q              : STD_LOGIC_VECTOR (64-1 DOWNTO 0);	               -- output data
SIGNAL sv_cntrl_1q             : STD_LOGIC_VECTOR (8-1  DOWNTO 0);	               -- xgmii control used to remove FCS

SIGNAL sv_sof_1q               : STD_LOGIC_VECTOR (2-1  DOWNTO 0);
SIGNAL s_err_1q                : STD_LOGIC;
SIGNAL s_eof_1q                : STD_LOGIC;

-- fcs_removal_regg -- signals
SIGNAL sv_fcs_removal_sm       : FCS_REMOVAL_SM_TYPE;

SIGNAL s_valid_2q              : STD_LOGIC;
SIGNAL sv_data_2q              : STD_LOGIC_VECTOR (64-1 DOWNTO 0);	               -- output data

SIGNAL sv_sof_2q               : STD_LOGIC_VECTOR (2-1  DOWNTO 0);
SIGNAL s_err_2q                : STD_LOGIC;
SIGNAL s_eof_2q                : STD_LOGIC;

-------------------------------------------------------------------------------

BEGIN	-- rtl

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
ddr_to_sdr_data_inst : ddr_to_sdr
GENERIC MAP(

    DATA_WIDTH_IN       => 32
    )  
  PORT MAP(

	 i_clk		             => i_clk,
	 i_rst		             => i_rst,
  
   	i_valid  		         => i_valid,
	 iv_data		           => iv_data,
	 	
	 o_valid		           => s_valid_in,
	 ov_data		           => sv_data_in
	
  );
  
  ddr_to_sdr_control_inst : ddr_to_sdr
GENERIC MAP(

    DATA_WIDTH_IN       => 4
    )  
  PORT MAP(

	 i_clk		             => i_clk,
	 i_rst		             => i_rst,
  
   	i_valid  		         => i_valid,
	 iv_data		           => iv_cntrl,
	 	
	 o_valid		           => OPEN,
	 ov_data		           => sv_cntrl_in 
	
  );
-------------------------------------------------------------------------------
-- 
-------------------------------------------------------------------------------
xgmii_decode_reg: PROCESS(i_clk,i_rst)

BEGIN

  IF i_rst = '1' THEN
    
    sv_sof                       <= "00";
    s_eof                        <= '0';
    s_err                        <= '0';
    s_valid_out                  <= '0';
    sv_cntrl_out                 <= (OTHERS => '0');         
    sv_data_out                  <= (OTHERS => '0');         
    sv_xgmii_statemachine        <= INIT;

         
  ELSIF (i_clk'event and i_clk = '1') THEN
  

  CASE sv_xgmii_statemachine IS 
  
    WHEN INIT =>
      
      s_err                            <= '0';
      s_valid_out                      <= '0';
      sv_data_out                      <= (OTHERS => '0'); 
      
    IF    ( s_valid_in                  = '1') THEN 
      
      IF    (sv_cntrl_in(0)             = '1') THEN
       
        IF    (sv_data_in(7 DOWNTO 0)   = x"FE")THEN -- error in position 0
          
          s_err                        <= '1';
       
        ELSIF (sv_data_in(7 DOWNTO 0)   = x"FB")THEN -- start of frame in position 0
        
          sv_sof                       <= "01";
        
          s_valid_out                  <= s_valid_in;
          sv_data_out                  <= sv_data_in;
          sv_xgmii_statemachine        <= IN_FRAME;
          
        END IF; 
      END IF; 
      
      IF    (sv_cntrl_in(1)             = '1') THEN 
    

        IF    (sv_data_in(15 DOWNTO 8) = x"FE")THEN -- error in position 1
          
          s_err                        <= '1';

        END IF; 
      END IF; 
      
      IF    (sv_cntrl_in(2)             = '1') THEN 
    

        IF    (sv_data_in(23 DOWNTO 16) = x"FE")THEN -- error in position 2
          
          s_err                        <= '1';
          
        END IF; 
      END IF; 
      
      IF    (sv_cntrl_in(3)             = '1') THEN 
    

        IF    (sv_data_in(31 DOWNTO 24) = x"FE")THEN -- error in position 3
          
          s_err                        <= '1';
          
        END IF; 
      END IF; 
              
      IF    (sv_cntrl_in(4)             = '1') THEN
    

        IF    (sv_data_in(39 DOWNTO 32) = x"FE")THEN -- error in position 4
          
          s_err                        <= '1';
       
        ELSIF (sv_data_in(39 DOWNTO 32) = x"FB")THEN -- start of frame in position 4
        
          sv_sof                       <= "10";
        
          s_valid_out                  <= s_valid_in;
          sv_data_out                  <= sv_data_in;
          sv_xgmii_statemachine        <= IN_FRAME;
          
        END IF; 
      END IF; 
              
      IF    (sv_cntrl_in(5)             = '1') THEN -- start of frame in position 5
    

        IF    (sv_data_in(47 DOWNTO 40) = x"FE")THEN -- error in position 0
          
          s_err                        <= '1';

        END IF; 
      END IF; 
            
      IF    (sv_cntrl_in(6)             = '1') THEN -- start of frame in position 6
    

        IF    (sv_data_in(55 DOWNTO 48) = x"FE")THEN -- error in position 0
          
          s_err                        <= '1';

        END IF; 
      END IF; 
            
      IF    (sv_cntrl_in(7)             = '1') THEN -- start of frame in position 7
    

        IF    (sv_data_in(63 DOWNTO 56) = x"FE")THEN -- error in position 0
          
          s_err                        <= '1';

        END IF; 

      END IF;      
    END IF;


    WHEN IN_FRAME =>

      s_valid_out                      <= s_valid_in;  
      sv_cntrl_out                     <= sv_cntrl_in; 
         
      IF    (s_err                      = '1') THEN
          
        sv_xgmii_statemachine          <= END_FRAME;
      ELSE 
      -------------------------------------------------------------------------------
      -- control bit 0      
      -------------------------------------------------------------------------------
      IF    (sv_cntrl_in(0)             = '1')  THEN 
        
        IF    (sv_data_in(7 DOWNTO 0)   = x"FE")THEN -- error in position 0
          
          sv_sof                       <= "00";
          s_err                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
        
        ELSIF (sv_data_in(7 DOWNTO 0)   = x"FD")THEN -- end of frame in position 0
          
          s_eof                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
          sv_data_out                  <= sv_data_in(63 DOWNTO 8) & x"00"; 
                
        END IF;
      ELSE 
        
        sv_data_out                    <= sv_data_in;                
        
      END IF;
      -------------------------------------------------------------------------------
      -- control bit 1      
      -------------------------------------------------------------------------------       
      IF    (sv_cntrl_in(1)             = '1')  THEN 
        
        IF    (sv_data_in(15 DOWNTO 8)  = x"FE")THEN -- error in position 1

          sv_sof                       <= "00";
          s_err                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
                    
        ELSIF (sv_data_in(15 DOWNTO 8)  = x"FD")THEN -- end of frame in position 1
          
          s_eof                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
          sv_data_out                  <= sv_data_in(63 DOWNTO 16) & x"00" & sv_data_in(7 DOWNTO 0); 
                    
        END IF;
      ELSE 
        
        sv_data_out                    <= sv_data_in;                
        
      END IF;       
      -------------------------------------------------------------------------------
      -- control bit 2      
      -------------------------------------------------------------------------------  
      IF    (sv_cntrl_in(2)             = '1')  THEN 
        
        IF    (sv_data_in(23 DOWNTO 16) = x"FE")THEN -- error in position 2

          sv_sof                       <= "00";
          s_err                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
        
        ELSIF (sv_data_in(23 DOWNTO 16) = x"FD")THEN -- end of frame in position 2
          
          s_eof                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
          sv_data_out                  <= sv_data_in(63 DOWNTO 24) & x"00" & sv_data_in(15 DOWNTO 0); 
                               
        END IF;        
      ELSE 
        
        sv_data_out                    <= sv_data_in;                
        
      END IF;
      -------------------------------------------------------------------------------
      -- control bit 3      
      -------------------------------------------------------------------------------
      IF    (sv_cntrl_in(3)             = '1')  THEN 
        
        IF    (sv_data_in(31 DOWNTO 24) = x"FE")THEN -- error in position 3

          sv_sof                       <= "00";
          s_err                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
        
        ELSIF (sv_data_in(31 DOWNTO 24) = x"FD")THEN -- end of frame in position 3
          
          s_eof                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
          sv_data_out                  <= sv_data_in(63 DOWNTO 32) & x"00" & sv_data_in(23 DOWNTO 0);               
                  
        END IF;
      END IF;        
      -------------------------------------------------------------------------------
      -- control bit 4      
      -------------------------------------------------------------------------------
      IF    (sv_cntrl_in(4)             = '1')  THEN 
        
        IF    (sv_data_in(39 DOWNTO 32) = x"FE")THEN -- error in position 4

          sv_sof                       <= "00";
          s_err                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
       
        ELSIF (sv_data_in(39 DOWNTO 32) = x"FD")THEN -- end of frame in position 4
          
          s_eof                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
          sv_data_out                  <= sv_data_in(63 DOWNTO 40) & x"00" & sv_data_in(31 DOWNTO 0); 
                                 
        END IF;  
      ELSE 
        
        sv_data_out                    <= sv_data_in;                
        
      END IF;        
      -------------------------------------------------------------------------------
      -- control bit 5      
      -------------------------------------------------------------------------------
      IF    (sv_cntrl_in(5)             = '1')  THEN 
        
        IF    (sv_data_in(47 DOWNTO 40) = x"FE")THEN -- error in position 5

          sv_sof                       <= "00";
          s_err                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
       
        ELSIF (sv_data_in(47 DOWNTO 40) = x"FD")THEN -- end of frame in position 5
          
          s_eof                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
          sv_data_out                  <= sv_data_in(63 DOWNTO 48) & x"00" & sv_data_in(39 DOWNTO 0); 
                              
        END IF;         
      ELSE 
        
        sv_data_out                    <= sv_data_in;                
        
      END IF;        
      -------------------------------------------------------------------------------
      -- control bit 6      
      -------------------------------------------------------------------------------
      IF    (sv_cntrl_in(6)             = '1')  THEN 
        
        IF    (sv_data_in(55 DOWNTO 48) = x"FE")THEN -- error in position 6

          sv_sof                       <= "00";
          s_err                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
       
        ELSIF (sv_data_in(55 DOWNTO 48) = x"FD")THEN -- end of frame in position 6
          
          s_eof                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
          sv_data_out                  <= sv_data_in(63 DOWNTO 56) & x"00" & sv_data_in(47 DOWNTO 0);        
            
        END IF;          
      ELSE 
        
        sv_data_out                    <= sv_data_in;                
        
      END IF;
      -------------------------------------------------------------------------------
      -- control bit 7      
      -------------------------------------------------------------------------------
      IF    (sv_cntrl_in(7)             = '1')  THEN 
        
        IF    (sv_data_in(63 DOWNTO 56) = x"FE")THEN -- error in position 7

          sv_sof                       <= "00";
          s_err                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
        
        ELSIF (sv_data_in(63 DOWNTO 56) = x"FD")THEN -- end of frame in position 7
          
          s_eof                        <= '1';
          sv_xgmii_statemachine        <= END_FRAME;
          sv_data_out                  <= x"00" & sv_data_in(55 DOWNTO 0);     
                          
        END IF;
      ELSE 
        
        sv_data_out                    <= sv_data_in;                
        
      END IF;
    END IF;      
    WHEN END_FRAME =>
      
      sv_sof                       <= "00";
      s_eof                        <= '0';
      s_err                        <= '0';
      s_valid_out                  <= '0';
      sv_cntrl_out                 <= (OTHERS => '0');               
      sv_data_out                  <= (OTHERS => '0');      
      sv_xgmii_statemachine        <= INIT;
      
    WHEN OTHERS =>
      
      sv_sof                       <= "00";
      s_eof                        <= '0';
      s_err                        <= '0';
      s_valid_out                  <= '0';
      sv_cntrl_out                 <= (OTHERS => '0');
      sv_data_out                  <= (OTHERS => '0');             
      sv_xgmii_statemachine        <= INIT;
      
  END CASE;

  END IF;

END PROCESS xgmii_decode_reg;


-------------------------------------------------------------------------------
-- 
-------------------------------------------------------------------------------
delay_sigals_reg: PROCESS(i_clk,i_rst)

BEGIN

  IF i_rst = '1' THEN
    
    s_valid_1q                   <= '0';              
    sv_data_1q                   <= (OTHERS => '0');              
    sv_cntrl_1q                  <= (OTHERS => '0');             

    sv_sof_1q                    <= (OTHERS => '0');               
    s_err_1q                     <= '0';                
    s_eof_1q                     <= '0';

  ELSIF (i_clk'event and i_clk = '1') THEN
    
    IF    (s_valid_out           <= '1') THEN
        
      s_valid_1q                 <= s_valid_out;              
      sv_data_1q                 <= sv_data_out;              
      sv_cntrl_1q                <= sv_cntrl_out;             

      sv_sof_1q                  <= sv_sof;               
      s_err_1q                   <= s_err;                
      s_eof_1q                   <= s_eof;
    END IF;
  END IF;

END PROCESS delay_sigals_reg;

-------------------------------------------------------------------------------
-- 
-------------------------------------------------------------------------------
fcs_removal_reg: PROCESS(i_clk,i_rst)

BEGIN

  IF i_rst = '1' THEN
    
    s_valid_2q                 <= '0';              
    sv_data_2q                 <= (OTHERS => '0');              

    sv_sof_2q                  <= (OTHERS => '0');               
    s_err_2q                   <= '0';
    s_eof_2q                   <= '0';
    
    sv_fcs_removal_sm          <= INIT_EOF;
    
  ELSIF (i_clk'event and i_clk  = '1') THEN 
   
  CASE sv_fcs_removal_sm IS 
  
    WHEN INIT_EOF =>
    
    IF    (s_err                = '1') THEN
             
        
        s_valid_2q             <= s_valid_1q;
        sv_data_2q             <= sv_data_1q;
          
        sv_sof_2q              <= sv_sof_1q;
        s_err_2q               <= s_err_1q;
        s_eof_2q               <= '0';   
        
        sv_fcs_removal_sm      <= INIT_EOF; 
   
    ELSE
      IF    (s_eof              = '1') THEN
      
        IF    (sv_cntrl_out(7)  = '1') THEN 
        
          s_valid_2q           <= s_valid_1q;
          sv_data_2q           <= sv_data_1q(63 DOWNTO 32) & x"00000000";
          
          sv_sof_2q            <= sv_sof_1q;
          s_err_2q             <= s_err_1q;
          s_eof_2q             <= '1';
          
          sv_fcs_removal_sm    <= REMOVEL; 
        
        ELSIF (sv_cntrl_out(6)  = '1') THEN 
        
          s_valid_2q           <= s_valid_1q;
          sv_data_2q           <= sv_data_1q(63 DOWNTO 24) & x"000000";
          
          sv_sof_2q            <= sv_sof_1q;
          s_err_2q             <= s_err_1q;
          s_eof_2q             <= '1';
          
          sv_fcs_removal_sm    <= REMOVEL;  
 
        ELSIF (sv_cntrl_out(5)  = '1') THEN 
          
          s_valid_2q           <= s_valid_1q;
          sv_data_2q           <= sv_data_1q(63 DOWNTO 16) & x"0000";
          
          sv_sof_2q            <= sv_sof_1q;
          s_err_2q             <= s_err_1q;
          s_eof_2q             <= '1';
          
          sv_fcs_removal_sm    <= REMOVEL; 
        
        ELSIF (sv_cntrl_out(4)  = '1') THEN 
        
          s_valid_2q           <= s_valid_1q;
          sv_data_2q           <= sv_data_1q(63 DOWNTO 8) & x"00";
          
          sv_sof_2q            <= sv_sof_1q;
          s_err_2q             <= s_err_1q;
          s_eof_2q             <= '1';
        
          sv_fcs_removal_sm    <= REMOVEL; 
      
        ELSIF (sv_cntrl_out(3)  = '1') THEN 
        
          s_valid_2q           <= s_valid_1q;
          sv_data_2q           <= sv_data_1q;
          
          sv_sof_2q            <= sv_sof_1q;
          s_err_2q             <= s_err_1q;
          s_eof_2q             <= '1';
          sv_fcs_removal_sm    <= SECOND_EOF;
        
        ELSE
      
          s_valid_2q           <= s_valid_1q;
          sv_data_2q           <= sv_data_1q;
          
          sv_sof_2q            <= sv_sof_1q;
          s_err_2q             <= s_err_1q;
          s_eof_2q             <= s_eof_1q;
          sv_fcs_removal_sm    <= SECOND_EOF; 
         
        END IF;
      ELSE
      
        s_valid_2q             <= s_valid_1q;
        sv_data_2q             <= sv_data_1q;
          
        sv_sof_2q              <= sv_sof_1q;
        s_err_2q               <= s_err_1q;
        s_eof_2q               <= s_eof_1q;
        sv_fcs_removal_sm      <= INIT_EOF;  
           
      END IF;
    END IF;        
    WHEN SECOND_EOF =>
    
      s_valid_2q               <= s_valid_1q;
      sv_data_2q               <= sv_data_1q;
          
      sv_sof_2q                <= sv_sof_1q;
      s_err_2q                 <= s_err_1q;
      s_eof_2q                 <= s_eof_1q;
    
    
    IF    (s_eof_1q             = '1') THEN
       
      IF    (sv_cntrl_1q(3)     = '1') THEN 
        
        s_valid_2q               <= '0';
        sv_data_2q               <= (OTHERS => '0');
          
        sv_sof_2q                <= (OTHERS => '0');
        s_err_2q                 <= s_err_1q;
        s_eof_2q                 <= '0';
        
        sv_fcs_removal_sm      <= REMOVEL; 

      ELSIF (sv_cntrl_1q(2)     = '1') THEN 
          
        s_valid_2q             <= s_valid_1q;
        sv_data_2q             <= sv_data_1q(63 DOWNTO 56) & x"00000000000000";
          
        sv_sof_2q              <= sv_sof_1q;
        s_err_2q               <= s_err_1q;
        s_eof_2q               <= s_eof_1q;  
        sv_fcs_removal_sm      <= REMOVEL;  
 
      ELSIF (sv_cntrl_1q(1)     = '1') THEN 
          
        s_valid_2q             <= s_valid_1q;
        sv_data_2q             <= sv_data_1q(63 DOWNTO 48) & x"000000000000";
          
        sv_sof_2q              <= sv_sof_1q;
        s_err_2q               <= s_err_1q;
        s_eof_2q               <= s_eof_1q; 
        sv_fcs_removal_sm      <= REMOVEL; 
        
      ELSIF (sv_cntrl_1q(0)     = '1') THEN 
          
        s_valid_2q             <= s_valid_1q;
        sv_data_2q             <= sv_data_1q(63 DOWNTO 40) & x"0000000000";
          
        sv_sof_2q              <= sv_sof_1q;
        s_err_2q               <= s_err_1q;
        s_eof_2q               <= s_eof_1q; 
        sv_fcs_removal_sm      <= REMOVEL;
      ELSE
      
        s_valid_2q             <= s_valid_1q;
        sv_data_2q             <= sv_data_1q;
          
        sv_sof_2q              <= sv_sof_1q;
        s_err_2q               <= s_err_1q;
        s_eof_2q               <= s_eof_1q;
        sv_fcs_removal_sm      <= INIT_EOF;  
      END IF;
    ELSE
      s_valid_2q               <= s_valid_1q;
      sv_data_2q               <= sv_data_1q;
          
      sv_sof_2q                <= sv_sof_1q;
      s_err_2q                 <= s_err_1q;
      s_eof_2q                 <= s_eof_1q;
      sv_fcs_removal_sm        <= INIT_EOF;      
    END IF;
          
    WHEN REMOVEL =>
    
      s_valid_2q               <= '0';              
      sv_data_2q               <= (OTHERS => '0');              

      sv_sof_2q                <= (OTHERS => '0');               
      s_err_2q                 <= s_err_1q;
      s_eof_2q                 <= '0';
      
      sv_fcs_removal_sm        <= INIT_EOF;
    
    WHEN OTHERS =>
    
      s_valid_2q               <= '0';              
      sv_data_2q               <= (OTHERS => '0');              

      sv_sof_2q                <= (OTHERS => '0');               
      s_err_2q                 <= '0';
      s_eof_2q                 <= '0';
    
      sv_fcs_removal_sm        <= INIT_EOF;
        
    END CASE;
  
  END IF;    

END PROCESS fcs_removal_reg;



o_valid <= s_valid_2q;
ov_data <= sv_data_2q;

ov_sof  <= sv_sof_2q;
o_err   <= s_err_2q;
o_eof   <= s_eof_2q AND NOT(s_err_2q);

  

END ARCHITECTURE rtl;

--------------------------------------------------