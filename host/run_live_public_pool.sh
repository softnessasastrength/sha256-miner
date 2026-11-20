#!/bin/bash
# run_live_public_pool.sh — the §3.1 live-share run, ready to launch.
# _muse — written 2026-11-20.
#
# STATUS: NOT YET RUN against the real pool. From the Muse sandbox,
# outbound raw TCP is denied by the user's permission setting
# (Muse settings -> Permissions -> Direct network protocols ->
# other_tcp is set to Deny; the egress interceptor states this verbatim).
# The moment that is set to Ask/Allow — or this script is run on any
# ordinary machine (e.g. the G5 SE) — the run below is the whole job.
#
# Pool: public-pool.io:21496 (open-source solo pool; documented minimum
# share difficulty 0.001; public stats by address at web.public-pool.io).
# Engine: the Verilator model of the project's own sha256d_search,
# verified against the Icarus testbench vectors and end-to-end against
# the local mock-pool oracle (share accepted, nonce 775144 @ diff 1e-4,
# 24,495 H/s through the client).
#
# Expected time to first share at difficulty 0.001 and ~24.5 kH/s:
#   2^32 * 0.001 / 24495 ≈ 175 s (Poisson — median ~2 min, 95th pct ~9 min).
#
# The supervisor loop restarts the client every <=15 min so it always
# works a fresh job (shares are memoryless; restarting loses nothing).
# The address below is PUBLIC information (it is the stratum username);
# the wallet's keys never leave ~/workspace/sha256-miner/wallet/.
set -u
cd "$(dirname "$0")/.."
ADDR="bc1qyv3amdpzz5lghwrkm50nhwa4y3cg6eldx0yvnt"
LOG="logs/LIVE_RUN_$(date -u +%Y-%m-%d)_muse.txt"
echo "live run started $(date -u) pool=public-pool.io:21496 user=${ADDR}.spoon" >> "$LOG"
while true; do
    python3 host/stratum_miner_vl.py \
        --host public-pool.io --port 21496 \
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
