set script_dir [file normalize [file dirname [info script]]]
set source_root [file normalize "$script_dir/../../../../.."]
set output_dir "$script_dir/out"
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
        [string match "*/q-engine/piston/hdl/memory_slice.v" $path]} {
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
add_files -norecurse $source_root/fpgas/common/xilinx/memory_slice_xilinx.v

set_property include_dirs [list \
    "$source_root/fpgas/packages" \
    "$source_root/libs/ip-library/lattice_support/gbit_mac/packages"] \
    [current_fileset]
set_property verilog_define {HIGGS_FPGA_XILINX} [current_fileset]
set_property top cs12_top [current_fileset]
update_compile_order -fileset sources_1

read_xdc $script_dir/constraints/cs12_timing.xdc
synth_design -top cs12_top -part $part
report_utilization -file $output_dir/cs12_synth_utilization.rpt
report_timing_summary -delay_type max -max_paths 20 -file $output_dir/cs12_synth_timing_summary.rpt
write_checkpoint -force $output_dir/cs12_synth.dcp
