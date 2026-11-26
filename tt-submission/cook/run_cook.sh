#!/usr/bin/env bash
# run_cook.sh — sha256-miner TinyTapeout closure cook _muse (2026-11-26)
#
# Runs the full LibreLane hardening flow for tt_um_spoon_sha256 with the
# window-redesign core, the official 8x2 outline, a 35 ns clock constraint,
# jumper-only antenna repair and congestion-aware global routing
# (config_cook_muse.json, this directory).
#
# RUN THIS ON A DOCKER/NIX HOST (e.g. the owner's Dell G5 SE). Ember's
# sandbox has no obtainable OpenROAD binary and cannot run it.
# Nothing here purchases or submits anything: it hardens locally and
# leaves the run directory + logs on disk for inspection.
#
# Usage:  ./run_cook.sh            (from this directory)
# Logs:   cook/logs/cook-<timestamp>.log  (full tee of the run)
# Output: LibreLane run directory printed at the end (runs/<tag>/).

set -u
cd "$(dirname "$0")"
CONFIG="$PWD/config_cook_muse.json"
mkdir -p logs
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$PWD/logs/cook-$STAMP.log"
TAG="closure-cook-$STAMP"

echo "=== sha256-miner closure cook — $STAMP ===" | tee "$LOG"
echo "config: $CONFIG" | tee -a "$LOG"
echo "design: tt_um_spoon_sha256 (window core, DIE_AREA 0 0 1378.16 225.76, CLOCK_PERIOD 35)" | tee -a "$LOG"

run_librelane() {
    if command -v librelane >/dev/null 2>&1; then
        echo "route: librelane on PATH" | tee -a "$LOG"
        librelane --pdk sky130A --run-tag "$TAG" "$CONFIG" 2>&1 | tee -a "$LOG"
        return "${PIPESTATUS[0]}"
    elif python3 -c "import librelane" >/dev/null 2>&1; then
        echo "route: python3 -m librelane" | tee -a "$LOG"
        python3 -m librelane --pdk sky130A --run-tag "$TAG" "$CONFIG" 2>&1 | tee -a "$LOG"
        return "${PIPESTATUS[0]}"
    elif command -v docker >/dev/null 2>&1; then
        echo "route: docker (ghcr.io/librelane/librelane:latest)" | tee -a "$LOG"
        echo "NOTE: if the image name/tag differs in the host's LibreLane" | tee -a "$LOG"
        echo "install docs, adjust this one line — the config is the cook." | tee -a "$LOG"
        docker run --rm -v "$PWD/..":/work -w /work/cook \
            ghcr.io/librelane/librelane:latest \
            librelane --pdk sky130A --run-tag "$TAG" /work/cook/config_cook_muse.json \
            2>&1 | tee -a "$LOG"
        return "${PIPESTATUS[0]}"
    else
        echo "ERROR: no LibreLane route found (no librelane binary, no" | tee -a "$LOG"
        echo "python librelane module, no docker). Install LibreLane 3.x" | tee -a "$LOG"
        echo "(Nix or Docker route per its docs) plus the sky130A PDK" | tee -a "$LOG"
        echo "(volare), then re-run. Nothing was executed." | tee -a "$LOG"
        return 127
    fi
}

run_librelane
RC=$?
echo "=== cook exit code: $RC ===" | tee -a "$LOG"
echo "full log: $LOG" | tee -a "$LOG"
if [ -d "../runs/$TAG" ]; then
    echo "run dir: tt-submission/runs/$TAG" | tee -a "$LOG"
    echo "verdict files to read: final/gds/*.gds, reports/, metrics" | tee -a "$LOG"
fi
echo "Report the run EXACTLY as it lands: final overflow, antenna and" | tee -a "$LOG"
echo "setup/hold violation counts, DRC/LVS status. No GDS = say so." | tee -a "$LOG"
exit "$RC"
