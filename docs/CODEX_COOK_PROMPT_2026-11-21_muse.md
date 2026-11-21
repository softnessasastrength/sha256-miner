# CODEX COOK PROMPT — sha256-miner verification and cloud cook

Paste-ready brief for the ChatGPT/Codex process. Written 2026-11-21 by Ember at the owner's instruction.

---

**AUTHOR:** Ember (Muse), on behalf of Branden Algozino (owner)
**AUTHORITY:** Branden's instructions of 2026-11-21: "Update GitHub so I can have gpt verify", "make it public cause we have numbers", and "a prompt for codex to cook in the clouds". Repo made public by the owner on that authority after a secrets audit (66-file tree; no wallet paths; content scan clean — the only match for key-material patterns is the house rule stating keys are never committed).
**EVIDENCE:** Everything claimed below is backed by files in this repository. Reproduce before trusting; where your results disagree with the logs, your results win and the discrepancy is the finding.
**REQUESTED_ACTION:** (1) Independently verify the claims in Part 1 against the repo evidence. (2) Cook the items in Part 2 in your cloud environment, on a clearly labelled branch, and report back in a memo carrying these same four header fields. Hard constraints in Part 3 are not negotiable.

## The project

`softnessasastrength/sha256-miner` (public) — a hand-built Bitcoin mining core in Verilog, designed by Branden Algozino with Ember as the execution-side agent. Not an economics project: the stated achievement is a working core of his own design producing an accepted share on the real Bitcoin network. Full state, history, and doctrine: `docs/HANDOFF_AND_STATUS_muse.md` (read it first; it is the map). Current main at time of writing: `7bd16a39`.

## Part 1 — Verify these claims

1. **Design correctness.** `rtl/sha256_core.v` (iterative SHA-256, FIPS 180-4) passes its testbench vectors; `rtl/sha256d_core.v` reproduces the genesis block hash exactly; `rtl/sha256d_search.v` recovers the genesis nonce 2083236893. Testbenches in `tb/`, run logs in `logs/`. Re-run them (iverilog is enough) and confirm the PASS lines are real.
2. **Pipelined core.** `rtl/sha256_pipe.v` + `rtl/sha256d_pipe_search.v`: 20/20 pipe testbench checks; Verilator sweep of 1,000,000 nonces in 1,000,195 clocks = exactly 1 hash/clock, 125,623 H/s measured in emulation. Logs: `logs/PIPELINE_LOG_2026-11-20_muse.txt`, `logs/pipe_search_icarus_run.txt`.
3. **The endgame — accepted shares, real network.** On 2026-11-21 the project's Verilator bridge, mining at BCMonster (bcmonster.com:9999, wire-verified assigned difficulty 0.001 — see the probe table in `logs/POOL_PROBE_2026-11-21_muse.txt`), had two shares accepted: 19:08:38 UTC, nonce 11760654, hash `0000003e1bf12b15c6c8c4185ec902dcf9c14ccf5f46e892f779c59255dbd81f`, computed difficulty 0.0161; and 19:09:52 UTC, nonce 253703, hash `000001fea736abe4f426e2707b612e8d7545d7ae862258806994d94fb6713bfd`, difficulty 0.0020. Evidence: `logs/LIVE_RUN_2026-11-21_muse.txt` (the client prints SHARE ACCEPTED only on the pool's `result: true`). Check the arithmetic: each hash against the difficulty-1 target, and the hash counts against the stated rates.
4. **Sizing claims.** sky130 synthesis with the real liberty: iterative core 9,241 cells / 82,721.84 µm²; full design 183,814 µm² ≈ 64% of TinyTapeout's 8×2-tile maximum (the only TT size it fits; the pipelined core does not fit). Log: `logs/yosys_sky130_2026-11-20.txt`.
5. **Hygiene.** Confirm the tree contains no wallet, seed, or key material (the `wallet/` directory is gitignored and has never been committed; the payout address in the host scripts is public stratum information for a throwaway wallet).

## Part 2 — Cook list (your cloud, your branch)

1. **The hardening run Ember's sandbox cannot do.** `tt-submission/` holds a prepared TinyTapeout project (`tt_um_spoon_sha256`, serial 960-bit load, elaborates cleanly). Ember's sandbox has LibreLane 3.0.17 and the sky130A PDK but no obtainable OpenROAD binary (no Docker/Nix there). If your environment can run LibreLane/OpenROAD: harden the project, and report the resulting die area, achieved clock (STA), DRC/LVS status, and whether the GDS passes TinyTapeout's precheck expectations. This is the single highest-value cook: it converts "fits on paper" into a submittable layout.
2. **Adder-architecture experiment.** The iterative core's rounds use naive adders. Prototype a compressor-tree (carry-save) round datapath on your branch, synthesize against the same sky130 liberty, and report area and critical-path deltas versus the 82,721.84 µm² baseline. Simulation must still pass the FIPS vectors and the genesis test before any number is reported.
3. **Gate-level simulation / equivalence** — only if Ember's results (watch for `logs/GLS_2026-11-21_muse.txt` and `logs/EQUIV_2026-11-21_muse.txt` on main) have not landed by the time you cook; otherwise verify hers instead of duplicating.

## Part 3 — Hard constraints

- **No purchases, no submissions.** No TinyTapeout shuttle submission, no orders, no paid services — the owner's explicit override for a specific purchase is the only exception, and you don't have one. (Context: the 8×2 sky130 submission is a ~€2,035 + VAT save-up goal the owner is funding slowly toward the May 2027 shuttle, two years after his May 13, 2025 termination — readiness, not submission, is the current standard.)
- **Keys are out of scope.** Never request, generate, or handle wallet seeds or private keys. The throwaway address is public; that is all you need.
- **Label your work.** Files you author carry your own marker (e.g. `_codex`), never `_muse`. Do not edit Ember's logs or the handoff's verified-state entries; append your own dated sections and say what you ran.
- **Report discrepancies, don't repair them silently.** If a claim in Part 1 fails verification, the failure is the deliverable: state which claim, the evidence, and the reproduction.
