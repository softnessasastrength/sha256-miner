# HANDOFF AND STATUS — sha256-miner

- **AUTHOR:** Ember (Muse), executing agent
- **AUTHORITY:** Branden Algozino's instructions of 2026-11-17 — Route B (design his own core), keep cooking sequentially until a blocker, and leave documentation sufficient for a better-resourced agent to continue.
- **EVIDENCE:** `logs/SIMULATION_LOG_2026-11-17_muse.txt` and `logs/COOK_LOG_2026-11-17_PART2_muse.txt` in this repo (machine-captured run output, not summaries); commit history of this repo; the goal record for "Hand-built Verilog SHA-256 mining core."
- **REQUESTED_ACTION:** Whoever picks this up: continue at §3, in order. The only step that cannot be done without the owner is §3.1 — it needs two strings from him.

## 1. What exists and is verified (2026-11-17)

| Piece | File | Verification |
|---|---|---|
| Iterative SHA-256 core (1 block/run, 64 rounds) | `rtl/sha256_core.v` | 3/3 FIPS 180-4 vectors, Icarus Verilog 12.0 |
| Double-SHA-256 wrapper (80-byte header) | `rtl/sha256d_core.v` | Reproduces the **genesis block hash** exactly, plus a synthetic vector |
| Nonce search (target compare, Bitcoin rule) | `rtl/sha256d_search.v` | Recovers Satoshi's nonce 2083236893 from 500 early in exactly 501 hashes; synthetic sweep finds nonce 434 as computed by reference; clean exhaustion |
| Synthesis harness (serial in, folded signature out) | `rtl/synth_top.v` | Exists because the bare core has ~1,300 ports; no package does |
| Stratum v1 client (software engine) | `host/stratum_miner.py` | Full loop against the mock pool: subscribe → authorize → job → search → submit → **accepted** |
| Mock pool (validates PoW math, not tx validity) | `host/mock_stratum_server.py` | Independently rebuilds the header and recomputes the hash before accepting |
| Local loop test | `host/run_local_test.py` | PASS — one share, validated by the oracle |

Run everything: `make sim` (8 tests) and `python3 host/run_local_test.py`.

## 2. Measured numbers (sandbox, 2026-11-17)

- Yosys 0.33, `sha256d_search` on ECP5: **3,074 LUT4, 4,632 FF**, 9,010 cells total — about 4% of an LFE5U-85F.
- nextpnr-ecp5 via the harness, CABGA381, 100 MHz target: **Fmax 53.54 MHz** (timing fails at 100; the one-round-per-cycle round logic is the critical path, as expected).
- Double-hash cost ≈ 200 clocks (3 core runs + sequencing). At Fmax, one iterative search unit ≈ **0.26 MH/s**. A dozen-plus parallel units fit the 85F by area → **~3–4 MH/s aggregate**, estimates pending a parallel build.
- GH/s requires the pipelined redesign (§3.3). Nothing in this repo promises it yet.

## 3. The road, in order

### 3.1 One accepted share from the real network — OWNER INPUT REQUIRED
Needs from Branden: (a) the throwaway Bitcoin address (old, empty, from the operation he believes is still running), (b) the stratum endpoint (host:port) for that operation. Then:

```
python3 host/stratum_miner.py --host <HOST> --port <PORT> \
    --user <ADDRESS>.spoon --pass x --shares 1
```

Caveats: the software engine runs ~100k H/s in CPython; if the pool's minimum difficulty is high, one share is a long cook (difficulty 0.0001 ≈ 430k expected hashes ≈ seconds; difficulty 1 ≈ 4.3 billion ≈ hours). Some pools accept a difficulty hint in the password field (`d=0.001`). The share that *matters* philosophically should come from the Verilog core — see §3.2 — but a software-engine share validates the account/endpoint first. A share is recorded in the **pool's** books under the address, not on-chain.

### 3.2 Sim-engine bridge — DONE 2026-11-17
The client drives the actual RTL: `tb/tb_job_search.v` is a plusargs harness around `sha256d_search`; the client's `--engine sim` mode chunks the nonce space (default 2,048/chunk) across `vvp` runs. Measured speed: **61 H/s**. Proven: the simulated core mined a share the mock oracle accepted (nonce 7165 at difficulty 1e-6). On top of that, `host/run_fake_world.py` runs the whole dress rehearsal — fake pool in chain mode (`--block-difficulty`), fake chain ledger at `build/fakechain.json`, sim engine hunting a fake BLOCK (share difficulty 1e-5, block difficulty 6e-5; expected ≈70 minutes to the first block at 61 H/s, high variance). A cron (`sha256-fake-block-watch`, every 20 min, owned by this goal) reports the block when it lands or reports if the untracked background run dies (e.g. sandbox VM replacement). Remaining on this branch: none — the live-network version of exactly this run is §3.1.

### 3.3 Pipelined core (the big design project)
Unroll the 64 rounds into a pipeline (one stage per round; two cascaded pipelines for double-SHA-256, reusing the midstate trick: the first 64 bytes of a header block are nonce-independent, so real miners precompute the midstate — worth doing here too). Verify against the same testbenches (genesis first). Expected: one hash per clock per pipeline at a more modest Fmax — two orders of magnitude over §2. This is the step where the sandbox (1.5 vCPU, 6 GB) may run out of food for place-and-route; see §4.

### 3.4 Hardware
`docs/BOARD_PROPOSAL_v1_muse.md` (SPOON-1: ECP5-85F + ESP32-S3, cable-box enclosure doctrine). Proposal only; no order without the owner's explicit go.

## 4. Blockers and environment notes

1. **Owner input** (§3.1) — the only hard blocker on the critical path.
2. **Compute:** this sandbox is 1.5 shared vCPU / 6 GB RAM. Simulation and iterative-core synthesis are fine; a large pipelined design's P&R will be slow. The owner's Dell G5 SE (12 threads, 32 GB, Ubuntu) is the natural next kitchen. Toolchain installs with: `sudo apt install iverilog yosys nextpnr-ecp5 nextpnr-ecp5-chipdb` (all in Ubuntu 24.04 repos; verified 2026-11-17).
3. **Rules of the house:** the repo stays **private** until benchmark numbers exist (owner's rule — synthesis estimates are not benchmarks); **no purchases** of anything, ever, without the owner's explicit go for that specific purchase; work proceeds **sequentially**, one milestone at a time; every claim in this document is backed by the logs in `logs/` — reproduce before trusting.
