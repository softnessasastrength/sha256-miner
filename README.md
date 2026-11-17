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

1. **Iterative core, verified in simulation.** ← we are here
2. Double-SHA-256 wrapper + nonce counter; verify against a known mined
   block header (the genesis block is the obvious witness).
3. Unrolled / pipelined datapath: one hash per clock per pipeline.
4. Parallel pipelines sized to a real FPGA board; first hardware numbers.
5. Stretch: a TinyTapeout shuttle run — the core in actual silicon.

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
