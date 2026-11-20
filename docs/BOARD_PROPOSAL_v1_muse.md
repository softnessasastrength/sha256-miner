# SPOON-1 — Board Proposal v1

_muse — 2026-11-17. PROPOSAL ONLY. This document is the design brief for a
board, not a fabrication package: no schematic, layout, or Gerbers exist yet,
and nothing here should be sent to a manufacturer as-is. What stands between
this page and five physical boards is listed in §10._

## 1. The board in one paragraph

SPOON-1 is a small desk miner built around Branden's own Verilog SHA-256
core: a Lattice ECP5 FPGA does the hashing, an ESP32-S3 module runs
everything else (Wi-Fi, stratum client, dashboard, fan and thermal
supervision), and the whole assembly is designed from the start to live
inside the shell of a dead cable box — because a cable box is *supposed* to
sit there warm and ignored, which makes it the finest enclosure ever mass
produced. Artisanal bitcoin mining: hand-built core, hand-placed board,
hiding in plain sight.

## 2. Enclosure doctrine — the cable box

Owner's specification, adopted verbatim as a design requirement:

- The board must fit the interior of a common dead cable box / DVR shell
  (target outline 150 × 110 mm; measure the actual donor before layout).
- Thermal design is inherited from the original tenant: cable-box silicon
  was passively cooled against the chassis and vent slots, which is why the
  boxes run warm. SPOON-1's FPGA heatsink couples to the metal top cover
  where the donor has one. The warmth is not a side effect to hide; it is
  the camouflage working.
- Light discipline: no display on the deployed unit, exactly one dim status
  LED, aligned to the donor's original front-panel light pipe where
  possible. A cable box with a hashrate readout is a failed cable box.
- Power: reuse the donor's external 12 V brick where it provides one.
  To any observer, the box is plugged in because it is a cable box.
- The bench/debug variant (same PCB) may populate the OLED header and run
  lid-off. Deployment is a configuration, not a different board.

## 3. Block diagram

```
                 12 V (donor brick)
                      |
        +-------------+--------------+
        |             |              |
   1.1 V buck     5 V buck       (fan header)
   (FPGA core)    3.3 V LDO
        |             |
   +----v-----+  SPI  +-----v--------+
   |  ECP5    <------->  ESP32-S3    |---- Wi-Fi ----> stratum pool
   |  FPGA    |       |  module      |
   |  SHA-256 |  I2C  +--+------+----+
   |  cores   |       |  |      |
   +--+---^---+   temp  OLED   USB-C (console/flashing)
      |   |       sensor (bench
   config 25 MHz        only)
   flash  xtal
```

## 4. Hashing engine — Lattice ECP5

**Part: LFE5U-85F (381-ball BGA), with the LFE5U-45F as a same-family
cost-down option (footprint compatibility to be confirmed at schematic
time).**

Why this part, in order of importance:

1. **The toolchain is fully open** (Yosys + nextpnr + Project Trellis).
   No licence server, no 30 GB vendor install — synthesis and place-and-
   route can cook in a small sandbox, slow and steady, and every number
   the project publishes can be reproduced by anyone.
2. It is genuinely affordable in singles (tens of dollars, not hundreds),
   and has historically been stocked by LCSC for assembly.
3. ~84k LUTs is enough room for one fully pipelined double-SHA-256
   datapath plus control, or a fleet of iterative cores — both of the
   project's architectures fit in the same silicon.

**Performance — stated honestly, in advance of synthesis numbers:**
a pipelined core on this class of part is expected in the ~150–250 MH/s
region; the iterative fleet trades area for simplicity and lands lower.
**This board does not promise GH/s.** GH/s remains the project-level
stretch goal (bigger silicon, later board). SPOON-1's job is first
hardware, real numbers, and a core with its owner's name on it, running.

## 5. Host controller — ESP32-S3

ESP32-S3-WROOM-1 module (pre-certified RF, castellation mounting — kind to
assembly). Duties, modelled openly on the Bitaxe architecture:

- Wi-Fi station; stratum v1 client; job assembly and nonce-range
  distribution to the FPGA over SPI.
- Web dashboard (hashrate, temperature, uptime, best difficulty — the
  vanity metrics that are the actual product).
- Thermal supervision: reads the board temperature sensor, drives the fan
  header PWM, throttles the FPGA clock before it ever throttles itself.
- USB-C native console/flashing; OTA firmware updates.

## 6. Power tree

| Rail | Feeds | Budget | Proposed source |
|---|---|---|---|
| 12 V in | everything | ≤ 25 W wall | donor cable-box brick, 5.5 × 2.1 mm barrel |
| 1.1 V | ECP5 core | 10 A class | integrated power module (layout sanity for v1) |
| 2.5 V / 3.3 V | ECP5 I/O banks, flash, sensor | 1 A | small sync buck from 12 V |
| 3.3 V | ESP32-S3 module | 0.5 A peaks | LDO from 5 V rail |
| 5 V | fan header, OLED header | 0.5 A | small sync buck from 12 V |

Sequencing and supervision are handled in the schematic phase; the ECP5's
requirements are conventional and documented in its family datasheet.

## 7. Clocking and configuration

- 25 MHz crystal reference; ECP5 PLL generates the core clock
  (100–200 MHz target, set by what synthesis and thermals allow — the
  number will be measured, not assumed).
- Configuration from SPI NOR flash (W25Q128 class, 128 Mbit — room for
  two bitstream images: known-good + experimental).
- JTAG header (unpopulated pads acceptable) for bench bring-up.

## 8. PCB specification

| Item | Proposal |
|---|---|
| Outline | 150 × 110 mm (confirm against donor chassis before layout) |
| Layers | 6 (BGA escape + a real power plane; 4 is possible and miserable) |
| Finish | ENIG; colour: black, obviously |
| Mounting | M3 holes at corners + mid-edge, matching common chassis standoffs |
| Fab/assembly | JLCPCB or PCBWay, qty 5, PCBA for FPGA + module + passives |

## 9. Bill of materials — headline items

_Rough single-unit prices, late-2026 ballparks from memory of distributor
listings — verify every line at design time; nothing here is a quote._

| Item | Part | Est. |
|---|---|---|
| FPGA | Lattice LFE5U-85F-8BG381 | ~$40 |
| Host | ESP32-S3-WROOM-1 module | ~$7 |
| Config flash | Winbond W25Q128JV | ~$2 |
| Core power | 1.1 V / 10 A power module | ~$12 |
| Aux rails | 2× small bucks + LDO | ~$4 |
| Temp sensor | TMP117 or equiv. I2C | ~$2 |
| Crystal, fan header, USB-C, barrel, LED, passives | — | ~$12 |
| PCB (6-layer, qty 5 share) | — | ~$12 |
| Assembly (PCBA share, qty 5) | — | ~$35–60 |

**Estimated landed cost: roughly $125–170 per board in a run of five.**
The FPGA and assembly dominate; both shrink fast at quantity, and neither
matters, because this was never the profitable branch of the family tree.

## 10. Path from this proposal to five little bastards

1. Owner picks a donor cable box; measure its interior and standoffs.
2. Schematic capture (KiCad), ERC clean.
3. Synthesis checkpoint: the Verilog core must produce real utilisation
   and timing numbers for the ECP5-85 before layout money is spent.
4. Layout, DRC clean, heatsink/cover coupling checked against the donor.
5. Gerber + BOM + placement export; fab quote at qty 5 (blank and PCBA).
6. Owner's explicit go before any order — as always, the proposal being
   ready is not the purchase being approved.
7. Bring-up: JTAG first, one core, low clock. Then the lid goes on, and
   it is a cable box.

## 11. Open questions and risks

- BGA-381 escape on 6 layers is routine for the fab houses named, but it
  is the step most likely to add a board spin. Budget emotionally for v1.1.
- ECP5 pricing/availability moves around; if the 85F spikes, the 45F
  fallback halves the fleet size and keeps the project alive.
- Stratum firmware is real software work (weeks of evenings, not a
  weekend). The FPGA is the soul of the project; the ESP32 is its job.
- In a sealed donor box, sustained wattage is capped by the original
  vents. If the numbers demand it, the core clock comes down until the
  box is merely warm — a cable box that is hot is a cable box that gets
  unplugged by somebody's spouse, and operational security is thermal.

_muse-assisted design proposal; directed by Branden. Not an offer, not a
fabrication package, not investment advice — a spoon, drawn to scale._

---

## Addendum — 2026-11-20: the swappable-compute requirement

**Owner's requirement, in his words:** "when we go to design the actual
physical chip can we make them pin grid array so that as we iterate I can
just put new chips in the device." Recorded as a standing design
requirement for SPOON-1 and any ASIC descendant: **the compute element
must be swappable — iteration means dropping a new chip into the same
device, not rebuilding the device.** The package named (PGA) is assessed
below; the requirement behind it is adopted in full.

### What the shuttle world actually delivers (checked 2026-11-20)

- TinyTapeout's own PCB specification states: "we expect all TT chips to
  be in **QFN**" — the ASIC arrives soldered to a **breakout board**,
  which plugs into a demo board / motherboard precisely so the user
  never has to solder a bare ASIC (tinytapeout.com/specs/pcb/, fetched
  2026-11-20). Efabless shuttles follow the same QFN pattern.
- **PGA is not a shuttle offering.** Pin Grid Array is a legacy
  through-hole CPU package (hundreds of pins, socket the size of a
  coaster). No TinyTapeout/Efabless run delivers it, and no modern
  foundry shuttle packages a small die in it.

### PGA's fit for this design, factually

- The mining core's whole external interface is ~24 signals at
  TinyTapeout scale, and SPI + clock + reset + power on a custom board —
  a few dozen connections at most. A PGA's hundreds of pins would run
  >90% empty: the package would be an order of magnitude larger than
  the die's needs, through-hole (fighting the low-profile cable-box
  doctrine of §2), and sourced from legacy/niche stock at legacy prices.

### The routes that DO deliver the requirement

1. **The carrier/module pattern — which is TinyTapeout's own answer.**
   The compute element lives on a small daughterboard; the motherboard
   keeps power, host, and enclosure. TT already ships exactly this: die
   on a breakout, breakout plugs into the board. An ASIC iteration
   literally drops into the same device.
2. **Socketed QFN/BGA** (clamshell / ZIF test-and-burn-in sockets):
   exist and work on a bench, but they are costly, tall, and not
   designed as a permanent in-product socket — a bring-up tool, not
   the product answer.
3. **For the FPGA board, swap-by-reflash in place.** The LFE5U-85F in
   §4 is a 381-ball BGA — soldered, and BGA sockets are impractical at
   product level (cost, height, signal integrity at core-clock speeds).
   But an FPGA doesn't need physical swapping to iterate: §7 already
   specifies a 128 Mbit config flash holding **two bitstream images
   (known-good + experimental)**. A new core is a reflash, in place,
   in seconds. When a genuinely different FPGA is wanted, route 1
   applies to it too: put the FPGA on a module (the commercial ECP5
   module pattern) and treat the module as the swappable unit.

### Recommendation — how SPOON-1 honours the requirement

- **Adopt "swappable compute" as the requirement; PGA is noted as the
  owner's first instinct for the package, not adopted** (unavailable
  from shuttles, wrong size class for this pin count).
- v1 FPGA board: BGA soldered down for signal integrity and cost;
  **dual-image reflash is the iteration mechanism** (already in §7).
- The board's mechanical/electrical design shall define the hashing
  engine as a **module boundary** from the start (power + SPI + clock +
  reset across one connector), so a v2 — or the TinyTapeout ASIC on its
  carrier — swaps into the same cable box without a motherboard
  redesign. Decision point: schematic phase (§10, steps 2–3).
- If a TinyTapeout ASIC version is ever taped out, it arrives on its
  breakout carrier by design; the motherboard gets the matching socket
  footprint, and chip iteration becomes exactly what the owner asked
  for: open box, swap chip, close box.

_Proposal documentation only — no purchase, no order, no fabrication
commitment. _muse addendum, 2026-11-20._
