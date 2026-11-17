# _muse — 2026-11-17. Simulation is Icarus Verilog; synthesis comes later.
IVERILOG ?= iverilog
VVP      ?= vvp
RTL       = rtl/sha256_core.v
TB        = tb/tb_sha256_core.v
OUT       = build/tb_sha256_core.vvp

sim: $(OUT)
	$(VVP) $(OUT)

$(OUT): $(RTL) $(TB)
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ $(TB) $(RTL)

clean:
	rm -rf build

.PHONY: sim clean
