-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use IEEE.numeric_bit.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

-------------------------------------------------------------------------------

ENTITY ether_decode IS  
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
END ether_decode;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF ether_decode IS
 

-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
TYPE DECODE_STATE_TYPE IS (INIT, FIRST_DECODE, VLAN, SECOND_DECODE, MPLS, OUTPUT, END_STATE);

-------------------------------------------------------------------------------

-- input_store_reg -- MTU is 1526 bytes for a simple IP packet including preammble and SFD
--                 -- with PBB VLAN and max MPLS MTU is 1578 bytes
SIGNAL sv_store_count          : STD_LOGIC_VECTOR(6-1 DOWNTO 0);
SIGNAL sv_frame_capture        : STD_LOGIC_VECTOR(64*198-1 DOWNTO 0); -- 1578 * 8 

SIGNAL s_valid                 : STD_LOGIC;
SIGNAL sv_sof                  : STD_LOGIC_VECTOR(2-1 DOWNTO 0);
SIGNAL s_t_err                 : STD_LOGIC;
SIGNAL s_eof                   : STD_LOGIC;

-- ethertype_decode_reg -- 
SIGNAL s_t_err_1q              : STD_LOGIC;
SIGNAL s_mpls_flag             : STD_LOGIC;
SIGNAL s_q_vlan_flag           : STD_LOGIC;
SIGNAL s_vlan_defined_flag     : STD_LOGIC;
SIGNAL s_q_in_q_flag           : STD_LOGIC;
SIGNAL s_mac_in_mac_flag       : STD_LOGIC;

SIGNAL sv_byte_num             : STD_LOGIC_VECTOR(12-1 DOWNTO 0);
SIGNAL s_read_enable           : STD_LOGIC;

SIGNAL s_sof_out               : STD_LOGIC;

SIGNAL s_frame_error           : STD_LOGIC;
SIGNAL s_mpls_error            : STD_LOGIC;
SIGNAL s_clear                 : STD_LOGIC;
SIGNAL s_eof_out               : STD_LOGIC;
SIGNAL sv_state_machine								: DECODE_STATE_TYPE;  

-- output_data_reg
SIGNAL s_sof_out_1q            : STD_LOGIC;
SIGNAL s_eof_out_1q            : STD_LOGIC;
SIGNAL s_t_err_2q              : STD_LOGIC;

SIGNAL s_valid_out             : STD_LOGIC;
SIGNAL sv_data_out             : STD_LOGIC_VECTOR(64-1 DOWNTO 0);

-------------------------------------------------------------------------------

BEGIN	-- rtl

-------------------------------------------------------------------------------

s_mpls_flag <= NOT(s_q_vlan_flag OR s_vlan_defined_flag OR s_q_in_q_flag OR s_mac_in_mac_flag);


-------------------------------------------------------------------------------
-- capture the input data into the barrel
-------------------------------------------------------------------------------
input_store_reg: PROCESS(i_clk, i_rst)

BEGIN

  IF (i_rst                    = '1') THEN
    
    s_valid                   <= '0';
    sv_sof                    <= (OTHERS => '0');  
    s_t_err                   <= '0';
    s_eof                     <= '0';
    sv_store_count            <= (OTHERS => '0');  
    sv_frame_capture          <= (OTHERS => '0');        
    
  ELSIF (i_clk'event and i_clk = '1') THEN
    
    s_valid                                <= i_valid;
    sv_sof                                 <= iv_sof;
    s_t_err                                <= i_err;
    s_eof                                  <= i_eof;
        
    IF    (s_clear           = '1') THEN
        
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
-- ethertype decode state machine
-------------------------------------------------------------------------------
ethertype_decode_reg: PROCESS(i_clk, i_rst)

BEGIN

  IF (i_rst                    = '1') THEN
      
      s_t_err_1q                          <= '0';      
      s_q_vlan_flag                       <= '0';
      s_vlan_defined_flag                 <= '0';
      s_q_in_q_flag                       <= '0';    
      s_mac_in_mac_flag                   <= '0';
      s_sof_out                           <= '0';
      sv_byte_num                         <= (OTHERS => '0');
      s_read_enable                       <= '0';

      s_frame_error                       <= '0';
      s_mpls_error                        <= '0';
      s_clear                             <= '0';
      s_eof_out                           <= '0';
      sv_state_machine                    <= INIT;    
    
  ELSIF (i_clk'event and i_clk = '1') THEN
  
    s_t_err_1q                                        <= s_t_err;
 
    CASE sv_state_machine IS 
    
    WHEN INIT                                          => 
    
      s_clear                                         <= '0';

    
    IF    (s_t_err                                     = '1') THEN
      
      s_clear                                         <= '1';
      sv_state_machine                                <= END_STATE;
    ELSE    
      ---------------------------------------------------------------------------------------------------------
      --  pass to FIRST_DECODE if the start or frame is detected and increment the count
      ---------------------------------------------------------------------------------------------------------
      IF    (s_valid                                   = '1') THEN 
                
        IF   ((sv_sof                                  = "01")  OR
              (sv_sof                                  = "10")) THEN       
        
          sv_state_machine                            <= FIRST_DECODE; 
            
        END IF;
      END IF;
    END IF; 
   

    WHEN FIRST_DECODE                                  => 
    IF    (s_t_err                                     = '1') THEN
      
      s_clear                                         <= '1';
      sv_state_machine                                <= END_STATE;
    ELSE  

      IF    (s_valid                                   = '1'  ) THEN 
        
        
        ---------------------------------------------------------------------------------------------------------
        --  decode first ether-type if enough data has been collected
        ---------------------------------------------------------------------------------------------------------
        IF    (CONV_INTEGER(sv_store_count)           >=  3) THEN 
          
          ---------------------------------------------------------------------------------------------------------
          --  decode ether-type field depending on start of frame position
          ---------------------------------------------------------------------------------------------------------
          IF    (sv_sof                                = "01") THEN 
            
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set starting byte and read enable for barrel shifter
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12511 DOWNTO 12496)    = x"0800") THEN
              
              s_sof_out                               <= '1';
              sv_byte_num                             <= CONV_STD_LOGIC_VECTOR(22,12);  
              s_read_enable                           <= '1';              
              sv_state_machine                        <= OUTPUT;
              
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is Q VLAN set starting byte and 
            --  enable Q VLAN flag to indicate to second decode
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12511 DOWNTO 12496)    = x"8100") OR
                  (sv_frame_capture(12511 DOWNTO 12496)    = x"9100") THEN
              
              s_q_vlan_flag                           <= '1';
              sv_byte_num                             <= CONV_STD_LOGIC_VECTOR(26,12);    
              sv_state_machine                        <= SECOND_DECODE;               
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is stacked VLAN then the state machine moves on to the VLAN state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12511 DOWNTO 12496)    = x"88A8") OR
                  (sv_frame_capture(12511 DOWNTO 12496)    = x"9200") THEN
                 
              sv_state_machine                        <= VLAN;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is user defined VLAN set starting byte and 
            --  enable user defined VLAN flag to indicate to second decode
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12511 DOWNTO 12496)    = iv_vlan_defned_tag) OR
                  (sv_frame_capture(12511 DOWNTO 12496)    = x"9300")   THEN
              
              s_vlan_defined_flag                     <= '1';
              sv_byte_num                             <= CONV_STD_LOGIC_VECTOR(34,12);    
              sv_state_machine                        <= SECOND_DECODE;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12511 DOWNTO 12496)    = x"8847") OR 
                  (sv_frame_capture(12511 DOWNTO 12496)    = x"8848") THEN
              
              sv_byte_num                             <= CONV_STD_LOGIC_VECTOR(22,12);   
              sv_state_machine                        <= MPLS;
              
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE;                          
            END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  decode ether-type field depending on start of frame position
          ---------------------------------------------------------------------------------------------------------
          ELSIF (sv_sof                                = "10") THEN 
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set starting byte and read enable for barrel shifter
            --  state machine moves on to the OUTPUT state            
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12543 DOWNTO 12528)   = x"0800") THEN
              
              s_sof_out                               <= '1';
              sv_byte_num                             <= CONV_STD_LOGIC_VECTOR(18,12);  
              s_read_enable                           <= '1';  
              sv_state_machine                        <= OUTPUT;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is Q VLAN set starting byte and 
            --  enable Q VLAN flag to indicate to second decode
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12543 DOWNTO 12528)    = x"8100") OR
                  (sv_frame_capture(12543 DOWNTO 12528)    = x"9100") THEN
              
              s_q_vlan_flag                           <= '1';
              sv_byte_num                             <= CONV_STD_LOGIC_VECTOR(22,12);    
              sv_state_machine                        <= SECOND_DECODE;               
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is stacked VLAN then the state machine moves on to the VLAN state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12543 DOWNTO 12528)    = x"88A8") OR
                  (sv_frame_capture(12543 DOWNTO 12528)    = x"9200") THEN
                 
              sv_state_machine                        <= VLAN;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is user defined VLAN set starting byte and 
            --  enable user defined VLAN flag to indicate to second decode
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12543 DOWNTO 12528)    = iv_vlan_defned_tag) OR
                  (sv_frame_capture(12543 DOWNTO 12528)    = x"9300") THEN
              
              s_vlan_defined_flag                     <= '1';
              sv_byte_num                             <= CONV_STD_LOGIC_VECTOR(30,12);    
              sv_state_machine                        <= SECOND_DECODE;

            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12543 DOWNTO 12528)    = x"8847") OR 
                  (sv_frame_capture(12543 DOWNTO 12528)    = x"8848") THEN
                 
              sv_byte_num                             <= CONV_STD_LOGIC_VECTOR(18,12);
              sv_state_machine                        <= MPLS;
            
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE;                            
            END IF;
          END IF;            
        END IF;
      END IF;    
    END IF;
    
    WHEN VLAN                                          =>
    IF    (s_t_err                                     = '1') THEN
      
      s_clear                                         <= '1';
      sv_state_machine                                <= END_STATE;
    ELSE      
      IF    (s_valid                                   = '1') THEN 
                
        ---------------------------------------------------------------------------------------------------------
        --  decode stack VLAN ether-type field depending on start of frame position
        ---------------------------------------------------------------------------------------------------------
        IF    (sv_sof                                  = "01") THEN 

          ---------------------------------------------------------------------------------------------------------
          --  if the second VLAN tag is 8100 or 9100 set starting byte and 
          --  enable Q in Q VLAN flag to indicate to second decode 
          ---------------------------------------------------------------------------------------------------------
          IF    (sv_frame_capture(12479 DOWNTO 12464)      = x"8100") OR 
                (sv_frame_capture(12479 DOWNTO 12464)      = x"9100") THEN

            s_q_in_q_flag                             <= '1';
            sv_byte_num                               <= CONV_STD_LOGIC_VECTOR(30,12);                 
            sv_state_machine                          <= SECOND_DECODE;                          
          
          ---------------------------------------------------------------------------------------------------------
          --  if the second VLAN tag is 88E7 set starting byte and 
          --  enable MAC in MAC VLAN flag to indicate to second decode 
          ---------------------------------------------------------------------------------------------------------
          ELSIF (sv_frame_capture(12479 DOWNTO 12464)      = x"88E7") THEN
              
            s_mac_in_mac_flag                         <= '1';
            sv_byte_num                               <= CONV_STD_LOGIC_VECTOR(50,12);   
            sv_state_machine                          <= SECOND_DECODE;
          
          ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE;  
          END IF;         
        
        ---------------------------------------------------------------------------------------------------------
        --  decode stack VLAN ether-type field depending on start of frame position
        ---------------------------------------------------------------------------------------------------------
        ELSIF (sv_sof                                  = "10") THEN       
        
          ---------------------------------------------------------------------------------------------------------
          --  if the second VLAN tag is 8100 or 9100 set starting byte and 
          --  enable Q in Q VLAN flag to indicate to second decode 
          ---------------------------------------------------------------------------------------------------------
          IF    (sv_frame_capture(12511 DOWNTO 12496)      = x"8100") OR 
                (sv_frame_capture(12511 DOWNTO 12496)      = x"9100") THEN

            s_q_in_q_flag                             <= '1';
            sv_byte_num                               <= CONV_STD_LOGIC_VECTOR(26,12);                 
            sv_state_machine                          <= SECOND_DECODE;                          
          
          ---------------------------------------------------------------------------------------------------------
          --  if the second VLAN tag is 88E7 set starting byte and 
          --  enable MAC in MAC VLAN flag to indicate to second decode 
          ---------------------------------------------------------------------------------------------------------
          ELSIF (sv_frame_capture(12511 DOWNTO 12496)      = x"88E7") THEN
              
            s_mac_in_mac_flag                         <= '1';
            sv_byte_num                               <= CONV_STD_LOGIC_VECTOR(46,12);   
            sv_state_machine                          <= SECOND_DECODE;
            
          ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE; 
          END IF;
            
        END IF;
      END IF;
    END IF;
    
    WHEN SECOND_DECODE                                 => 
    IF    (s_t_err                                     = '1') THEN
      
      s_clear                                         <= '1';
      sv_state_machine                                <= END_STATE;
    ELSE
      IF    (s_valid                                   = '1') THEN 
                  
        ---------------------------------------------------------------------------------------------------------
        --  decode ether-type field depending on start of frame position
        ---------------------------------------------------------------------------------------------------------
        IF    (sv_sof                                  = "01") THEN 
          
          ---------------------------------------------------------------------------------------------------------
          --  decode if the Q VLAN flag is set and if enough data has been collected
          ---------------------------------------------------------------------------------------------------------
          IF    (s_q_vlan_flag                         = '1') AND
                (CONV_INTEGER(sv_store_count)         >=  4 ) THEN
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12479 DOWNTO 12464)    = x"8847") OR 
                  (sv_frame_capture(12479 DOWNTO 12464)    = x"8848") THEN
                  
              sv_state_machine                        <= MPLS;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set read enable for barrel shifter
            --  state machine moves on to the OUTPUT state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12479 DOWNTO 12464)    = x"0800") THEN
            
              s_sof_out                               <= '1';
              s_read_enable                           <= '1';                
              sv_state_machine                        <= OUTPUT;
            
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE;  
            END IF;               
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  decode if the Q in Q VLAN flag is set and if enough data has been collected
          ---------------------------------------------------------------------------------------------------------
          IF    (s_q_in_q_flag                         = '1') AND
                (CONV_INTEGER(sv_store_count)         >=  4 ) THEN
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12447 DOWNTO 12432)    = x"8847") OR 
                  (sv_frame_capture(12447 DOWNTO 12432)    = x"8848") THEN
                  
              sv_state_machine                        <= MPLS;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set read enable for barrel shifter
            --  state machine moves on to the OUTPUT state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12447 DOWNTO 12432)    = x"0800") THEN
            
              s_sof_out                               <= '1';
              s_read_enable                           <= '1';                
              sv_state_machine                        <= OUTPUT;

            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE; 
            END IF;   
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  decode if the user defined VLAN flag is set and if enough data has been collected
          ---------------------------------------------------------------------------------------------------------
          IF    (s_vlan_defined_flag                   = '1') AND
                (CONV_INTEGER(sv_store_count)         >=  5 ) THEN
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12415 DOWNTO 12400)    = x"8847") OR 
                  (sv_frame_capture(12415 DOWNTO 12400)    = x"8848") THEN
                  
              sv_state_machine                        <= MPLS;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set read enable for barrel shifter
            --  state machine moves on to the OUTPUT state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12415 DOWNTO 12400)    = x"0800") THEN
            
              s_sof_out                               <= '1';
              s_read_enable                           <= '1';                
              sv_state_machine                        <= OUTPUT;
            
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE; 
            END IF;   
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  decode if the MAC in MAC VLAN flag is set and if enough data has been collected
          ---------------------------------------------------------------------------------------------------------
          IF    (s_mac_in_mac_flag                     = '1') AND
                (CONV_INTEGER(sv_store_count)         >=  7 ) THEN
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12287 DOWNTO 12272)    = x"8847") OR 
                  (sv_frame_capture(12287 DOWNTO 12272)    = x"8848") THEN
                  
              sv_state_machine                        <= MPLS;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set read enable for barrel shifter
            --  state machine moves on to the OUTPUT state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12287 DOWNTO 12272)    = x"0800") THEN
            
              s_sof_out                               <= '1';
              s_read_enable                           <= '1';                
              sv_state_machine                        <= OUTPUT;
              
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE;  
            END IF;   
          END IF;          
        
        ---------------------------------------------------------------------------------------------------------
        --  decode ether-type field depending on start of frame position
        ---------------------------------------------------------------------------------------------------------
        ELSIF (sv_sof                                  = "10") THEN       
           
          ---------------------------------------------------------------------------------------------------------
          --  decode if the Q VLAN flag is set and if enough data has been collected
          ---------------------------------------------------------------------------------------------------------
          IF    (s_q_vlan_flag                         = '1') AND
                (CONV_INTEGER(sv_store_count)         >=  3 ) THEN
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12511 DOWNTO 12496)    = x"8847") OR 
                  (sv_frame_capture(12511 DOWNTO 12496)    = x"8848") THEN
                  
              sv_state_machine                        <= MPLS;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set read enable for barrel shifter
            --  state machine moves on to the OUTPUT state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12511 DOWNTO 12496)    = x"0800") THEN
              
              s_sof_out                               <= '1';
              s_read_enable                           <= '1';                
              sv_state_machine                        <= OUTPUT;
              
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE;  
            END IF;   
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  decode if the Q in Q VLAN flag is set and if enough data has been collected
          ---------------------------------------------------------------------------------------------------------
          IF    (s_q_in_q_flag                         = '1') AND
                (CONV_INTEGER(sv_store_count)         >=  4 ) THEN
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12479 DOWNTO 12464)    = x"8847") OR 
                  (sv_frame_capture(12479 DOWNTO 12464)    = x"8848") THEN
                  
              sv_state_machine                        <= MPLS;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set read enable for barrel shifter
            --  state machine moves on to the OUTPUT state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12479 DOWNTO 12464)    = x"0800") THEN
            
              s_sof_out                               <= '1';
              s_read_enable                           <= '1';                
              sv_state_machine                        <= OUTPUT;
            
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE; 
            END IF;   
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  decode if the user defined VLAN flag is set and if enough data has been collected
          ---------------------------------------------------------------------------------------------------------
          IF    (s_vlan_defined_flag                   = '1') AND
                (CONV_INTEGER(sv_store_count)         >=  4 ) THEN
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12447 DOWNTO 12432)    = x"8847") OR 
                  (sv_frame_capture(12447 DOWNTO 12432)    = x"8848") THEN
                  
              sv_state_machine                        <= MPLS;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set read enable for barrel shifter
            --  state machine moves on to the OUTPUT state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12447 DOWNTO 12432)    = x"0800") THEN
            
              s_sof_out                               <= '1';
              s_read_enable                           <= '1';                
              sv_state_machine                        <= OUTPUT;
            
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE;  
            END IF;   
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  decode if the MAC in MAC VLAN flag is set and if enough data has been collected
          ---------------------------------------------------------------------------------------------------------
          IF    (s_mac_in_mac_flag                     = '1') AND
                (CONV_INTEGER(sv_store_count)         >=  6 ) THEN
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is MPLS then the state machine moves on to the MPLS state
            ---------------------------------------------------------------------------------------------------------
            IF    (sv_frame_capture(12319 DOWNTO 12304)    = x"8847") OR 
                  (sv_frame_capture(12319 DOWNTO 12304)    = x"8848") THEN
                  
              sv_state_machine                        <= MPLS;
            
            ---------------------------------------------------------------------------------------------------------
            --  if ether-type is IP set read enable for barrel shifter
            --  state machine moves on to the OUTPUT state
            ---------------------------------------------------------------------------------------------------------
            ELSIF (sv_frame_capture(12319 DOWNTO 12304)    = x"0800") THEN
            
              s_sof_out                               <= '1';
              s_read_enable                           <= '1';                
              sv_state_machine                        <= OUTPUT;
            
            ELSE 
              
              s_frame_error                           <= '1';
              s_clear                                 <= '1';
              sv_state_machine                        <= END_STATE;  
            END IF;   
          END IF;            
        END IF;
      END IF;
    END IF;    
    
    WHEN MPLS                                          =>         
    IF    (s_t_err                                     = '1') THEN
      
      s_clear                                         <= '1';
      sv_state_machine                                <= END_STATE;
    ELSE
      IF    (s_valid                                   = '1' ) THEN 
        
        
        IF    (sv_sof                                  = "01") THEN
          ---------------------------------------------------------------------------------------------------------
          --  if MPLS is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_mpls_flag                           = '1') THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  4 ) THEN  
              IF    (sv_frame_capture(12472)             = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                IF (sv_frame_capture(12440)              = '1') THEN
              
                  s_sof_out                           <= '1';
                  s_read_enable                       <= '1';                
                  sv_byte_num                         <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                  sv_state_machine                    <= OUTPUT;
                  
                ELSE 
                  IF (CONV_INTEGER(sv_store_count)    >=  5 ) THEN
                    IF    (sv_frame_capture(12408)       = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      IF    (sv_frame_capture(12376)     = '1') THEN
              
                        s_sof_out                     <= '1';
                        s_read_enable                 <= '1';                
                        sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                        sv_state_machine              <= OUTPUT;
                      
                      ELSE
                        IF    (CONV_INTEGER(sv_store_count) >=  6 ) THEN
                          IF    (sv_frame_capture(12344)       = '1') THEN
              
                            s_sof_out                       <= '1';
                            s_read_enable                   <= '1';                
                            sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine                <= OUTPUT;
                            
                          ELSE
                            IF    (sv_frame_capture(12312)     = '1') THEN
               
                              s_sof_out                     <= '1';
                              s_read_enable                 <= '1';                
                              sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                              sv_state_machine              <= OUTPUT;
                              
                            ELSE
                            
                              s_mpls_error                  <= '1';
                              s_clear                       <= '1';
                              sv_state_machine              <= END_STATE;  
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF;
                   
          ---------------------------------------------------------------------------------------------------------
          --  if Q VLAN is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_q_vlan_flag                         = '1' ) THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  4 ) THEN  
              IF    (sv_frame_capture(12440)             = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                IF (CONV_INTEGER(sv_store_count)      >=  5 ) THEN
                  IF (sv_frame_capture(12408)            = '1' ) THEN
              
                    s_sof_out                         <= '1';
                    s_read_enable                     <= '1';                
                    sv_byte_num                       <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                    sv_state_machine                  <= OUTPUT;
                  
                  ELSE 
                  
                    IF    (sv_frame_capture(12376)       = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      IF    (CONV_INTEGER(sv_store_count) >=  6 ) THEN
                        IF    (sv_frame_capture(12344)       = '1' ) THEN
              
                          s_sof_out                       <= '1';
                          s_read_enable                   <= '1';                
                          sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                          sv_state_machine                <= OUTPUT;
                      
                      ELSE
                        
                          IF    (sv_frame_capture(12312)     = '1') THEN
              
                            s_sof_out                     <= '1';
                            s_read_enable                 <= '1';                
                            sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine              <= OUTPUT;
                            
                          ELSE
                            IF    (CONV_INTEGER(sv_store_count) >=  7 ) THEN
                              IF    (sv_frame_capture(12280)      = '1' ) THEN
               
                                s_sof_out                       <= '1';
                                s_read_enable                   <= '1';                
                                sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                                sv_state_machine                <= OUTPUT;
                              ELSE
                            
                                s_mpls_error                    <= '1';
                                s_clear                         <= '1';
                                sv_state_machine                <= END_STATE;  
                              END IF;
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF; 
          
          ---------------------------------------------------------------------------------------------------------
          --  if QinQ VLAN is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_q_in_q_flag                         = '1' ) THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  5 ) THEN  
              IF    (sv_frame_capture(12408)            = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                IF (sv_frame_capture(12376)             = '1' ) THEN
              
                  s_sof_out                           <= '1';
                  s_read_enable                       <= '1';                
                  sv_byte_num                         <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                  sv_state_machine                    <= OUTPUT;
                  
                ELSE 
                  IF (CONV_INTEGER(sv_store_count)    >=  6 ) THEN
                    IF    (sv_frame_capture(12344)      = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      IF    (sv_frame_capture(12312)    = '1' ) THEN
              
                        s_sof_out                     <= '1';
                        s_read_enable                 <= '1';                
                        sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                        sv_state_machine              <= OUTPUT;
                      
                      ELSE
                        IF    (CONV_INTEGER(sv_store_count) >=  7 ) THEN
                          IF    (sv_frame_capture(12280)      = '1') THEN
              
                            s_sof_out                       <= '1';
                            s_read_enable                   <= '1';                
                            sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine                <= OUTPUT;
                            
                          ELSE
                            IF    (sv_frame_capture(12248)    = '1' ) THEN
               
                              s_sof_out                     <= '1';
                              s_read_enable                 <= '1';                
                              sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                              sv_state_machine              <= OUTPUT;
                            ELSE
                            
                              s_mpls_error                  <= '1';
                              s_clear                       <= '1';
                              sv_state_machine              <= END_STATE; 
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  if QinQinQ VLAN is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_vlan_defined_flag                   = '1' ) THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  5 ) THEN  
              IF    (sv_frame_capture(12376)            = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                IF (CONV_INTEGER(sv_store_count)      >=  6 ) THEN
                  IF (sv_frame_capture(12344)           = '1' ) THEN
              
                    s_sof_out                         <= '1';
                    s_read_enable                     <= '1';                
                    sv_byte_num                       <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                    sv_state_machine                  <= OUTPUT;
                  
                  ELSE 
                  
                    IF    (sv_frame_capture(12312)      = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      IF    (CONV_INTEGER(sv_store_count) >=  7 ) THEN
                        IF    (sv_frame_capture(12280)      = '1' ) THEN
              
                          s_sof_out                       <= '1';
                          s_read_enable                   <= '1';                
                          sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                          sv_state_machine                <= OUTPUT;
                      
                      ELSE
                        
                          IF    (sv_frame_capture(12248)    = '1') THEN
              
                            s_sof_out                     <= '1';
                            s_read_enable                 <= '1';                
                            sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine              <= OUTPUT;
                            
                          ELSE
                            IF    (CONV_INTEGER(sv_store_count) >=  8 ) THEN
                              IF    (sv_frame_capture(12216)      = '1' ) THEN
               
                                s_sof_out                       <= '1';
                                s_read_enable                   <= '1';                
                                sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                                sv_state_machine                <= OUTPUT;
                              ELSE
                            
                                s_mpls_error                    <= '1';
                                s_clear                         <= '1';
                                sv_state_machine                <= END_STATE; 
                              END IF;
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  if MACinMAC VLAN is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_mac_in_mac_flag                     = '1' ) THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  7 ) THEN  
              IF    (sv_frame_capture(12248)            = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                IF (CONV_INTEGER(sv_store_count)      >=  8 ) THEN
                  IF (sv_frame_capture(12216)           = '1' ) THEN
              
                    s_sof_out                         <= '1';
                    s_read_enable                     <= '1';                
                    sv_byte_num                       <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                    sv_state_machine                  <= OUTPUT;
                  
                  ELSE 
                  
                    IF    (sv_frame_capture(12184)      = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      IF    (CONV_INTEGER(sv_store_count) >=  9 ) THEN
                        IF    (sv_frame_capture(12152)      = '1' ) THEN
              
                          s_sof_out                       <= '1';
                          s_read_enable                   <= '1';                
                          sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                          sv_state_machine                <= OUTPUT;
                      
                      ELSE
                        
                          IF    (sv_frame_capture(12120)     = '1') THEN
              
                            s_sof_out                     <= '1';
                            s_read_enable                 <= '1';                
                            sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine              <= OUTPUT;
                            
                          ELSE
                            IF    (CONV_INTEGER(sv_store_count) >=  10 ) THEN
                              IF    (sv_frame_capture(12088)       = '1' ) THEN
               
                                s_sof_out                       <= '1';
                                s_read_enable                   <= '1';                
                                sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                                sv_state_machine                <= OUTPUT;
                              ELSE
                            
                                s_mpls_error                    <= '1';
                                s_clear                         <= '1';
                                sv_state_machine                <= END_STATE; 
                              END IF;
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF;
          
                     
        ELSIF (sv_sof                                  = "10") THEN       
          ---------------------------------------------------------------------------------------------------------
          --  if MPLS is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_mpls_flag                           = '1') THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  3 ) THEN  
              IF    (sv_frame_capture(12504)            = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                IF (CONV_INTEGER(sv_store_count)      >=  4 ) THEN
                  IF (sv_frame_capture(12472)           = '1') THEN
              
                    s_sof_out                         <= '1';
                    s_read_enable                     <= '1';                
                    sv_byte_num                       <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                    sv_state_machine                  <= OUTPUT;
                  
                  ELSE 
                  
                    IF    (sv_frame_capture(12440)      = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      IF    (CONV_INTEGER(sv_store_count) >=  5 ) THEN
                        IF    (sv_frame_capture(12408)      = '1') THEN
              
                          s_sof_out                       <= '1';
                          s_read_enable                   <= '1';                
                          sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                          sv_state_machine                <= OUTPUT;
                      
                      ELSE
                        
                        IF    (sv_frame_capture(12376)      = '1') THEN
              
                          s_sof_out                       <= '1';
                          s_read_enable                   <= '1';                
                          sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                          sv_state_machine                <= OUTPUT;
                            
                          ELSE
                            IF    (CONV_INTEGER(sv_store_count) >=  6 ) THEN
                              IF    (sv_frame_capture(12344)      = '1') THEN
               
                                s_sof_out                       <= '1';
                                s_read_enable                   <= '1';                
                                sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                                sv_state_machine                <= OUTPUT;
                              
                              ELSE
                            
                                s_mpls_error                    <= '1';
                                s_clear                         <= '1';
                                sv_state_machine                <= END_STATE; 
                              END IF;
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF;
                   
          ---------------------------------------------------------------------------------------------------------
          --  if Q VLAN is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_q_vlan_flag                         = '1') THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  4 ) THEN  
              IF    (sv_frame_capture(12472)            = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                
                IF (sv_frame_capture(12440)             = '1' ) THEN
              
                  s_sof_out                           <= '1';
                  s_read_enable                       <= '1';                
                  sv_byte_num                         <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                  sv_state_machine                    <= OUTPUT;
                  
                ELSE 
                  IF (CONV_INTEGER(sv_store_count)    >=  5 ) THEN
                    IF    (sv_frame_capture(12408)      = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      
                      IF    (sv_frame_capture(12376)   = '1') THEN
              
                        s_sof_out                    <= '1';
                        s_read_enable                <= '1';                
                        sv_byte_num                  <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                        sv_state_machine             <= OUTPUT;
                      
                      ELSE
                        IF    (CONV_INTEGER(sv_store_count) >=  6 ) THEN
                          IF    (sv_frame_capture(12344)      = '1') THEN
              
                            s_sof_out                       <= '1';
                            s_read_enable                   <= '1';                
                            sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine                <= OUTPUT;
                            
                          ELSE
                            
                              IF    (sv_frame_capture(12312)  = '1') THEN
               
                                s_sof_out                   <= '1';
                                s_read_enable               <= '1';                
                                sv_byte_num                 <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                                sv_state_machine            <= OUTPUT;
                              ELSE
                            
                                s_mpls_error                <= '1';
                                s_clear                     <= '1';
                                sv_state_machine            <= END_STATE; 
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF; 
          
          ---------------------------------------------------------------------------------------------------------
          --  if QinQ VLAN is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_q_in_q_flag                         = '1') THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  4 ) THEN  
              IF    (sv_frame_capture(12440)            = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                IF (CONV_INTEGER(sv_store_count)      >=  5 ) THEN
                  IF (sv_frame_capture(12408)           = '1' ) THEN
              
                    s_sof_out                         <= '1';
                    s_read_enable                     <= '1';                
                    sv_byte_num                       <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                    sv_state_machine                  <= OUTPUT;
                  
                  ELSE 
                  
                    IF    (sv_frame_capture(12376)      = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      IF    (CONV_INTEGER(sv_store_count) >=  6 ) THEN
                        IF    (sv_frame_capture(12344)      = '1' ) THEN
              
                          s_sof_out                       <= '1';
                          s_read_enable                   <= '1';                
                          sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                          sv_state_machine                <= OUTPUT;
                      
                        ELSE
                        
                          IF    (sv_frame_capture(12312)   = '1') THEN
              
                            s_sof_out                    <= '1';
                            s_read_enable                <= '1';                
                            sv_byte_num                  <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine             <= OUTPUT;
                            
                          ELSE
                            IF    (CONV_INTEGER(sv_store_count) >=  7 ) THEN
                              IF    (sv_frame_capture(12280)      = '1' ) THEN
               
                                s_sof_out                       <= '1';
                                s_read_enable                   <= '1';                
                                sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                                sv_state_machine                <= OUTPUT;
                              ELSE
                            
                                s_mpls_error                    <= '1';
                                s_clear                         <= '1';
                                sv_state_machine                <= END_STATE; 
                              END IF;
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  if QinQinQ VLAN is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_vlan_defined_flag                   = '1' ) THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  5 ) THEN  
              IF    (sv_frame_capture(12408)            = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                
                IF (sv_frame_capture(12376)             = '1' ) THEN
              
                  s_sof_out                           <= '1';
                  s_read_enable                       <= '1';                
                  sv_byte_num                         <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                  sv_state_machine                    <= OUTPUT;
                  
                  ELSE 
                    IF (CONV_INTEGER(sv_store_count)  >=  6 ) THEN
                      IF    (sv_frame_capture(12344)    = '1') THEN
              
                        s_sof_out                     <= '1';
                        s_read_enable                 <= '1';                
                        sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                        sv_state_machine              <= OUTPUT;
                            
                    ELSE  
                      
                      IF    (sv_frame_capture(12312)    = '1' ) THEN
              
                        s_sof_out                     <= '1';
                        s_read_enable                 <= '1';                
                        sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                        sv_state_machine              <= OUTPUT;
                      
                      ELSE
                        IF    (CONV_INTEGER(sv_store_count) >=  7 ) THEN
                          IF    (sv_frame_capture(12280)      = '1') THEN
              
                            s_sof_out                       <= '1';
                            s_read_enable                   <= '1';                
                            sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine                <= OUTPUT;
                            
                          ELSE
                            
                            IF    (sv_frame_capture(12248)    = '1' ) THEN
               
                              s_sof_out                     <= '1';
                              s_read_enable                 <= '1';                
                              sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                              sv_state_machine              <= OUTPUT;
                            ELSE
                            
                                s_mpls_error                <= '1';
                                s_clear                     <= '1';
                                sv_state_machine            <= END_STATE; 
                            END IF;
                          END IF;
                        END IF;                
                      END IF;  
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF;
          
          ---------------------------------------------------------------------------------------------------------
          --  if MACinMAC VLAN is decoded in first decode check for S bit and add corresponding amount of bytes
          ---------------------------------------------------------------------------------------------------------  
          IF    (s_mac_in_mac_flag                     = '1' ) THEN 
              
            IF    (CONV_INTEGER(sv_store_count)       >=  7 ) THEN  
              IF    (sv_frame_capture(12280)            = '1') THEN
              
                s_sof_out                             <= '1';
                s_read_enable                         <= '1';                
                sv_byte_num                           <= sv_byte_num + CONV_STD_LOGIC_VECTOR(4,12);
                sv_state_machine                      <= OUTPUT;
                            
              ELSE
                
                IF (sv_frame_capture(12248)             = '1' ) THEN
              
                  s_sof_out                           <= '1';
                  s_read_enable                       <= '1';                
                  sv_byte_num                         <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
                  sv_state_machine                    <= OUTPUT;
                  
                ELSE 
                  IF (CONV_INTEGER(sv_store_count)    >=  8 ) THEN
                    IF    (sv_frame_capture(12216)      = '1') THEN
              
                      s_sof_out                       <= '1';
                      s_read_enable                   <= '1';                
                      sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(12,12);
                      sv_state_machine                <= OUTPUT;
                            
                    ELSE  
                      
                      IF    (sv_frame_capture(12184)    = '1' ) THEN
              
                        s_sof_out                     <= '1';
                        s_read_enable                 <= '1';                
                        sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(16,12);
                        sv_state_machine              <= OUTPUT;
                      
                      ELSE
                        IF    (CONV_INTEGER(sv_store_count) >=  9 ) THEN
                          IF    (sv_frame_capture(12152)      = '1') THEN
              
                            s_sof_out                       <= '1';
                            s_read_enable                   <= '1';                
                            sv_byte_num                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(20,12);
                            sv_state_machine                <= OUTPUT;
                            
                          ELSE
                            
                            IF    (sv_frame_capture(12120)     = '1' ) THEN
               
                              s_sof_out                     <= '1';
                              s_read_enable                 <= '1';                
                              sv_byte_num                   <= sv_byte_num + CONV_STD_LOGIC_VECTOR(24,12);
                              sv_state_machine              <= OUTPUT;
                            ELSE
                            
                              s_mpls_error                  <= '1';
                              s_clear                       <= '1';
                              sv_state_machine              <= END_STATE; 
                            END IF;
                          END IF;                
                        END IF;  
                      END IF;                                              
                    END IF;                      
                  END IF;
                END IF;
              END IF;
            END IF;            
          END IF;            
        END IF;
      END IF;
    END IF;
    
    WHEN OUTPUT                                        => 
    IF    (s_t_err                                     = '1') THEN
      
      s_sof_out                                       <= '0';
      sv_byte_num                                     <= (OTHERS => '0');
      s_read_enable                                   <= '0';
      
      s_clear                                         <= '1';
      sv_state_machine                                <= END_STATE;
    ELSE
      s_sof_out                                       <= '0';
      sv_byte_num                                     <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);  
      
      IF    (s_valid                                   = '1') THEN          
      
        IF    (s_eof                                   = '1') THEN           
          
          s_clear                                     <= '1';
          s_eof_out                                   <= '1';
          sv_state_machine                            <= END_STATE;
        END IF;  
      END IF;
    END IF;
        
    WHEN END_STATE                                     =>      
    
      s_sof_out                                       <= '0';
      s_q_vlan_flag                                   <= '0';
      s_q_in_q_flag                                   <= '0';
      s_vlan_defined_flag                             <= '0';
      s_mac_in_mac_flag                               <= '0';
      sv_byte_num                                     <= (OTHERS => '0');
      s_read_enable                                   <= '0';
              
      s_frame_error                                   <= '0';
      s_mpls_error                                    <= '0';
      s_eof_out                                       <= '0';
      ------------------------------------------------------------------------------------------------------------
      --  waits until the sof goes low so as to not get repeated frame errors from incorrect ether-types
      ------------------------------------------------------------------------------------------------------------
      IF    (sv_sof                                    = "00") THEN
          
        sv_state_machine                              <= INIT;
      END IF;
      
    WHEN OTHERS                                        =>
    
      s_sof_out                                       <= '0';
      s_q_vlan_flag                                   <= '0';
      s_q_in_q_flag                                   <= '0';
      s_vlan_defined_flag                             <= '0';
      s_mac_in_mac_flag                               <= '0';
      sv_byte_num                                     <= (OTHERS => '0');
      s_read_enable                                   <= '0';
       
      s_frame_error                                   <= '0';
      s_mpls_error                                    <= '0';
      s_clear                                         <= '0';
      s_eof_out                                       <= '0';
      sv_state_machine                                <= INIT;    
    
    END CASE; 
    
  END IF;

END PROCESS ethertype_decode_reg;

-------------------------------------------------------------------------------
-- output from barrel starting at byte sv_byte_num when read enable is high
-------------------------------------------------------------------------------
output_data_reg: PROCESS(i_clk, i_rst)

BEGIN

  IF (i_rst                    = '1') THEN
    
    s_sof_out_1q              <= '0';
    s_eof_out_1q              <= '0';
    s_t_err_2q                <= '0';
    s_valid_out               <= '0'; 
    sv_data_out               <= (OTHERS => '0'); 
   
  ELSIF (i_clk'event and i_clk = '1') THEN
    
    s_sof_out_1q              <= s_sof_out;
    s_eof_out_1q              <= s_eof_out;
    s_t_err_2q                <= s_t_err_1q;
    
    s_valid_out               <= '0';
    sv_data_out               <= (OTHERS => '0'); 
    
    IF    (s_read_enable       = '1') THEN
      
      s_valid_out             <= '1';    
      sv_data_out             <= sv_frame_capture((((1584 - CONV_INTEGER(sv_byte_num))*8)-1) DOWNTO ((1576 - CONV_INTEGER(sv_byte_num))*8));

    END IF;     
      
  END IF;
END PROCESS output_data_reg;


o_valid <= s_valid_out;
ov_data <= sv_data_out;

o_t_err       <= s_t_err_2q;

o_sof         <= s_sof_out_1q;
o_fr_err      <= s_frame_error;
o_mpls_err    <= s_mpls_error;     
o_eof         <= s_eof_out_1q;     


END ARCHITECTURE rtl;

--------------------------------------------------------------