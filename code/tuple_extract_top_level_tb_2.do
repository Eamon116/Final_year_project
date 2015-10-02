# do Z:/Uni/Final_Year_Project/Code/tuple_extract_top_level/sim/tuple_extract_top_level_tb_2.do

quit -sim

cd Z:/Uni/Final_Year_Project/Code/tuple_extract_top_level/sim

vlib work
vmap work work

vcom -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/component_package_2.vhd

vcom -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/ddr_to_sdr/ddr_to_sdr_2.vhd

vcom -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/xgmii_decoder/xgmii_decoder.vhd

vcom -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/ether_decode/ether_decode_2.vhd

vcom -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/barrel_shifter/barrel_shifter.vhd

vcom -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/tuple_extract/tuple_extract_2.vhd

vcom -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/tuple_extract_top_level/tuple_extract_top_level_2.vhd

vlog -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/file_pump/file_pump.v

vlog -93 -reportprogress 300 -work work Z:/Uni/Final_Year_Project/Code/tuple_extract_top_level/sim/tuple_extract_top_level_tb.v

file copy -force  Z:/Uni/Final_Year_Project/Code/tuple_extract_top_level/sim/TC00/input_config.txt Z:/Uni/Final_Year_Project/Code/tuple_extract_top_level/sim/input_config.txt   

vsim -novopt +notimingchecks -l "Z:/Uni/Final_Year_Project/Code/tuple_extract_top_level/sim/transcript.txt" work.tuple_extract_tb -t ps

do Z:/Uni/Final_Year_Project/Code/tuple_extract_top_level/sim/wave.do
set StdArithNoWarnings 1
set NumericStdNoWarnings 1

run 4 us
