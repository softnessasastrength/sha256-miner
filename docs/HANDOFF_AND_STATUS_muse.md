# HANDOFF AND STATUS — sha256-miner

- **AUTHOR:** Ember (Muse), executing agent
- **AUTHORITY:** Branden Algozino's instructions of 2026-11-17 (Route B, keep cooking sequentially) as extended 2026-11-20: §3.1 authorised with a fresh throwaway wallet; own pool authorised; §3.3 pipelined core; tape-out READINESS assessment (no submission, no purchase, no account); hashrate milestone ladder 1k/10k/100k H/s; layout visualisation; swappable-chip requirement recorded for SPOON-1.
- **EVIDENCE:** `logs/SIMULATION_LOG_2026-11-17_muse.txt`, `logs/COOK_LOG_2026-11-17_PART2_muse.txt`, `logs/COOK_LOG_2026-11-20_muse.txt`, `logs/PIPELINE_LOG_2026-11-20_muse.txt`, `logs/pipe_search_icarus_run.txt`, `logs/yosys_sky130_2026-11-20.txt`, `logs/nextpnr_pipe_2026-11-20.txt` in this repo (machine-captured run output, not summaries); commit history of this repo; the goal record for "Hand-built Verilog SHA-256 mining core."
- **REQUESTED_ACTION:** Whoever picks this up: the network permission (§4 item 1) was FIXED by the owner 2026-11-21 — both live tracks now run. The §3.1 share is blocked on a NEW fact (§4 item 5): public-pool.io assigns difficulty 100,000, not 0.001. §3.1 needs one owner decision among the three routes in §3.1's 2026-11-21 entry. Everything else on the road is done or documented below. Do not submit anything for tape-out; readiness is the bar, not a plan.

## 1. What exists and is verified

| Piece | File | Verification |
|---|---|---|
| Iterative SHA-256 core (1 block/run, 64 rounds) | `rtl/sha256_core.v` | 3/3 FIPS 180-4 vectors, Icarus Verilog 12.0 (2026-11-17) |
| Double-SHA-256 wrapper (80-byte header) | `rtl/sha256d_core.v` | Reproduces the **genesis block hash** exactly, plus a synthetic vector |
| Nonce search (target compare, Bitcoin rule) | `rtl/sha256d_search.v` | Recovers Satoshi's nonce 2083236893 from 500 early in exactly 501 hashes; synthetic sweep finds nonce 434; clean exhaustion |
| **Pipelined SHA-256 core (64 stages, 1 block/clock, latency 65)** | `rtl/sha256_pipe.v` | **20/20 Icarus tests (2026-11-20):** FIPS "abc" / empty / 55-byte blocks back-to-back in order, NIST 56-byte two-block chaining, 16× burst no cross-talk |
| **Pipelined double-hash search (3 cascaded pipes)** | `rtl/sha256d_pipe_search.v` | **Icarus: genesis 501 hashes, synthetic 434/435, clean exhaustion.** Verilator: genesis FOUND in 696 clocks (501 + 195 cascade latency); **1M-nonce sweep = 1,000,195 clocks = exactly 1 hash/clock** |
| Synthesis harnesses (serial in, folded signature out) | `rtl/synth_top.v`, `rtl/synth_pipe_top.v`, `rtl/synth_pipe_search_top.v` | Exist because the bare cores have ~1,300+ ports; no package does |
| Stratum v1 client (software engine) | `host/stratum_miner.py` | Full loop against the mock pool: subscribe → authorize → job → search → submit → **accepted** |
| Mock pool (validates PoW math, not tx validity) | `host/mock_stratum_server.py` | Independently rebuilds the header and recomputes the hash before accepting |
| **Verilator bridge (client drives the RTL, compiled)** | `host/sim_main_search.cpp`, `host/stratum_miner_vl.py` | **SHARE ACCEPTED by the mock pool, nonce 775144, 775,145 hashes at 24,495 H/s** (2026-11-20) |
| **Verilator pipelined harness** | `host/sim_main_pipe_search.cpp` | 1M hashes / 7.96 s wall = **125,623 H/s measured** |
| Local loop test | `host/run_local_test.py` | PASS — one share, validated by the oracle |
| **Throwaway wallet + pruned node** | `wallet/` (gitignored, never committed) | Bitcoin Core 32.1, checksum-verified tarball; wallet "spoon-throwaway"; address in §3.1. Seed/keys exist ONLY in `wallet/` |
| **Own pool (ckpool solo)** | `pool/ckpool-solo.conf.template`, live config in `wallet/` | ckpool built and running against the local node; standby until the node syncs (§3.5) |
| **TinyTapeout project (prepared, NOT submitted)** | `tt-submission/` | `tt_um_spoon_sha256` wrapper around the iterative search; elaborates cleanly under Icarus; sized in §3.6 |

Run everything: `make sim` and `python3 host/run_local_test.py`.

## 2. Measured numbers

**Emulation (measured, sandbox):**
- Icarus bridge (iterative RTL): **61 H/s** (2026-11-17).
- Verilator bridge (iterative RTL): **24,495 H/s** end-to-end through the stratum client, share accepted by the mock pool (raw harness 24,560 H/s).
- Verilator pipelined cascade: **125,623 H/s** (1,000,000 hashes, 1 hash/clock in the model).

**Live network (2026-11-21, measured):** stratum session to public-pool.io:21496 completed (subscribe → authorize `result: true` → real `mining.notify`); the bridge searched real pool work at **23,311–24,497 H/s**; pool-assigned difficulty **100,000** (verbatim from `mining.set_difficulty`) — see §3.1's run entry for what that does to the expected wait.

**Milestone ladder (Branden, 2026-11-20) — 1 kH/s → 10 kH/s → 100 kH/s: FULLY CLIMBED in emulation.** Rungs 1+2 crossed by the Verilator iterative bridge (24,495 H/s); rung 3 by the pipelined cascade (125,623 H/s). Evidence: the two 2026-11-20 logs. Everything above the top rung is hardware.

**FPGA synthesis (Yosys 0.33 + nextpnr-ecp5 0.6, LFE5U-85F CABGA381 — SYNTHESIS ESTIMATES, not benchmarks):**
- Iterative search unit: **3,074 LUT4, 4,632 FF** (~4% of device), routed **Fmax 53.54 MHz** → ≈ **0.26 MH/s** per unit; a dozen-plus units fit → ~3–4 MH/s aggregate (2026-11-17).
- Single pipelined core (`synth_pipe_top`): **34,890 LUT4, 64,481 FF** — nextpnr utilisation **TRELLIS_FF 77%, TRELLIS_COMB 52%**, BRAM 0. **Routed Fmax 50.15 MHz** → at 1 hash/clock ≈ **50.15 MH/s per pipe** (~190× the iterative unit). Log: `logs/nextpnr_pipe_2026-11-20.txt`.
- The full 3-pipe mining cascade does **not** fit the 85F: 3 × 64,481 = 193,443 pipeline FF alone vs the device's 83,640 total; even a 2-pipe midstate variant (128,962 FF) exceeds it. (Cascade `synth_ecp5` also OOM-killed Yosys's ABC at the sandbox's 6 GB ceiling — the FF arithmetic from the measured single pipe is the conclusive evidence.) The pipelined miner's homes: a larger FPGA, or ASIC (§3.6). Pipeline registers, not logic, are the currency.

**sky130 standard-cell synthesis (Yosys 0.33, sky130_fd_sc_hd, tt liberty — pre-placement CELL areas from `stat -liberty`; log `logs/yosys_sky130_2026-11-20.txt`):**
- `sha256_core` alone: 9,241 cells, **82,721.84 µm²** (dfxtp_1 ×1,832; nand2_1 ×2,895; maj3_1 ×459; …)
- `sha256d_search` (design only): 5,748 cells, 58,629.98 µm²; design total incl. submodules **183,814 µm²**
- Full `synth_top` incl. serial harness: 20,305 cells, 217,335.94 µm²

## 3. The road, in order

### 3.1 One accepted share from the real network — AUTHORISED, RUNNING, BLOCKED ON POOL DIFFICULTY (see the 2026-11-21 entry below)
Branden authorised this 2026-11-20 with a fresh throwaway ("we'll just use it as a throwaway"). Done: Bitcoin Core 32.1 installed (official tarball, SHA256SUMS verified), wallet "spoon-throwaway" created in the gitignored `wallet/`, native SegWit address:

**`bc1qyv3amdpzz5lghwrkm50nhwa4y3cg6eldx0yvnt`** (public; the only wallet artefact that may be written down — seed and keys never leave `wallet/`)

Pool chosen from live sources: **public-pool.io:21496** — open-source solo pool, documented minimum share difficulty **0.001**, public stats by address. (solo.ckpool.org was rejected on its own FAQ: minimum difficulty 10,000.) Username `<address>.spoon`, password `x`. The Verilator bridge is the engine (24,495 H/s measured): expected time to first share at difficulty 0.001 ≈ **175 s** (2^32 × 0.001 / 24,495, Poisson — could be 10 s, could be 15 min).

**The blocker:** the sandbox's egress interceptor refuses raw TCP verbatim — *"Other TCP connections is turned off for this assistant. To allow it, ask the user to open Muse settings -> Permissions -> Direct network protocols and switch other_tcp from Deny to Ask."* HTTP flows via proxy; stratum and Bitcoin P2P do not. No circumvention attempted. **Fix (owner, ~30 s): flip that setting** — or run the staged launcher on any ordinary machine:

```
host/run_live_public_pool.sh     # supervisor loop, logs to logs/LIVE_RUN_<date>_muse.txt
```

The moment it runs: authorize → notify → set_difficulty → search → submit, and the share lands in public-pool's stats under the address. That pool record — not anything on-chain — is the artifact Branden defined as the endgame.

**Run entry 2026-11-21 (evidence: `logs/COOK_LOG_2026-11-21_muse.txt`, `logs/LIVE_RUN_2026-11-21_muse.txt`, `logs/EGRESS_TEST_2026-11-21_muse.txt`):** The owner flipped the permission and said "Cook." Relaunched: bitcoind acquired 10–11 peers within seconds (headers fully synced, 976,924; blocks validating from genesis), ckpool solo in standby, and the staged launcher connected on its third attempt (16:08:51 UTC): subscribe answered, authorize accepted, real jobs flowing, the Verilator bridge searching at 23,311–24,497 H/s. **The premise then failed on a measured fact:** a brief probe connection captured the pool's own `mining.set_difficulty` verbatim — **100,000**, not the documented 0.001 this section was written around. At ~23,600 H/s the expected time to one share at difficulty 100,000 is ~1.8×10¹⁰ s ≈ **577 years** (arithmetic from measured numbers). The hunt is left running under its supervisor loop (it costs nothing and vardiff could in principle step down), but nobody should expect it to land. **§3.1 now needs one of:** (a) a pool that *verifiably* assigns ~0.001 to tiny workers — verify by probe, never by documentation again; (b) our own pool after IBD (§3.5; difficulty floor 1 → ~50 h expected per share at bridge speed); (c) FPGA hashrate, where difficulty 100,000 is ~2.4 h/share at the pipelined core's ~50 MH/s synthesis estimate. Owner's call.

### 3.2 Sim-engine bridge — DONE (Icarus 2026-11-17; Verilator 2026-11-20)
Icarus bridge: 61 H/s, mined a share the mock oracle accepted (nonce 7165 at difficulty 1e-6); the fake-world dress rehearsal (`host/run_fake_world.py`) stands as built 2026-11-17. Verilator bridge: same client contract, compiled model — 24,495 H/s, mock-pool share accepted (nonce 775144). The Verilator model was verified against the same genesis/synthetic vectors before use.

### 3.3 Pipelined core — DONE 2026-11-20
`rtl/sha256_pipe.v`: 64 stages, one round each, a new block every clock once full, latency 65 clocks, results in order. Per-stage registers: state 256 + chaining 256 + schedule window 512 + block 512 (block carried only through stage 15). Round math identical to the verified iterative core; clean synthesizable RTL, no simulation-only constructs (silicon discipline per the readiness brief). `rtl/sha256d_pipe_search.v` cascades three pipes (header block 1 → header block 2 + nonce → hash-of-digest) with nonce tags in shift registers; the midstate trick was deliberately NOT taken — a uniform cascade keeps one verified contract (a midstate front-end is the obvious v2 optimisation). Verification and synthesis: §1 table and §2. Contract note: after a HIT, pulse `rst_n` before the next `start` (in-flight slots remain in the pipes).

### 3.4 Hardware — SPOON-1
`docs/BOARD_PROPOSAL_v1_muse.md` (ECP5-85F + ESP32-S3, cable-box enclosure doctrine), including the **2026-11-20 addendum: the compute element must be SWAPPABLE** (see §3.6, item 6). Proposal only; no order without the owner's explicit go. New datapoint from §3.3: one pipelined core fills 77% of the 85F's flip-flops — on SPOON-1 the FPGA gives iteration by *reflash* (dual bitstream images, proposal §7), which is the swappable requirement already satisfied in the FPGA embodiment.

### 3.5 Own pool — BUILT, RUNNING, WAITING ON SYNC
Branden, 2026-11-20: "Set up your own pool too." Stack: the §3.1 Bitcoin Core as a **pruned node** (`prune=10000`, datadir in `wallet/`) + **ckpool** (Con Kolivas, built from source, `--without-ckdb`) in **solo mode** (`-B`), coinbase to the throwaway address, coinbase signature `/SPOON-1/`, stratum bound to **127.0.0.1:3333 only**. Template: `pool/ckpool-solo.conf.template`; live config (with the RPC password) lives in `wallet/`, never committed. Status: ckpool runs and polls the node; `getblocktemplate` returns error −9 "Bitcoin Core is not connected!" (0 peers) — correct standby behaviour. The node cannot sync because P2P is raw TCP — the **same §4 item 1 permission** gates this too. **Update 2026-11-21:** the permission was flipped; the node now has 10–11 peers, headers are fully synced (976,924), blocks are validating from genesis, and ckpool's poll now returns error −10 "Bitcoin Core is in initial sync and waiting for blocks..." — still correct standby, one step closer. IBD on this sandbox will take a long time; ckpool serves real work automatically when it completes. Once the node syncs, ckpool serves real chain-tip work automatically and a bridge instance points at `127.0.0.1:3333` as a second live run. Honest limits: this ckpool build's difficulty fields are integers, so the **home-pool difficulty floor is 1** — ~48 h per share for the Verilator bridge, trivial for FPGA hardware. Logs: `pool/logs/ckpool_stdout.log`, `pool/logs/spoon.log`.

### 3.6 Tape-out READINESS assessment (proposal/assessment only — no submission, no purchase, no account)
Branden's framing: *"We don't have to physically send it for tapeout. I just want it so that theoretically I could send it to tapeout — FPGA practically."* Readiness is the quality bar; the practical embodiment remains FPGA (ECP5 / SPOON-1). Shuttle facts below were checked live from tinytapeout.com on 2026-11-20 and are context for the bar only.

**The bar — what "could send it tomorrow" requires (TinyTapeout, sky130):**
1. A `tt_um_*` top module on the fixed pin interface (`ui_in[7:0]`, `uo_out[7:0]`, `uio[7:0]` + `ena`, `clk`, `rst_n`) — **DONE**: `tt-submission/src/project.v` (`tt_um_spoon_sha256`), elaborates cleanly under Icarus.
2. A pin-budget design for getting work on/off chip — **DONE**: serial load (ui_in[0] data, [1] SHIFT, [2] GO; 960-bit parameter set), status on `uio_out`, 8-bit folded hash signature on `uo_out`. A mining job cannot cross 24 pins in parallel; serial is the honest answer, same scheme as the FPGA harness.
3. Tile fit — **ASSESSED FROM MEASURED NUMBERS**: tile ≈167×108 µm (current template `info.yaml`); valid sizes 1x1…8x2. Iterative design (the realistic candidate): 183,814 µm² of cells ≈ **64% of an 8x2 die** (~288,576 µm²) — fits the maximum tile at a plausible density; the core alone is ~4.6 tiles raw. The **pipelined core does not fit TT**: ~3× the iterative design's register-heavy structure (its ECP5 build is 64,481 FF for ONE pipe of three) — stated from the synthesis numbers, not vibes. FPGA→standard-cell conversion note: the sky130 figures above are DIRECT synthesis against the real liberty, not a conversion estimate — no conversion was needed.
4. Hardening flow run (LibreLane, sky130) producing GDS — **NOT RUN; one tool short.** LibreLane 3.0.17 + volare are installed (`~/workspace/tools/llane-venv`) and the sky130A PDK is enabled (2.0 GB), but **no OpenROAD binary is obtainable in this sandbox** (checked: OpenROAD releases ship no binaries; no apt package; OSS CAD Suite builds don't bundle it; Docker/Nix unavailable; source build = hours on 1.5 vCPU). On any Docker/Nix host (e.g. the Dell G5 SE) the prepared project in `tt-submission/` hardens with the template's standard flow. The synthesis half of the flow IS done locally (§2 sky130 numbers).
5. Shuttle context (checked 2026-11-20): **TTSKY26d and TTSKY26e close 2026-11-30** (chips expected 2027-05-25); TTSKY27a follows with a May 2027 deadline. Cost: TinyTapeout's own calculator is a JavaScript app whose figures a text fetch cannot read (limitation, stated); secondary sources that extracted TT's published pricing give **€70 per tile, devkit PCB €300 (€100 subsidised for individuals, limited), €15 shipping** — label: secondary-sourced, 2026-11-20, NOT a TT-published table. Any slot decision is Branden's alone, later; nothing here is a plan to buy.
6. **Swappable compute (Branden's requirement, 2026-11-20):** *"make them pin grid array so that as we iterate I can just put new chips in the device."* Assessed honestly (also appended to the board proposal as a dated addendum): (a) shuttles deliver **QFN** — TT's own specs state all TT chips are expected in QFN, arriving **soldered on a breakout board that plugs into a demo/motherboard without soldering a bare ASIC**; PGA is not offered by any shuttle. (b) PGA is also a factual mismatch: this design needs ~24 signals; PGA is a legacy through-hole package of hundreds of pins. (c) The requirement — *drop in a new chip, keep the device* — is delivered by the **carrier/module pattern** (TT's own breakout is exactly this), by clamshell/ZIF sockets as bench tools, and on SPOON-1 by **swap-by-reflash** (the ECP5 is soldered BGA-381; new bitstreams are the iteration, dual images already in the proposal). (d) **Recommendation:** define a module boundary from the schematic phase — power + SPI + clock + reset across one connector — so an ASIC-on-carrier later drops into the same box the FPGA board occupies today.

**Layout visualisation (Branden wants to LOOK at the design):** in `docs/layout/` — transistor-level GDS portraits of the actual sky130 cells this design is built from (`cell_dfxtp_1.png` — the D flip-flop, 1,832 instances in the core; `cell_nand2_1.png`; `cell_maj3_1.png` — the Maj gate), drawn from the real PDK GDS by `docs/render_cell_mpl_muse.py`; plus the full gate-level schematic of `sha256_core` from the sky130 netlist (`sha256_core_schematic.svg`, netlistsvg, zoomable; PNG renders alongside). A die-level GDS portrait requires the OpenROAD run in item 4 — that is the one view still missing, and the blocker is named there.

**Remaining work list, verified-Verilog → submittable:** (i) run LibreLane on a Docker/Nix host against `tt-submission/`; (ii) gate-level sim of the wrapper in the template's testbench; (iii) confirm final tile size from the hardened area (8x2 assumed); (iv) shuttle paperwork + slot purchase — OWNER ONLY, not authorised. Items (i)–(iii) are an afternoon on the G5 SE.

## 4. Blockers and environment notes

1. **Network permission — RESOLVED 2026-11-21 (owner action taken):** sandbox raw TCP was denied (Muse settings → Permissions → Direct network protocols → `other_tcp`: Deny → Ask). The owner flipped it; evidence the gate is open: bitcoind holds 10–11 real peers and synced all headers, and a stratum session to public-pool.io completed subscribe + authorize + notify. Note for future diagnosis: raw `connect()` "succeeds" instantly against the sandbox's intercepting layer (peer 198.19.0.1:3128) in both states — only real protocol traffic distinguishes open from closed.
2. **OpenROAD absence** gates the LibreLane hardening run and the die-level layout view (§3.6 items 4). Fix: any Docker/Nix host.
3. **Compute:** this sandbox is 1.5 shared vCPU / 6 GB RAM. It OOM-killed the cascade's `synth_ecp5` in ABC and took ~70 min to place-and-route one pipe (successfully). The owner's Dell G5 SE (12 threads, 32 GB, Ubuntu) is the natural next kitchen for the cascade P&R and LibreLane. Toolchain: `sudo apt install iverilog yosys nextpnr-ecp5 verilator klayout` (Ubuntu 24.04 repos; versions used here: Icarus 12.0, Yosys 0.33, nextpnr-ecp5 0.6, Verilator 5.020).
4. **Environment lesson (2026-11-20):** a sandbox service restart wipes apt-installed tools (home directory persists). Reinstall before assuming a tool is gone; bitcoind/ckpool processes also die — restart them from `wallet/` and `pool/`.
5. **Pool difficulty (the live §3.1 blocker, discovered 2026-11-21):** public-pool.io assigns this worker difficulty **100,000** (captured verbatim from its `mining.set_difficulty`), contradicting the 0.001 minimum the 2026-11-20 web research reported. At bridge hashrate the expected wait is ~577 years. Lesson, same family as item 4's: a pool's *documented* minimum is not its *assigned* difficulty — probe before planning. Routes around it are listed in §3.1's 2026-11-21 entry; choosing one is the owner's.
6. **Rules of the house:** the repo stays **private** until benchmark numbers exist (owner's rule — synthesis estimates are not benchmarks); **no purchases** of anything, ever, without the owner's explicit go for that specific purchase; seed phrase and private keys live only in the gitignored `wallet/` and are never written anywhere else; work proceeds **sequentially**, one milestone at a time; every claim in this document is backed by the logs in `logs/` — reproduce before trusting.
