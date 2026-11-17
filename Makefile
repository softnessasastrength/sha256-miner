# _muse — 2026-11-17. Simulation is Icarus Verilog; synthesis comes later.
IVERILOG ?= iverilog
VVP      ?= vvp
RTL       = rtl/sha256_core.v rtl/sha256d_core.v rtl/sha256d_search.v
OUT1      = build/tb_sha256_core.vvp
OUT2      = build/tb_sha256d_core.vvp
OUT3      = build/tb_sha256d_search.vvp

sim: $(OUT1) $(OUT2) $(OUT3)
	$(VVP) $(OUT1)
	$(VVP) $(OUT2)
	$(VVP) $(OUT3)

$(OUT1): rtl/sha256_core.v tb/tb_sha256_core.v
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ tb/tb_sha256_core.v rtl/sha256_core.v

$(OUT2): $(RTL) tb/tb_sha256d_core.v
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ tb/tb_sha256d_core.v rtl/sha256_core.v rtl/sha256d_core.v

$(OUT3): $(RTL) tb/tb_sha256d_search.v
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ tb/tb_sha256d_search.v $(RTL)

clean:
	rm -rf build

.PHONY: sim clean
