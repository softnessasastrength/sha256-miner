#!/bin/bash
# run_live_bcmonster_muse.sh — the §3.1 live-share run, SWITCHED to a
# wire-verified low-difficulty pool. _muse — written 2026-11-21.
#
# WHY THIS POOL: public-pool.io DOCUMENTED a 0.001 minimum difficulty but
# ASSIGNED 100,000 on the wire (mining.set_difficulty, captured verbatim
# 2026-11-21) — a ~577-year expected wait at bridge speed. The owner ruled
# 2026-11-21: "let's do one that allows low diff." BCMonster's BTC solo
# lottery port was verified ON THE WIRE before this switch (evidence:
# logs/POOL_PROBE_2026-11-21_muse.txt): subscribe answered, FIRST
# mining.set_difficulty = 0.001, authorize result true, real mainnet
# mining.notify jobs (coinbase height 977002, /BCMonster/ tag).
#
# Pool: bcmonster.com:9999 (BTC, always-solo lottery port), user
# <address>.spoon, password x (exactly as probed).
# Engine: the Verilator model of the project's own sha256d_search
# (~23.2 kH/s measured live). Expected time to first share at difficulty
# 0.001: 2^32 * 0.001 / 23200 ≈ 185 s (Poisson).
#
# The supervisor loop restarts the client every <=15 min so it always
# works a fresh job (shares are memoryless; restarting loses nothing).
# The address below is PUBLIC information (it is the stratum username);
# the wallet's keys never leave ~/workspace/sha256-miner/wallet/.
#
# NOTE: the public-pool supervisor (run_live_public_pool.sh, setsid
# session from the 2026-11-21 16:30 UTC relaunch) could not be signalled
# from the switching agent's session (per-session pid namespace — its
# processes are not visible there). It keeps running in parallel until a
# session that owns it kills it; it costs CPU share only.
set -u
cd "$(dirname "$0")/.."
ADDR="bc1qyv3amdpzz5lghwrkm50nhwa4y3cg6eldx0yvnt"
LOG="logs/LIVE_RUN_$(date -u +%Y-%m-%d)_muse.txt"
echo "live run started $(date -u) pool=bcmonster.com:9999 user=${ADDR}.spoon (switched from public-pool.io:21496 — wire-verified diff 0.001)" >> "$LOG"
while true; do
    python3 host/stratum_miner_vl.py \
        --host bcmonster.com --port 9999 \
        --user "${ADDR}.spoon" --pass x \
        --shares 1 --max-seconds 900 --engine sim \
        >> "$LOG" 2>&1
    rc=$?
    echo "client exited rc=$rc at $(date -u)" >> "$LOG"
    [ "$rc" -eq 0 ] && break      # share accepted — done
    [ "$rc" -eq 3 ] && break      # share rejected — stop and look
    sleep 5                        # timeout/other: relaunch on a fresh job
done
echo "live run finished $(date -u)" >> "$LOG"
