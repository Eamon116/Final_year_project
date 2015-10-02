-- tuple_extract.vhd
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


-------------------------------------------------------------------------------

ENTITY tuple_extract IS
 
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
END tuple_extract;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF tuple_extract IS
 

-------------------------------------------------------------------------------
----------------------------------------------------------------------------
TYPE TUPLE_SM_TYPE        IS  (INIT, PROTOCOL_DECODE, TUPLE_EXTRACT, OUTPUT_END, OUTPUT, END_STATE);

-- input_store_reg -- MTU is 1526 bytes for a simple IP packet including preammble and SFD
--                 -- with PBB VLAN and max MPLS MTU is 1578 bytes
SIGNAL sv_store_count          : STD_LOGIC_VECTOR(6-1 DOWNTO 0);
SIGNAL sv_frame_capture        : STD_LOGIC_VECTOR(64*198-1 DOWNTO 0); -- 1578 * 8 

	             
SIGNAL s_valid                 : STD_LOGIC;
SIGNAL s_sof                   : STD_LOGIC;
SIGNAL s_t_err                 : STD_LOGIC;
SIGNAL s_eof                   : STD_LOGIC;

-- tuple_extract_reg -- signals	             
SIGNAL s_t_err_1q              : STD_LOGIC;

SIGNAL s_ihl_5                 : STD_LOGIC;
SIGNAL s_ihl_6                 : STD_LOGIC;
SIGNAL s_icmp_flag             : STD_LOGIC;

SIGNAL s_read_enable           : STD_LOGIC;
SIGNAL s_clear                 : STD_LOGIC;
SIGNAL sv_byte_num             : STD_LOGIC_VECTOR (12-1  DOWNTO 0);

SIGNAL sv_five_tuple           : STD_LOGIC_VECTOR (104-1  DOWNTO 0);	           	

SIGNAL s_sof_out               : STD_LOGIC;
SIGNAL s_ihl_err               : STD_LOGIC;
SIGNAL s_ip_error              : STD_LOGIC; 
SIGNAL s_eof_out               : STD_LOGIC;

SIGNAL sv_out_count            : STD_LOGIC_VECTOR(3-1 DOWNTO 0);

SIGNAL sv_tuple_sm             : TUPLE_SM_TYPE;

-- output_data_reg
SIGNAL sv_five_tuple_1q        : STD_LOGIC_VECTOR (104-1  DOWNTO 0);	           	
SIGNAL s_sof_out_1q            : STD_LOGIC;
SIGNAL s_eof_out_1q            : STD_LOGIC;

SIGNAL s_valid_out             : STD_LOGIC;
SIGNAL sv_data_out             : STD_LOGIC_VECTOR(64-1 DOWNTO 0);


-------------------------------------------------------------------------------

BEGIN	-- rtl

-------------------------------------------------------------------------------
-- capture the input data into the barrel
-------------------------------------------------------------------------------
input_store_reg: PROCESS(i_clk, i_rst)

BEGIN

  IF (i_rst                    = '1') THEN
    
    s_valid                   <= '0';
    s_sof                     <= '0';  
    s_t_err                   <= '0';
    s_eof                     <= '0';
    sv_store_count            <= (OTHERS => '0');  
    sv_frame_capture          <= (OTHERS => '0');        
    
  ELSIF (i_clk'event and i_clk = '1') THEN
    
    s_valid                                <= i_valid;
    s_sof                                  <= i_sof;
    s_t_err                                <= i_t_err;
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
-- 
-------------------------------------------------------------------------------
tuple_extract_reg: PROCESS(i_clk,i_rst)

BEGIN

  IF i_rst = '1' THEN
    
    s_t_err_1q                   <= '0';
    
    s_ihl_5                      <= '0';
    s_ihl_6                      <= '0';
    s_icmp_flag                  <= '0';
    
    s_read_enable                <= '0';
    s_clear                      <= '0';
    sv_byte_num                  <= (OTHERS => '0');
    
    s_sof_out                    <= '0';
    s_ihl_err                    <= '0';
    s_ip_error                   <= '0';   
    s_eof_out                    <= '0';   
    
    sv_out_count                 <= (OTHERS => '0');
    sv_five_tuple                <= (OTHERS => '0');
    
    sv_tuple_sm                  <= INIT;

         
  ELSIF (i_clk'event and i_clk = '1') THEN
    
    s_t_err_1q                   <= s_t_err;

  CASE sv_tuple_sm IS 
  
    WHEN INIT =>
    IF    (s_t_err                                               = '1') THEN
        
      sv_tuple_sm                                               <= INIT;  
    ELSE    
      IF    (s_valid                                             = '1') THEN    
        IF    (s_sof                                             = '1') THEN
         
          IF    (CONV_INTEGER(sv_frame_capture(12667 DOWNTO 12664)) =  5 ) THEN
          
            s_ihl_5                                             <= '1';
            sv_tuple_sm                                         <= PROTOCOL_DECODE;   
            
          ELSIF (CONV_INTEGER(sv_frame_capture(12667 DOWNTO 12664)) =  6 ) THEN
            
            s_ihl_6                                             <= '1';
            sv_tuple_sm                                         <= PROTOCOL_DECODE;
          
          ELSE
        
            s_ihl_err                                           <= '1';
            s_clear                                             <= '1';
            sv_tuple_sm                                         <= END_STATE;
          
          END IF;
        END IF;
      END IF;
    END IF;    
    WHEN PROTOCOL_DECODE =>
    IF    (s_t_err                                               = '1') THEN
            
      s_clear                                                   <= '1';
      sv_tuple_sm                                               <= END_STATE;  
    ELSE
      IF    (s_valid                                             = '1') THEN    
        IF    (CONV_INTEGER(sv_store_count)                     >=  2 ) THEN
        
          IF    (CONV_INTEGER(sv_frame_capture(12599 DOWNTO 12592)) =  1 ) THEN
          
            s_icmp_flag                                         <= '1';
            sv_tuple_sm                                         <= TUPLE_EXTRACT;  
            
          ELSIF (CONV_INTEGER(sv_frame_capture(12599 DOWNTO 12592)) =  6 ) OR
                (CONV_INTEGER(sv_frame_capture(12599 DOWNTO 12592)) = 17 ) THEN
          
            sv_tuple_sm                                         <= TUPLE_EXTRACT;          
          
          ELSE
          
            s_ip_error                                          <= '1';
            s_clear                                             <= '1';
            sv_tuple_sm                                         <= END_STATE;
        
          END IF;
        END IF;
      END IF; 
    END IF;       
    
    WHEN TUPLE_EXTRACT =>
    IF    (s_t_err                                               = '1') THEN
            
      s_clear                                                   <= '1';
      sv_tuple_sm                                               <= END_STATE;  
    ELSE
      IF    (s_valid                                             = '1') THEN
        
        IF    (s_icmp_flag                                       = '1') THEN
          
          sv_five_tuple                                         <= sv_frame_capture(12575 DOWNTO 12544) & -- ip source
                                                                   x"0000" &                           -- source port
                                                                   sv_frame_capture(12543 DOWNTO 12512)  & -- ip destination
                                                                   x"0000" &                           -- destination port
                                                                   sv_frame_capture(12599 DOWNTO 12592);  -- protocol
          
          s_sof_out                                             <= '1';
          s_read_enable                                         <= '1';   
          sv_tuple_sm                                           <= OUTPUT;
           
        ELSE
          IF    (s_ihl_5                                         = '1') THEN  
            IF    (CONV_INTEGER(sv_store_count)                 >=  3 ) THEN
          
              sv_five_tuple                                     <= sv_frame_capture(12575 DOWNTO 12544) & -- ip source
                                                                 sv_frame_capture(12511 DOWNTO 12496)   & -- source port
                                                                 sv_frame_capture(12543 DOWNTO 12512)  & -- ip destination
                                                                 sv_frame_capture(12495 DOWNTO 12480)   & -- destination port
                                                                 sv_frame_capture(12599 DOWNTO 12592);  -- protocol
       
              s_sof_out                                         <= '1';   
              s_read_enable                                     <= '1';
              sv_tuple_sm                                       <= OUTPUT;
            END IF;
          END IF;
    
          IF    (s_ihl_6                                         = '1') THEN  
            IF    (CONV_INTEGER(sv_store_count)                 >=  4 ) THEN
          
              sv_five_tuple                                     <= sv_frame_capture(12575 DOWNTO 12544) & -- ip source
                                                                 sv_frame_capture(12479 DOWNTO 12464)   & -- source port
                                                                 sv_frame_capture(12543 DOWNTO 12512)  & -- ip destination
                                                                 sv_frame_capture(12463 DOWNTO 12448)   & -- destination port
                                                                 sv_frame_capture(12599 DOWNTO 12592);  -- protocol
       
              s_sof_out                                         <= '1';   
              s_read_enable                                     <= '1';
              sv_tuple_sm                                       <= OUTPUT;
            END IF;
          END IF;
        END IF;
    
    
      END IF; 
    END IF;
        
    WHEN OUTPUT =>

    IF    (s_t_err                                             = '1') THEN
      
      s_read_enable                                           <= '0';
      sv_byte_num                                             <= (OTHERS => '0');
      
      s_clear                                                 <= '1';
      sv_tuple_sm                                             <= END_STATE;
    ELSE
      s_sof_out                                               <= '0';
      sv_byte_num                                             <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);  
      
      IF    (s_valid                                           = '1') THEN          
      
        IF    (s_eof                                           = '1') THEN           
          
          sv_out_count                                        <= sv_out_count + 1;
          sv_tuple_sm                                         <= OUTPUT_END;
        END IF;  
      END IF;
    END IF;    
    
    WHEN OUTPUT_END =>
    IF    (s_t_err                                             = '1') THEN
            
      s_read_enable                                           <= '0';
      sv_byte_num                                             <= (OTHERS => '0');
      
      s_clear                                                 <= '1';
      sv_tuple_sm                                             <= END_STATE; 
    ELSE
      sv_out_count                                            <= sv_out_count + 1;
      sv_byte_num                                             <= sv_byte_num + CONV_STD_LOGIC_VECTOR(8,12);
      
      IF    (s_ihl_5                                           = '1') THEN    
        IF    (CONV_INTEGER(sv_out_count)                      =  2 ) THEN
         
         s_clear                                              <= '1';

         s_eof_out                                            <= '1';
         sv_tuple_sm                                          <= END_STATE;
        
        END IF;
      END IF;
    
      IF    (s_ihl_6                                           = '1') THEN    
        IF    (CONV_INTEGER(sv_out_count)                      =  3 ) THEN
           
           s_clear                                            <= '1';

           s_eof_out                                          <= '1';
           sv_tuple_sm                                        <= END_STATE;
        
        END IF;
      END IF;
    END IF;    
    
    WHEN END_STATE =>
      
      s_ihl_5                                         <= '0';
      s_ihl_6                                         <= '0';
      s_icmp_flag                                     <= '0';
    
      s_read_enable                                   <= '0';
      s_clear                                         <= '0';
      sv_byte_num                                     <= (OTHERS => '0');
    
      s_sof_out                                       <= '0';
      s_ihl_err                                       <= '0';
      s_ip_error                                      <= '0';   
      s_eof_out                                       <= '0';   
    
      sv_out_count                                    <= (OTHERS => '0');
      sv_five_tuple                                   <= (OTHERS => '0');
    
      sv_tuple_sm                                     <= INIT;
        
    WHEN OTHERS =>
      
      s_ihl_5                                         <= '0';
      s_ihl_6                                         <= '0';
      s_icmp_flag                                     <= '0';
    
      s_read_enable                                   <= '0';
      s_clear                                         <= '0';
      sv_byte_num                                     <= (OTHERS => '0');
    
      s_sof_out                                       <= '0';
      s_ihl_err                                       <= '0';
      s_ip_error                                      <= '0';   
      s_eof_out                                       <= '0';   
    
      sv_out_count                                    <= (OTHERS => '0');
      sv_five_tuple                                   <= (OTHERS => '0');
    
      sv_tuple_sm                                     <= INIT;
      
  END CASE;

  END IF;

END PROCESS tuple_extract_reg;

-------------------------------------------------------------------------------
-- output from barrel starting at byte sv_byte_num when read enable is high
-------------------------------------------------------------------------------
output_data_reg: PROCESS(i_clk, i_rst)

BEGIN

  IF (i_rst                    = '1') THEN
    
    sv_five_tuple_1q          <= (OTHERS => '0'); 
    s_sof_out_1q              <= '0';
    s_eof_out_1q              <= '0';
    s_valid_out               <= '0'; 
    sv_data_out               <= (OTHERS => '0'); 
   
  ELSIF (i_clk'event and i_clk = '1') THEN
    
    sv_five_tuple_1q          <= sv_five_tuple;
    s_sof_out_1q              <= s_sof_out;
    s_eof_out_1q              <= s_eof_out;
    
    s_valid_out               <= '0';
    sv_data_out               <= (OTHERS => '0'); 
    
    IF    (s_read_enable       = '1') THEN
      
      s_valid_out             <= '1';    
      sv_data_out             <= sv_frame_capture((((1584 - CONV_INTEGER(sv_byte_num))*8)-1) DOWNTO ((1576 - CONV_INTEGER(sv_byte_num))*8));

    END IF;     
      
  END IF;
END PROCESS output_data_reg;



ov_five_tuple  <= sv_five_tuple_1q;  
	 
o_valid        <= s_valid_out;
ov_data        <= sv_data_out;

o_t_err        <= s_t_err_1q;
	 
o_sof		        <= s_sof_out_1q;     
o_ihl_err      <= s_ihl_err;   	 
o_ip_err       <= s_ip_error;          
o_eof		        <= s_eof_out_1q;        


END ARCHITECTURE rtl;

-------------------------