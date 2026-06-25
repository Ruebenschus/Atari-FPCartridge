SHELL := /bin/zsh

OSS_CAD := /Users/jbecker/fpga/oss-cad-suite
YOSYS := $(OSS_CAD)/bin/yosys
NEXTPNR := $(OSS_CAD)/bin/nextpnr-ecp5
ECPPACK := $(OSS_CAD)/bin/ecppack
OPENFPGALOADER := $(OSS_CAD)/bin/openFPGALoader
BOARD := ulx3s

TOP := top
DEVICE := 12k
PACKAGE := CABGA381

SOURCES := \
	rtl/top.v \
	rtl/cart_rom.v \
	rtl/button_edge.v \
	rtl/ssd1306_menu.v

ROM_LOW := ROM_TEST_KIT_FOR_ST_V4.4/ST4_4.LOW
ROM_HIGH := ROM_TEST_KIT_FOR_ST_V4.4/ST4_4.HGH
ROM_MEM := build/cart_rom.mem

.PHONY: all build prog prog-sudo flash flash-sudo detect detect-sudo clean check-tools

all: build

build: check-tools $(ROM_MEM)
	mkdir -p build
	$(YOSYS) -p "synth_ecp5 -top $(TOP) -json build/$(TOP).json" $(SOURCES)
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --json build/$(TOP).json --lpf ulx3s.lpf --textcfg build/$(TOP).config
	$(ECPPACK) build/$(TOP).config build/$(TOP).bit

$(ROM_MEM): $(ROM_LOW) $(ROM_HIGH) tools/build_cart_mem.py
	mkdir -p build
	python3 tools/build_cart_mem.py $(ROM_LOW) $(ROM_HIGH) $(ROM_MEM)

prog: build
	$(OPENFPGALOADER) -b $(BOARD) build/$(TOP).bit

prog-sudo:
	sudo $(OPENFPGALOADER) -b $(BOARD) build/$(TOP).bit

flash: build
	$(OPENFPGALOADER) -b $(BOARD) -f build/$(TOP).bit

flash-sudo:
	sudo $(OPENFPGALOADER) -b $(BOARD) -f build/$(TOP).bit

detect:
	$(OPENFPGALOADER) -b $(BOARD) --detect

detect-sudo:
	sudo $(OPENFPGALOADER) -b $(BOARD) --detect

clean:
	rm -rf build/*

check-tools:
	@test -x $(YOSYS) || (echo "missing yosys: $(YOSYS)" && exit 1)
	@test -x $(NEXTPNR) || (echo "missing nextpnr: $(NEXTPNR)" && exit 1)
	@test -x $(ECPPACK) || (echo "missing ecppack: $(ECPPACK)" && exit 1)
	@test -x $(OPENFPGALOADER) || (echo "missing openFPGALoader: $(OPENFPGALOADER)" && exit 1)
