# Closure cook package — tt_um_spoon_sha256 (window design)

_muse — packaged 2026-11-26, the same day the owner adopted the window
patch into mainline ("Adopt the window patch, then cook", 2026-11-26).
Adoption evidence: `logs/WINDOW_ADOPTION_2026-11-26_muse.txt`.

## What this is

Everything needed to run the closure-focused LibreLane hardening run that
neither kitchen has finished yet. Codex's 2026-11-21 window-design run got
past antenna repair into detailed routing (TritonRoute 90% of the initial
pass) — the furthest any run has gone — but produced no completed route,
no GDS, no DRC/LVS, no precheck. This package aims the next run at exactly
those blockers:

- **Design:** the adopted window core (`../src/sha256_core.v` — block
  loaded into the schedule window, no separate block register), in the
  serial TT wrapper (`../src/project.v`).
- **Outline:** official TinyTapeout 8x2, `DIE_AREA 0 0 1378.16 225.76`
  (corrects the old 1400 × 300 figure, which exceeded the outline in both
  dimensions; the local config `../src/config_local_muse.json` is fixed
  too).
- **Clock constraint:** 35 ns (the constraint Codex's A/B comparison used;
  the window design's pre-route min period was 12.34 ns, so 35 ns leaves
  the run to fight congestion and antennas, not setup timing).
- **Antenna legalisation:** `GRT_REPAIR_ANTENNAS` on, and detailed-route
  repair **jumper-only** (`DRT_ANTENNA_REPAIR_JUMPER_ONLY`) — Codex's
  start config, the one that got past the DPL-0036 diode-legalisation
  failure that killed both original-design candidates. Repair iterations
  raised to 10 (default 3), margin 10%.
- **Congestion:** `GRT_ALLOW_CONGESTION` on; placement density 74%
  (the window design placed at 74.4% utilisation on this outline in
  Codex's run, vs 80.0% for the original).
- Everything else (margins, PDN pitch, CTS, linter) carries over from the
  project's known-good local config.

Variable names were checked against the LibreLane 3.0.17 source in
Ember's sandbox (`DRT_ANTENNA_REPAIR_JUMPER_ONLY` is the current name;
the old `DIODE_INSERTION_STRATEGY` is removed in LibreLane ≥ 2.0).

## The one command (Dell G5 SE, or any Docker/Nix host)

```
git clone https://github.com/softnessasastrength/sha256-miner.git && cd sha256-miner/tt-submission/cook && chmod +x run_cook.sh && ./run_cook.sh
```

Prerequisites on the host: LibreLane 3.x reachable one of the three ways
`run_cook.sh` probes (binary on PATH, python module, or Docker), and the
sky130A PDK (volare). The script tees the whole run to
`logs/cook-<timestamp>.log` in this directory and prints the LibreLane run
directory at the end.

**This sandbox cannot run it** — no OpenROAD binary is obtainable here
(verified repeatedly since 2026-11-20; LibreLane and the PDK are present,
the OpenROAD executable is not). The run itself is pending execution on
the G5 as of packaging.

## Reading the verdict

Report the run exactly as it lands — no rounding a partial run into a
pass:

- Did detailed routing **complete**? Final overflow figure.
- Antenna violations remaining after repair; setup/hold violation counts
  from the final STA.
- GDS present under the run dir's `final/gds/`? DRC / LVS / precheck
  status, each stated separately.
- If it stalls: the step, the error verbatim (e.g. DPL-0036), and the
  last checkpoint numbers.

## Hard constraints (unchanged)

No shuttle purchase, no TinyTapeout submission, no account creation —
readiness is the bar, and any slot decision is the owner's alone. No
wallet material is involved in this flow at all.
