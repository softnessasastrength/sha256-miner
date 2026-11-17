# sha256-miner

A hand-built Bitcoin mining core in Verilog — Branden's own design, built to
see if he can pull it off. Not a business. CPU mining was profitable once;
this is the opposite of that era, and that is rather the point.

**Status: private until there are numbers.** The repository stays private
until the design produces benchmark figures worth showing.

## Design

- `rtl/sha256_core.v` — iterative SHA-256 compression core (FIPS 180-4):
  one 512-bit block per run, 64 rounds, one round per clock, message
  schedule expanded on the fly from a 16-word sliding window. Padding is
  the caller's job; the core eats raw blocks and a chaining value.
- `tb/tb_sha256_core.v` — testbench against the standard vectors:
  `"abc"`, the empty message, and the 56-byte NIST message (which also
  exercises two-block chaining).

## Run the simulation

```sh
make sim        # needs Icarus Verilog (iverilog + vvp)
```

## Roadmap

1. **Iterative core, verified in simulation.** ✔ Done 2026-11-17 — all
   three FIPS vectors pass (see the simulation record below).
2. Double-SHA-256 wrapper; verify against a known mined block header.
   ✔ Done 2026-11-17 — the genesis block reproduces exactly.
3. Nonce-search wrapper + a host stratum client driving the simulated
   core, aimed at **one accepted share** from the real network under the
   owner's old mining address: proof, recorded in a pool's books, that
   this machine contributed a unit of work. ← we are here
4. Unrolled / pipelined datapath: one hash per clock per pipeline.
5. Parallel pipelines sized to a real FPGA board; first hardware numbers.
6. Stretch: a TinyTapeout shuttle run — the core in actual silicon.

## Simulation record

2026-11-17, Icarus Verilog 12.0, `make sim`:

```
PASS abc       ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
PASS empty     e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
PASS nist-56B  248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1
ALL 3 TESTS PASSED
```

Same day, the double-hash wrapper (`rtl/sha256d_core.v`), same flow:

```
PASS genesis-block     6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000
PASS synthetic-header  852c98044fb00507122ff63bda7b529566348fc204f72b00dff1afd7b40501e4
ALL 2 TESTS PASSED
```

The genesis digest is in internal byte order; reversed, it is the famous
`000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f` —
Satoshi's block, reproduced by this core, in this sandbox.

## Hardware

- `docs/BOARD_PROPOSAL_v1_muse.md` — **SPOON-1**, the proposed board: a
  Lattice ECP5 FPGA + ESP32-S3 host, designed from the start to live
  inside a dead cable box (the warmth is the camouflage). Proposal only —
  no schematic or layout exists yet, and the path to five boards is
  spelled out in the document.

## Honest numbers, stated in advance

- The iterative core does one hash per 64 clocks: at 100 MHz that is
  ~1.6 MH/s. Correctness first; speed is a later milestone.
- A pipelined core does one hash per clock: a few hundred MH/s per
  pipeline on a mid-range FPGA. Reaching even a few GH/s means several
  pipelines on a serious board. That is the achievement bar the owner set,
  and it is a real one.
- Nothing here will ever be profitable. A modern ASIC does ~200 TH/s.
  This machine's yield is that it exists and is understood end to end.

_muse-assisted project; RTL authored with Ember, directed by Branden._
