HIGGS_ROOT=../../..
###############
#
#  test_image_1: image kernel datapath platform test (doc/kernel/README.md).
#
#  The TB injects a multi-job image stream (libs/datapath/image/img_model.py
#  gen-stream) on cs22in. cs22 runs the image C library (image_kernel.c)
#  on the image datapath. cs22out is captured and compared job by job with
#  the Python model. cs21 runs a DMA sink so that cs22out has a ready.
#
#  make stream     generate in.hex / exp.hex
#  make test       Verilator build + run (+ compare)
#  make xsim_compare  XSIM run, compared with the model and with Verilator

# the image datapath replaces the FFT datapath in every q-engine of the build
HIGGS_DATAPATH=img

OVERRIDE_CS22_C=1
OVERRIDE_CS21_C=1

TB_USE_CS32=1
TB_USE_CS22=1
TB_USE_CS21=1

CS32_NO_RISCV=1

IMG_MODEL=$(HIGGS_ROOT)/libs/datapath/image/img_model.py

HIGGS_TEST_DIR=.
include $(HIGGS_ROOT)/scripts/make_include/tb_common.mk

# the TB reads in.hex / exp.hex from the working directory
.PHONY: stream
stream:
	python3 $(IMG_MODEL) gen-stream in.hex exp.hex
compile: stream

XSIM_COMPARE_COMMAND = python3 $(IMG_MODEL) compare exp.hex xsim_got.hex && cmp got.hex xsim_got.hex && echo "XSIM matches Verilator"
include $(HIGGS_ROOT)/scripts/make_include/xsim_common.mk
xsim_compile: stream
