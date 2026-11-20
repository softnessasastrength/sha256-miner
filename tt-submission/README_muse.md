# tt-submission — SPOON-1 TinyTapeout project (PREPARED, NOT SUBMITTED)

_muse — prepared 2026-11-20 under Branden's tape-out READINESS brief:
the quality bar is "could be sent tomorrow", not a planned submission.
No submission, no purchase, no account has been made or will be made
without Branden's explicit go for that specific step._

## What this is

The iterative mining core wrapped for the TinyTapeout sky130 template:

- `src/project.v` — `tt_um_spoon_sha256`: the TT pin interface
  (ui_in/uo_out/uio, clk, rst_n). Work is loaded SERIALLY because the
  TT pin budget (8 in / 8 out / 8 bidir) cannot carry a mining job in
  parallel: ui_in[0] = serial data, ui_in[1] = SHIFT, ui_in[2] = GO.
  A 960-bit parameter set (two header blocks' chaining state +
  message words + target) shifts in MSB-first, GO starts the search,
  uio_out reports busy/found/done, uo_out returns an 8-bit folded
  signature of the winning hash. Same scheme as rtl/synth_top.v.
- `src/sha256_*.v` — copies of the verified iterative RTL.
- `info.yaml` — tiles "8x2" (the TT maximum), clock_hz 50000000.
  Sizing evidence: sky130 synthesis of the design (Yosys 0.33,
  sky130_fd_sc_hd) = 183,814 um^2 of cells, ~64% of an 8x2 die;
  the core alone is 82,722 um^2 (~4.6 tiles raw). Log:
  logs/yosys_sky130_2026-11-20.txt.
- `src/config_local_muse.json` — LibreLane config for a local run
  (DIE_AREA 1400x300 um inside the 8x2 footprint).

## To harden (needs a Docker or Nix host — see handoff §4)

```
git clone https://github.com/TinyTapeout/ttsky-verilog-template
cp -r <this folder>/src/* <this folder>/info.yaml ttsky-verilog-template/
# then follow the template's local-hardening instructions
# (LibreLane via Docker/Nix); in this sandbox the flow is blocked
# only by the absence of an OpenROAD binary.
```

Verified so far: the wrapper elaborates cleanly under Icarus
Verilog 12.0; the underlying core passes 3/3 FIPS vectors and the
search recovers the genesis nonce. NOT yet done: LibreLane run
(floorplan/placement/routing/DRC/LVS), gate-level sim of the
wrapper against the template testbench, shuttle paperwork.
