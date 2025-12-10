set script_dir [file normalize [file dirname [info script]]]
set source_root [file normalize "$script_dir/../../../../.."]
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
set part xczu7ev-ffvc1156-2-e

create_project -force cs12_vivado $output_dir/cs12_vivado -part $part
set_property target_language Verilog [current_project]

proc prj_src {command path} {
    if {$command ne "add"} {
        error "Unsupported prj_src command: $command"
    }

    if {[string match "*/common/ip/lattice/sys_pll/sys_pll.v" $path] ||
        [string match "*/common/modules/core_top.sv" $path] ||
        [string match "*/common/modules/core_reset.sv" $path] ||
        [string match "*/q-engine/hdl/scalar_memory.v" $path] ||
        [string match "*/q-engine/piston/hdl/memory_slice.v" $path] ||
        [string match "*/q-engine/piston/hdl/vmem_dat_6_5.v" $path]} {
        return
    }

    add_files -norecurse $path
    if {[file extension $path] eq ".v"} {
        set_property file_type SystemVerilog [get_files $path]
    }
}

proc prj_impl {args} {}
proc prj_strgy {args} {}

set original_dir [pwd]
cd "$source_root/fpgas/cs/cs12/build"
source ./sources.tcl
cd $original_dir

add_files -norecurse $script_dir/hdl/sys_pll.sv
add_files -norecurse $script_dir/hdl/pmi_fifo_dc.sv
add_files -norecurse $script_dir/hdl/core_top.sv
add_files -norecurse $source_root/fpgas/common/xilinx/scalar_memory_xilinx.sv
add_files -norecurse $source_root/fpgas/common/xilinx/memory_slice_1_1_xilinx.sv
add_files -norecurse $source_root/libs/d-engine/rtl/elastic-buffer/eb15.sv
add_files -norecurse $source_root/libs/q-engine/piston/hdl/vmem_dat_6_5_1_1.v
add_files -norecurse $source_root/libs/q-engine/piston/hdl/vmem_dat_arb_out_spinal_wrapper.v
add_files -norecurse $source_root/libs/spinal/hw/gen/VmemDatArbOut1_1.v

set higgs_defines {HIGGS_FPGA_XILINX MEMORY_SLICE_1_1 VMEM_DAT_ARB_OUT_1_1}
if {$higgs_datapath eq "img"} {
    add_files -norecurse $source_root/libs/datapath/image/rtl/img_datapath.v
    lappend higgs_defines HIGGS_IMG_DATAPATH
}

set_property include_dirs [list \
    "$source_root/fpgas/packages" \
    "$source_root/libs/ip-library/lattice_support/gbit_mac/packages"] \
    [current_fileset]
set_property verilog_define $higgs_defines [current_fileset]
set_property top cs12_top [current_fileset]
update_compile_order -fileset sources_1

read_xdc $script_dir/constraints/cs12_timing.xdc
synth_design -top cs12_top -part $part
report_utilization -file $output_dir/cs12_synth_utilization.rpt
report_timing_summary -delay_type max -max_paths 20 -file $output_dir/cs12_synth_timing_summary.rpt
write_checkpoint -force $output_dir/cs12_synth.dcp
