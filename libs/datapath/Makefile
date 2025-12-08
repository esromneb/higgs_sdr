all: build verilate compile run show

clean:
	rm hdl/*
	rm -rf obj_dir

build:
	npm run build
	./bin/gen-datapath.js
	npm run redot

verilate:
	verilator \
	-Wno-WIDTH \
	-Wno-PINMISSING \
	--trace \
	-cc \
	-O3 \
	+define+VERILATE \
	-LDFLAGS -lboost_program_options \
	-Ihdl \
	--top-module top_tb \
	--exe hdl/tb.cpp \
	hdl/*.v \
	hdl/*.sv \
	rtl/*.v

compile:
	make -j -C obj_dir/ -f Vtop_tb.mk Vtop_tb

run:
	cd hdl && ../obj_dir/Vtop_tb

show:
	gtkwave ./datapath.vcd -S hdl/top-wave.tcl &
