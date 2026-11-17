#!/usr/bin/env python3
"""run_fake_world.py — the full dress rehearsal, everything fake.
_muse — written 2026-11-17. Directed by Branden Algozino.

Starts the fake pool in chain mode and the stratum client running the
SIM engine — Branden's actual Verilog, simulated, chunked — and lets it
cook until the core finds a fake BLOCK. The block lands in
build/fakechain.json: a fake ledger entry, honestly labelled, recording
real proof-of-work computed by the owner's own gates.

Fake address, fake pool, fake chain. Real hashes.

Usage: python3 host/run_fake_world.py [--max-minutes 720]
Re-running continues the same fake chain where it left off.
"""
import argparse, json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = 33341
CHAIN = os.path.join(ROOT, "build", "fakechain.json")
CLIENT_LOG = os.path.join(ROOT, "build", "fake_world_client.log")


def chain_tip_height():
    try:
        with open(CHAIN) as f:
            return json.load(f)["blocks"][-1]["height"]
    except Exception:
        return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-minutes", type=int, default=720)
    args = ap.parse_args()
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)

    pool = subprocess.Popen(
        [sys.executable, f"{ROOT}/host/mock_stratum_server.py",
         "--port", str(PORT), "--difficulty", "0.00001",
         "--block-difficulty", "0.00006", "--chain-file", CHAIN],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    # The pool creates/loads the chain file at startup; only once it
    # exists do we know the height we are starting from. (Genesis is
    # height 0 and is nobody's mined block.)
    for _ in range(30):
        start_height = chain_tip_height()
        if start_height >= 0:
            break
        time.sleep(0.5)
    logf = open(CLIENT_LOG, "w")
    client = subprocess.Popen(
        [sys.executable, f"{ROOT}/host/stratum_miner.py",
         "--host", "127.0.0.1", "--port", str(PORT),
         "--user", "dressrehearsal.spoon", "--pass", "x",
         "--engine", "sim", "--chunk", "2048",
         "--shares", "1000000", "--max-seconds", str(args.max_minutes * 60)],
        stdout=logf, stderr=subprocess.STDOUT, text=True)
    print(f"fake world running: pool on :{PORT}, sim engine cooking, "
          f"chain tip at height {start_height}; client log: {CLIENT_LOG}",
          flush=True)
    started = time.time()
    try:
        while time.time() - started < args.max_minutes * 60:
            time.sleep(10)
            height = chain_tip_height()
            if height > start_height and height >= 1:
                with open(CHAIN) as f:
                    block = json.load(f)["blocks"][-1]
                shares = 0
                try:
                    with open(CLIENT_LOG) as f:
                        shares = sum(1 for l in f if "SHARE ACCEPTED" in l)
                except OSError:
                    pass
                print(f"FAKE BLOCK MINED BY THE CORE: {json.dumps(block)}",
                      flush=True)
                print(f"shares accepted on the way: {shares}; "
                      f"elapsed: {(time.time() - started) / 60:.1f} minutes",
                      flush=True)
                return 0
            if client.poll() is not None:
                print(f"client exited early with {client.returncode}; "
                      f"see {CLIENT_LOG}", flush=True)
                return 1
        print(f"no block within {args.max_minutes} minutes; the chain "
              f"persists in {CHAIN} and a re-run continues it", flush=True)
        return 2
    finally:
        client.terminate(); pool.terminate()
        logf.close()


if __name__ == "__main__":
    sys.exit(main())
