set script_dir [file normalize [file dirname [info script]]]
# HIGGS_DATAPATH=img selects the image kernel datapath (doc/kernel/README.md)
set higgs_datapath fft
if {[info exists ::env(HIGGS_DATAPATH)]} {
    set higgs_datapath $::env(HIGGS_DATAPATH)
}
if {$higgs_datapath eq "img"} {
    set output_dir "$script_dir/out_img"
} else {
    set output_dir "$script_dir/out"
}

open_checkpoint $output_dir/cs12_synth.dcp
opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force $output_dir/cs12_routed.dcp
report_clocks -file $output_dir/cs12_clocks.rpt
report_clock_interaction -file $output_dir/cs12_clock_interaction.rpt
report_utilization -file $output_dir/cs12_routed_utilization.rpt
report_timing_summary -delay_type max -max_paths 20 -file $output_dir/cs12_routed_timing_summary.rpt
