open_project vivado_proj/netsec_accel_zu4ev.xpr
open_run impl_1
write_bitstream -force bitstream_output/system_top.bit
puts "BIT_DONE"
