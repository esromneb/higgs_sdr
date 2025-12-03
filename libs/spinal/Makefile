# Output directories
GEN_DIR = hw/gen
PROJECT_DIR = project

# Source files - find all Scala files in qengine directory
SOURCES := $(wildcard hw/spinal/qengine/*.scala)


all: vao

vao: $(GEN_DIR)/VmemDatArbOut1_1.v

$(GEN_DIR)/VmemDatArbOut1_1.v: $(SOURCES) Makefile
	mkdir -p $(GEN_DIR)
	sbt 'set scalacOptions += "-deprecation"' "runMain qengine.VmemDatArbOut1_1Verilog"

# Clean generated files and build artifacts
clean:
	rm -rf $(GEN_DIR)
	rm -rf $(PROJECT_DIR)/project
	rm -rf $(PROJECT_DIR)/target
	rm -rf target

.PHONY: all clean vao
