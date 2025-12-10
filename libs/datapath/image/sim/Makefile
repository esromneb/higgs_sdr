# Standalone unit test of img_datapath.v against the Python model.
#   make          lint + build + run (several seeds / stall rates)
#   make lint     verilator -Wall lint only
MODEL   = ../img_model.py
RTL     = ../rtl/img_datapath.v
SEQS   ?= 240

.PHONY: all run lint clean
all: lint run

vectors.txt: $(MODEL)
	python3 $(MODEL) gen-unit $@ --seqs $(SEQS)

obj_dir/Vimg_datapath: $(RTL) tb_img_datapath.cpp
	verilator -Wall --cc $(RTL) --top-module img_datapath --exe tb_img_datapath.cpp -CFLAGS -O1
	$(MAKE) -C obj_dir -f Vimg_datapath.mk -s

lint:
	verilator --lint-only -Wall $(RTL) --top-module img_datapath

run: obj_dir/Vimg_datapath vectors.txt
	./obj_dir/Vimg_datapath vectors.txt 1 0
	./obj_dir/Vimg_datapath vectors.txt 2 30
	./obj_dir/Vimg_datapath vectors.txt 3 70

clean:
	rm -rf obj_dir vectors.txt
