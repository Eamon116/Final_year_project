`timescale 1ps/1ps

module file_pump #(

parameter 			DATA_WIDTH = 8	 )(

input  wire 			i_clk,
input  wire 			i_rst,

input  wire    i_enable,

output reg 		 	o_data_valid,
output reg[DATA_WIDTH-1:0] 	ov_data

);

integer data_file, read_file ;

reg[DATA_WIDTH-1:0] data;

`define NULL 0 
`define EMPTY 32'hffff_ffff

//-----------------------------------------------------------------------
//-- file extraction
//-----------------------------------------------------------------------
initial begin
  data_file = $fopen("input_config.txt", "r");
  if (data_file == `NULL) begin
    $display("data_file handle was NULL");
    $finish;
  end
end 

always @(posedge i_clk or negedge i_rst) begin
	if (i_rst) begin 
      
      read_file     <= 0;
		o_data_valid 	<= 1'd0;
		data          <= {DATA_WIDTH{1'b0}};
		ov_data   	   <= {DATA_WIDTH{1'b0}};	
	end else begin 
			
			if (i_enable) begin
			  read_file	           = $fscanf(data_file, "%x", data);
			
			  if (read_file       != `EMPTY) begin
			 
			        o_data_valid 	<= 1'd1;
			        ov_data 	     <= data;
			  end else begin 
			 
			        o_data_valid 	<= 1'd0;
			        ov_data 	     <= {DATA_WIDTH{1'd0}}; 	 	   
			   	
			  end
			end else begin 
			 
			      o_data_valid 	  <= 1'd0;
			      ov_data 	       <= {DATA_WIDTH{1'd0}}; 	 	   
			   	
		   end			   	 	   
	end
end

endmodule 