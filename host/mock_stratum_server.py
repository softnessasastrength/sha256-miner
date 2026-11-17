#!/usr/bin/env python3
"""mock_stratum_server.py — a local, honest-oracle Stratum v1 pool.
_muse — written 2026-11-17, chain mode added the same day.
Directed by Branden Algozino.

Scope, stated plainly: this mock validates the PROTOCOL FLOW and the
PROOF-OF-WORK MATH. It rebuilds the header from the submitted fields,
recomputes the double-SHA-256, and checks it against the difficulty it
issued. It does not validate the coinbase as a real transaction — the
coinb1/coinb2 chunks are well-formed filler. A real pool is the final
exam; this is the mock test that proves the client can sit it.

Chain mode (--block-difficulty > 0): the pool also keeps a FAKE chain.
A share whose hash also beats the block target becomes a block: it is
appended to the chain file as a ledger entry, and a fresh job goes out
with the new tip as prevhash. Everything is fake, labelled fake, and
local — a dress rehearsal for one real share.

Usage: python3 mock_stratum_server.py --port 33330 --difficulty 0.0001 \
           [--block-difficulty 0.00006 --chain-file build/fakechain.json]
"""
import argparse, hashlib, json, os, socket, struct, threading, time

DIFF1_TARGET = 0x00000000FFFF0000000000000000000000000000000000000000000000000000
EXTRANONCE1 = "08000002"
EN2_SIZE = 4
COINB1 = "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff2002080002"
COINB2 = "ffffffff0100f2052a010000001976a914" + "00" * 20 + "88ac00000000"
BRANCH = [hashlib.sha256(b"spoon branch 1").hexdigest(),
          hashlib.sha256(b"spoon branch 2").hexdigest()]
VERSION, NBITS, NTIME = "20000000", "1d00ffff", "6553f100"


def sha256d(b: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()


class FakeChain:
    """A tiny fake blockchain: a list of block records in a JSON file."""

    def __init__(self, path):
        self.path = path
        self.job_n = 0
        if path and os.path.exists(path):
            with open(path) as f:
                self.blocks = json.load(f)["blocks"]
        else:
            genesis_hash = sha256d(b"spoon fake genesis block")[::-1].hex()
            self.blocks = [{"height": 0, "prev": "00" * 32, "hash": genesis_hash,
                            "nonce": 0, "miner": "satoshi-of-the-dress-rehearsal",
                            "ts": 1231006505, "fake": True}]
            self._save()

    def _save(self):
        if self.path:
            with open(self.path, "w") as f:
                json.dump({"chain": "FAKE — local dress rehearsal only",
                           "blocks": self.blocks}, f, indent=1)

    @property
    def tip(self):
        return self.blocks[-1]

    def next_job(self):
        self.job_n += 1
        return {"job_id": f"spoon-job-{self.job_n}", "prevhash": self.tip["hash"],
                "coinb1": COINB1, "coinb2": COINB2, "merkle_branch": BRANCH,
                "version": VERSION, "nbits": NBITS, "ntime": NTIME}

    def add_block(self, hash_display_hex, nonce, en2_hex, user):
        block = {"height": self.tip["height"] + 1, "prev": self.tip["hash"],
                 "hash": hash_display_hex, "nonce": nonce,
                 "extranonce2": en2_hex, "miner": user,
                 "ts": int(time.time()), "fake": True}
        self.blocks.append(block)
        self._save()
        return block


def rebuild_header(job, en2_hex, ntime_hex, nonce_hex):
    coinbase = bytes.fromhex(job["coinb1"] + EXTRANONCE1 + en2_hex + job["coinb2"])
    root = sha256d(coinbase)
    for step in job["merkle_branch"]:
        root = sha256d(root + bytes.fromhex(step))
    prev = bytes.fromhex(job["prevhash"])
    prev_swapped = b"".join(prev[i:i + 4][::-1] for i in range(0, 32, 4))
    return (struct.pack("<I", int(job["version"], 16)) + prev_swapped + root
            + struct.pack("<I", int(ntime_hex, 16))
            + struct.pack("<I", int(job["nbits"], 16))
            + struct.pack("<I", int(nonce_hex, 16)))


def send_notify(conn, job):
    notify = {"id": None, "method": "mining.notify",
              "params": [job["job_id"], job["prevhash"], job["coinb1"],
                         job["coinb2"], job["merkle_branch"], job["version"],
                         job["nbits"], job["ntime"], True]}
    conn.sendall((json.dumps(notify) + "\n").encode())


def handle(conn, difficulty, chain, block_difficulty):
    buf = b""
    authorized = False
    job = chain.next_job() if chain else {
        "job_id": "spoon-job-1", "prevhash": hashlib.sha256(b"spoon prevhash").hexdigest(),
        "coinb1": COINB1, "coinb2": COINB2, "merkle_branch": BRANCH,
        "version": VERSION, "nbits": NBITS, "ntime": NTIME}
    shares = 0
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
            send_notify(conn, job)
        elif method == "mining.submit" and authorized:
            user, job_id, en2_hex, ntime_hex, nonce_hex = msg["params"]
            if job_id != job["job_id"]:
                ok, why, digest = False, "unknown job", None
            else:
                digest = sha256d(rebuild_header(job, en2_hex, ntime_hex, nonce_hex))
                share_target = int(DIFF1_TARGET / difficulty)
                ok = int.from_bytes(digest, "little") <= share_target
                why = "ok" if ok else "hash above target"
            print(f"SUBMIT {'ACCEPTED' if ok else 'REJECTED'} ({why}) "
                  f"params={msg['params']}", flush=True)
            conn.sendall((json.dumps({"id": mid, "result": ok,
                                       "error": None if ok else [21, why, None]}) + "\n").encode())
            if ok:
                shares += 1
                if chain and block_difficulty > 0:
                    block_target = int(DIFF1_TARGET / block_difficulty)
                    if int.from_bytes(digest, "little") <= block_target:
                        block = chain.add_block(digest[::-1].hex(),
                                                int(nonce_hex, 16), en2_hex, user)
                        print(f"*** FAKE BLOCK FOUND *** height={block['height']} "
                              f"hash={block['hash']} nonce={block['nonce']} "
                              f"miner={user} (shares so far: {shares})", flush=True)
                        job = chain.next_job()
                        send_notify(conn, job)
        else:
            conn.sendall((json.dumps({"id": mid, "result": None,
                                       "error": [20, "unknown method", None]}) + "\n").encode())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=33330)
    ap.add_argument("--difficulty", type=float, default=0.0001)
    ap.add_argument("--block-difficulty", type=float, default=0.0,
                    help="chain mode: shares beating this difficulty become fake blocks")
    ap.add_argument("--chain-file", default=None)
    args = ap.parse_args()
    chain = FakeChain(args.chain_file) if args.block_difficulty > 0 else None
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", args.port))
    srv.listen(1)
    print(f"mock pool listening on 127.0.0.1:{args.port} difficulty={args.difficulty}"
          + (f" chain mode: block_difficulty={args.block_difficulty}, "
             f"tip height={chain.tip['height']}" if chain else ""), flush=True)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle,
                         args=(conn, args.difficulty, chain, args.block_difficulty),
                         daemon=True).start()


if __name__ == "__main__":
    main()
