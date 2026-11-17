#!/usr/bin/env python3
"""run_local_test.py — end-to-end local loop test for the stratum client.
_muse — written 2026-11-17.

Starts the mock pool on a throwaway port, runs the client against it for
exactly one share, and reports PASS only if the mock's own validation
accepted the share and the client exited cleanly. Everything is local;
no real pool, no real address — the username is a dummy string.
"""
import subprocess, sys, time, socket

PORT = 33339
ROOT = __file__.rsplit("/", 2)[0]


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return True
        except OSError:
            time.sleep(0.2)
    return False


def main():
    server = subprocess.Popen(
        [sys.executable, f"{ROOT}/host/mock_stratum_server.py",
         "--port", str(PORT), "--difficulty", "0.0001"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        if not wait_for_port(PORT):
            print("FAIL: mock pool never started"); return 1
        client = subprocess.run(
            [sys.executable, f"{ROOT}/host/stratum_miner.py",
             "--host", "127.0.0.1", "--port", str(PORT),
             "--user", "throwaway.spoon", "--pass", "x",
             "--shares", "1", "--max-seconds", "120"],
            capture_output=True, text=True, timeout=180)
        print("--- client output ---")
        print(client.stdout)
        if client.returncode != 0:
            print(f"FAIL: client exited {client.returncode}\n{client.stderr}")
            return 1
    finally:
        server.terminate()
        try:
            out, _ = server.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill(); out, _ = server.communicate()
    print("--- mock pool output ---")
    print(out)
    if "SUBMIT ACCEPTED" in out and "SHARE ACCEPTED #1" in client.stdout:
        print("LOCAL LOOP TEST: PASS — one share, validated by the pool oracle")
        return 0
    print("LOCAL LOOP TEST: FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
