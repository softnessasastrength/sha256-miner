#!/usr/bin/env python3
"""mock_stratum_server.py — a local, honest-oracle Stratum v1 pool for tests.
_muse — written 2026-11-17. Directed by Branden Algozino.

Scope, stated plainly: this mock validates the PROTOCOL FLOW and the
PROOF-OF-WORK MATH. It rebuilds the header from the submitted fields,
recomputes the double-SHA-256, and checks it against the difficulty it
issued. It does not validate the coinbase as a real transaction — the
coinb1/coinb2 chunks are well-formed filler. A real pool is the final
exam; this is the mock test that proves the client can sit it.

Usage: python3 mock_stratum_server.py --port 33330 --difficulty 0.0001
"""
import argparse, hashlib, json, socket, struct, threading

DIFF1_TARGET = 0x00000000FFFF0000000000000000000000000000000000000000000000000000
EXTRANONCE1 = "08000002"
EN2_SIZE = 4
JOB = {
    "job_id": "spoon-job-1",
    # Fabricated but fixed job material (deterministic across runs).
    "prevhash": hashlib.sha256(b"spoon prevhash").hexdigest(),
    "coinb1": "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff2002080002",
    "coinb2": "ffffffff0100f2052a010000001976a914" + "00" * 20 + "88ac00000000",
    "merkle_branch": [hashlib.sha256(b"spoon branch 1").hexdigest(),
                      hashlib.sha256(b"spoon branch 2").hexdigest()],
    "version": "20000000",
    "nbits": "1d00ffff",
    "ntime": "6553f100",
}


def sha256d(b: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()


def validate_share(params, difficulty):
    _user, job_id, en2_hex, ntime_hex, nonce_hex = params
    if job_id != JOB["job_id"]:
        return False, "unknown job"
    coinbase = bytes.fromhex(JOB["coinb1"] + EXTRANONCE1 + en2_hex + JOB["coinb2"])
    root = sha256d(coinbase)
    for step in JOB["merkle_branch"]:
        root = sha256d(root + bytes.fromhex(step))
    prev = bytes.fromhex(JOB["prevhash"])
    prev_swapped = b"".join(prev[i:i + 4][::-1] for i in range(0, 32, 4))
    header = (struct.pack("<I", int(JOB["version"], 16)) + prev_swapped + root
              + struct.pack("<I", int(ntime_hex, 16))
              + struct.pack("<I", int(JOB["nbits"], 16))
              + struct.pack("<I", int(nonce_hex, 16)))
    digest = sha256d(header)
    target = int(DIFF1_TARGET / difficulty)
    ok = int.from_bytes(digest, "little") <= target
    return ok, ("ok" if ok else "hash above target")


def handle(conn, difficulty):
    buf = b""
    authorized = False
    while True:
        while b"\n" not in buf:
            chunk = conn.recv(65536)
            if not chunk:
                return
            buf += chunk
        line, buf = buf.split(b"\n", 1)
        if not line.strip():
            continue
        msg = json.loads(line)
        method, mid = msg.get("method"), msg.get("id")
        if method == "mining.subscribe":
            reply = {"id": mid, "result": [[["mining.set_difficulty", "1"],
                                             ["mining.notify", "1"]],
                                            EXTRANONCE1, EN2_SIZE], "error": None}
            conn.sendall((json.dumps(reply) + "\n").encode())
        elif method == "mining.authorize":
            authorized = True
            conn.sendall((json.dumps({"id": mid, "result": True, "error": None}) + "\n").encode())
            conn.sendall((json.dumps({"id": None, "method": "mining.set_difficulty",
                                       "params": [difficulty]}) + "\n").encode())
            notify = {"id": None, "method": "mining.notify",
                      "params": [JOB["job_id"], JOB["prevhash"], JOB["coinb1"],
                                 JOB["coinb2"], JOB["merkle_branch"], JOB["version"],
                                 JOB["nbits"], JOB["ntime"], True]}
            conn.sendall((json.dumps(notify) + "\n").encode())
        elif method == "mining.submit" and authorized:
            ok, why = validate_share(msg["params"], difficulty)
            print(f"SUBMIT {'ACCEPTED' if ok else 'REJECTED'} ({why}) "
                  f"params={msg['params']}", flush=True)
            conn.sendall((json.dumps({"id": mid, "result": ok,
                                       "error": None if ok else [21, why, None]}) + "\n").encode())
        else:
            conn.sendall((json.dumps({"id": mid, "result": None,
                                       "error": [20, "unknown method", None]}) + "\n").encode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=33330)
    ap.add_argument("--difficulty", type=float, default=0.0001)
    args = ap.parse_args()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(1)
    print(f"mock pool listening on 127.0.0.1:{args.port} difficulty={args.difficulty}",
          flush=True)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn, args.difficulty), daemon=True).start()


if __name__ == "__main__":
    main()
