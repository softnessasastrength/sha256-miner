#!/bin/bash
# run_live_bcmonster_persistent_muse.sh — persistent lottery hunt on the
# wire-verified low-diff pool. _muse — written 2026-11-21.
#
# §3.1 COMPLETED 2026-11-21 19:08:38 UTC (SHARE ACCEPTED, job 05ef222f,
# nonce 11760654 — see logs/LIVE_RUN_2026-11-21_muse.txt). A second share
# followed 19:09:52 UTC. This wrapper keeps the worker hunting after the
# artifact run: each client pass hunts ONE share (the verified client,
# unmodified), then loops for the next. A REJECTED share (rc=3) still
# stops the loop cold — stop and look. Pool: bcmonster.com:9999 (BTC solo
# lottery port, wire-verified assigned difficulty 0.001 — evidence:
# logs/POOL_PROBE_2026-11-21_muse.txt). Expected ~3 min per share at
# ~24.5 kH/s (Poisson). Runs detached under setsid; kill the session to
# stop it.
set -u
cd "$(dirname "$0")/.."
ADDR="bc1qyv3amdpzz5lghwrkm50nhwa4y3cg6eldx0yvnt"
LOG="logs/LIVE_RUN_$(date -u +%Y-%m-%d)_muse.txt"
echo "persistent hunt started $(date -u) pool=bcmonster.com:9999 user=${ADDR}.spoon" >> "$LOG"
while true; do
    python3 host/stratum_miner_vl.py \
        --host bcmonster.com --port 9999 \
        --user "${ADDR}.spoon" --pass x \
        --shares 1 --max-seconds 900 --engine sim \
        >> "$LOG" 2>&1
    rc=$?
    echo "client exited rc=$rc at $(date -u)" >> "$LOG"
    [ "$rc" -eq 3 ] && break      # share rejected — stop and look
    sleep 5                        # accepted or timeout/other: hunt the next one
done
echo "persistent hunt stopped $(date -u)" >> "$LOG"
