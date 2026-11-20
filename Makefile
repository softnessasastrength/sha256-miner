# _muse — 2026-11-17; extended 2026-11-20 (pipelined core + Verilator).
# Simulation is Icarus Verilog; synthesis comes later.
IVERILOG  ?= iverilog
VVP       ?= vvp
VERILATOR ?= verilator
RTL        = rtl/sha256_core.v rtl/sha256d_core.v rtl/sha256d_search.v
PIPE_RTL   = rtl/sha256_pipe.v rtl/sha256d_pipe_search.v
OUT1       = build/tb_sha256_core.vvp
OUT2       = build/tb_sha256d_core.vvp
OUT3       = build/tb_sha256d_search.vvp
OUT4       = build/tb_sha256_pipe.vvp
OUT5       = build/tb_sha256d_pipe_search.vvp

# Note: OUT5 (pipelined search) is slow under Icarus — minutes, not
# seconds. Its throughput test is gated behind the +thru plusarg and
# is normally measured under Verilator instead (make obj-pipe-search).
sim: $(OUT1) $(OUT2) $(OUT3) $(OUT4) $(OUT5)
	$(VVP) $(OUT1)
	$(VVP) $(OUT2)
	$(VVP) $(OUT3)
	$(VVP) $(OUT4)
	$(VVP) $(OUT5)

$(OUT1): rtl/sha256_core.v tb/tb_sha256_core.v
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ tb/tb_sha256_core.v rtl/sha256_core.v

$(OUT2): $(RTL) tb/tb_sha256d_core.v
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ tb/tb_sha256d_core.v rtl/sha256_core.v rtl/sha256d_core.v

$(OUT3): $(RTL) tb/tb_sha256d_search.v
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ tb/tb_sha256d_search.v $(RTL)

$(OUT4): $(PIPE_RTL) tb/tb_sha256_pipe.v
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ tb/tb_sha256_pipe.v rtl/sha256_pipe.v

$(OUT5): $(PIPE_RTL) tb/tb_sha256d_pipe_search.v
	mkdir -p build
	$(IVERILOG) -g2005 -o $@ tb/tb_sha256d_pipe_search.v $(PIPE_RTL)

# Verilator engines. NB: the harness .cpp is passed by absolute path —
# Verilator 5.020's generated makefile resolves a relative user-source
# path against the obj dir and fails with "No rule to make target".
obj-search: $(RTL) host/sim_main_search.cpp
	mkdir -p build
	$(VERILATOR) --cc --exe --build -O2 --top-module sha256d_search \
		-Mdir build/obj-search -o tb_job_search_vl \
		$(RTL) $(abspath host/sim_main_search.cpp)
	cp build/obj-search/tb_job_search_vl build/

obj-pipe-search: $(PIPE_RTL) host/sim_main_pipe_search.cpp
	mkdir -p build
	$(VERILATOR) --cc --exe --build -O2 --top-module sha256d_pipe_search \
		-Mdir build/obj-pipe-search -o tb_pipe_search_vl \
		$(PIPE_RTL) $(abspath host/sim_main_pipe_search.cpp)
	cp build/obj-pipe-search/tb_pipe_search_vl build/

clean:
	rm -rf build

.PHONY: sim clean obj-search obj-pipe-search
