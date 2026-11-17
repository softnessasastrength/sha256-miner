#!/usr/bin/env python3
"""stratum_miner.py — a minimal Stratum v1 client for the sha256-miner project.
_muse — written 2026-11-17. Directed by Branden Algozino.

Speaks to a pool, takes jobs, and searches nonces with a software
double-SHA-256 engine (hashlib). The software engine exists to prove the
plumbing end to end; the project's own Verilog core is the engine that
matters, and this client's job-assembly code is written so the header it
builds for the software engine is byte-identical to the template the RTL
search consumes.

Usage:
    python3 stratum_miner.py --host 127.0.0.1 --port 33330 \
        --user ADDRESS.worker --pass x --shares 1
Exits 0 after --shares accepted shares.
"""
import argparse, hashlib, json, os, socket, struct, subprocess, sys, time

DIFF1_TARGET = 0x00000000FFFF0000000000000000000000000000000000000000000000000000
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JOB_TB = os.path.join(REPO_ROOT, "build", "tb_job_search.vvp")


def sha256d(b: bytes) -> bytes:
    return hashlib.sha256(hashlib.sha256(b).digest()).digest()


def merkle_root(coinbase_hash: bytes, branch: list) -> bytes:
    root = coinbase_hash
    for step in branch:
        root = sha256d(root + bytes.fromhex(step))
    return root


def build_header(job, extranonce1: str, extranonce2: int, en2_size: int,
                 nonce: int) -> bytes:
    en2 = extranonce2.to_bytes(en2_size, "big").hex()
    coinbase = bytes.fromhex(job["coinb1"] + extranonce1 + en2 + job["coinb2"])
    root = merkle_root(sha256d(coinbase), job["merkle_branch"])
    # Stratum conventions (as in cpuminer): version/nbits/ntime arrive as
    # big-endian hex and are packed little-endian; prevhash is word-swapped.
    prev = bytes.fromhex(job["prevhash"])
    prev_swapped = b"".join(prev[i:i + 4][::-1] for i in range(0, 32, 4))
    header = (
        struct.pack("<I", int(job["version"], 16))
        + prev_swapped
        + root
        + struct.pack("<I", int(job["ntime"], 16))
        + struct.pack("<I", int(job["nbits"], 16))
        + struct.pack("<I", nonce)
    )
    assert len(header) == 80
    return header


def software_search(pool, job, target, en2):
    """Hashlib engine: fast, and not the point — it proves plumbing."""
    for nonce in range(0x100000000):
        header = build_header(job, pool.extranonce1, en2, pool.en2_size, nonce)
        digest = sha256d(header)
        if int.from_bytes(digest, "little") <= target:
            return nonce, digest
    return None, None


def ensure_job_tb():
    """Compile the plusargs job-search testbench if missing or stale."""
    srcs = [os.path.join(REPO_ROOT, "tb", "tb_job_search.v"),
            os.path.join(REPO_ROOT, "rtl", "sha256_core.v"),
            os.path.join(REPO_ROOT, "rtl", "sha256d_core.v"),
            os.path.join(REPO_ROOT, "rtl", "sha256d_search.v")]
    if os.path.exists(JOB_TB) and \
            os.path.getmtime(JOB_TB) > max(os.path.getmtime(s) for s in srcs):
        return
    os.makedirs(os.path.dirname(JOB_TB), exist_ok=True)
    subprocess.run(["iverilog", "-g2005", "-o", JOB_TB] + srcs,
                   check=True, cwd=REPO_ROOT)
    print("compiled the job-search testbench", flush=True)


def sim_search(pool, job, target, en2, chunk):
    """The real engine: Branden's Verilog, simulated, fed in chunks.

    The chunker splits the nonce space into `chunk`-sized pieces and runs
    one vvp invocation per piece against tb_job_search. Slow — a few
    thousand hashes a second on a good day — and entirely the point: the
    hashes that come back were computed by the owner's own gates.
    Returns (nonce, digest, hashes_done) or (None, None, hashes_done).
    """
    ensure_job_tb()
    template = build_header(job, pool.extranonce1, en2, pool.en2_size, 0)
    total = 0
    nonce = 0
    started = time.time()
    while nonce <= 0xFFFFFFFF:
        limit = min(nonce + chunk - 1, 0xFFFFFFFF)
        out = subprocess.run(
            ["vvp", JOB_TB, f"+tmpl={template.hex()}", f"+target={target:064x}",
             f"+n0={nonce}", f"+n1={limit}"],
            capture_output=True, text=True, timeout=900, cwd=REPO_ROOT)
        lines = [l for l in out.stdout.splitlines() if l.startswith("RESULT")]
        if not lines:
            raise RuntimeError(f"sim produced no result: {out.stdout} {out.stderr}")
        parts = dict(kv.split("=", 1) for kv in lines[0].split()[1:] if "=" in kv)
        total += int(parts.get("hashes", 0))
        rate = total / max(1e-9, time.time() - started)
        print(f"  chunk @{nonce}: {total} hashes this segment, "
              f"{rate:.0f} H/s (sim)", flush=True)
        if "FOUND" in lines[0]:
            return int(parts["nonce"]), bytes.fromhex(parts["digest"]), total
        if limit == 0xFFFFFFFF:
            break
        nonce = limit + 1
    return None, None, total


class Stratum:
    def __init__(self, host, port):
        self.sock = socket.create_connection((host, port), timeout=30)
        self.buf = b""
        self.next_id = 1
        self.difficulty = 1.0
        self.job = None
        self.extranonce1 = ""
        self.en2_size = 4
        self.accepted = 0
        self.pending = {}

    def send(self, method, params):
        mid = self.next_id; self.next_id += 1
        msg = {"id": mid, "method": method, "params": params}
        self.sock.sendall((json.dumps(msg) + "\n").encode())
        return mid

    def readline(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("pool closed the connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def _process(self, msg):
        """Fold one pool message into local state; return it if it is a
        response, else None."""
        if msg.get("method") == "mining.notify":
            p = msg["params"]
            self.job = {"job_id": p[0], "prevhash": p[1], "coinb1": p[2],
                        "coinb2": p[3], "merkle_branch": p[4],
                        "version": p[5], "nbits": p[6], "ntime": p[7],
                        "clean": p[8]}
            return None
        if msg.get("method") == "mining.set_difficulty":
            self.difficulty = float(msg["params"][0])
            return None
        return msg

    def pump_until(self, want_id=None, timeout=20):
        """Process messages until the response to want_id arrives (or a
        job shows up, when want_id is None). Returns the response dict."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            if want_id is None and self.job is not None:
                return None
            self.sock.settimeout(max(1, deadline - time.time()))
            try:
                msg = self.readline()
            except (socket.timeout, TimeoutError):
                break
            resp = self._process(msg)
            if resp is not None:
                if want_id is not None and resp.get("id") == want_id:
                    return resp
                self.pending[resp.get("id")] = resp
        if want_id is None and self.job is not None:
            return None
        raise TimeoutError("timed out waiting for the pool")

    def drain(self, seconds=1):
        """Process whatever the pool sends for a moment — used after an
        accepted share so a fresh job (e.g. after a found block) replaces
        the stale one before the next search segment starts."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            self.sock.settimeout(max(0.1, deadline - time.time()))
            try:
                msg = self.readline()
            except (socket.timeout, TimeoutError):
                break
            resp = self._process(msg)
            if resp is not None:
                self.pending[resp.get("id")] = resp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--user", required=True)
    ap.add_argument("--pass", dest="password", default="x")
    ap.add_argument("--shares", type=int, default=1)
    ap.add_argument("--max-seconds", type=int, default=600)
    ap.add_argument("--engine", choices=["software", "sim"], default="software")
    ap.add_argument("--chunk", type=int, default=2048,
                    help="nonce chunk size for the sim engine")
    args = ap.parse_args()

    pool = Stratum(args.host, args.port)
    sub_id = pool.send("mining.subscribe", ["sha256-miner/0.1"])
    resp = pool.pump_until(sub_id)
    _subs, pool.extranonce1, pool.en2_size = resp["result"]
    auth_id = pool.send("mining.authorize", [args.user, args.password])
    resp = pool.pump_until(auth_id)
    if resp.get("result") is not True:
        print("AUTHORIZE FAILED", resp, flush=True); return 1
    print(f"connected: extranonce1={pool.extranonce1} en2_size={pool.en2_size}",
          flush=True)

    started = time.time()
    extranonce2 = 0
    while pool.accepted < args.shares:
        if time.time() - started > args.max_seconds:
            print("TIMEOUT before reaching the share goal", flush=True); return 2
        if pool.job is None:
            pool.pump_until(None, timeout=30); continue
        job = pool.job
        target = int(DIFF1_TARGET / pool.difficulty)
        en2 = extranonce2; extranonce2 += 1
        if args.engine == "sim":
            nonce, digest, _hashes = sim_search(pool, job, target, en2, args.chunk)
        else:
            nonce, digest = software_search(pool, job, target, en2)
        if nonce is None:
            continue
        # The client stays honest even about its own engines.
        assert int.from_bytes(digest, "little") <= target
        sub = pool.send("mining.submit", [
            args.user, job["job_id"],
            en2.to_bytes(pool.en2_size, "big").hex(),
            job["ntime"], "%08x" % nonce])
        resp = pool.pump_until(sub)
        if resp.get("result") is True:
            pool.accepted += 1
            print(f"SHARE ACCEPTED #{pool.accepted} job={job['job_id']} "
                  f"nonce={nonce} hash={digest[::-1].hex()}", flush=True)
            pool.drain(1)
        else:
            print(f"SHARE REJECTED {resp}", flush=True); return 3
    print(f"DONE: {pool.accepted} share(s) accepted", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
