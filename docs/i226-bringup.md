# i226 PPS-injection bring-up (Stage 3 runbook)

Prep and test plan for feeding the F9T hardware PPS into an Intel **i226** NIC's
PHC (PTP Hardware Clock) via an SDP EXTTS channel, then serving it as a
GPS-disciplined **PTP grandmaster** with `ptp4l`. This is the end-to-end
PPS-vs-PHC assessment and the "how good is our GM" number.

This is Stage 3 of `docs/00-plan.md` (§3 and the Stage-3 checklist).

> **Status: PPS→PHC validated (2026-07-10).** The i226 card is installed and the
> **full PPS-injection path works on the bench**: the F9T 1 PPS lands on SDP0,
> and `ts2phc` locks `/dev/ptp0` (enp3s0) to it — servo `s2`, steady-state
> offset ~±10 ns, freq ~+10 ppm (steps 1–5 below). What is **still unvalidated**
> is the *serving* side — chrony (system clock) and the `ptp4l` grandmaster
> (steps 6–7), including the `clockClass`/`clockAccuracy` values. Treat those as
> forward-looking guesses until a real reading confirms them.

Skeleton config files live in `config/i226/` (`ts2phc.conf`, `ptp4l.conf`,
`chrony.conf`), each carrying the same `<CONFIRM>` placeholders as the blocks
below. Do not run them before confirming those values on hardware.

## Confirmed against hardware — 2026-07-08

Driver / PHC side, on host `radio`. The i226 is a **full PCIe card** reporting
`03:00.0 … Intel I226-LM (rev 04)`; a **6-pin SDP header was soldered onto the
card** (Intel ships none) and a Timebeat U.FL PPS breakout (50 Ω-termination DIP
switches) mates to it. No PPS injected yet.

- Host toolchain installed: `linuxptp 4.0`, `pps-tools 1.0.2`, `ethtool`,
  `gpsd`/`gpsd-clients 3.25`, `chrony 4.5`, `build-essential`,
  `linux-headers-6.17.0-35`. `testptp` not installed (deferred — see note).
- `igc` driver in-tree; kernel **6.17.0-35-generic**.
- Interface **`enp3s0`**, driver `igc`, fw `2020:888d`, bus `0000:03:00.0`.
  Link DOWN (no cable — irrelevant to PHC work).
- `ethtool -T enp3s0`: `hardware-transmit`, `hardware-receive`,
  `hardware-raw-clock`; **PTP Hardware Clock: 0** → `/dev/ptp0`.
- `/sys/class/ptp/ptp0`: `clock_name f0b2b93551a9` (= enp3s0 MAC → ptp0 is this
  NIC's PHC); **2 EXTTS + 2 perout** channels; pins **SDP0–SDP3**, all `0 0`
  (unassigned). (`n_pins` scalar not published by this kernel; the `pins/`
  directory enumerates the pins.)

**Resolved:** the earlier I226-LM-vs-T1 worry — it's a PCIe card with the SDP
header soldered on, so the breakout attaches and driver-level EXTTS injection is
viable.

**Still open:**
- Which U.FL / SDP is the **PPS-in** (→ `ts2phc.pin_index` / `channel`).
  Timebeat's pinout wasn't retrievable (store/community pages 403). Determine it
  **empirically** — arm the EXTTS channels and see which SDP logs edges once the
  F9T pulse is on the PPS-in connector.
- **Software stack undecided:** Timebeat's sync daemon vs. linuxptp
  `ts2phc`/`ptp4l`. The Timebeat breakout's own config uses Timebeat "pin/index"
  semantics (index 0 = PPS-in); the `config/i226/` skeletons here assume
  linuxptp. Pick one before wiring config.

## What's in scope

- **Done (2026-07-08):** host toolchain installed; i226 card / PHC verified on
  the bench (see "Confirmed against hardware").
- **Remaining:** wire → discipline → inject → serve, one gated step at a time,
  each confirmed by an observed reading before the next.

## Prep now — install the toolchain

One-liner to install everything host-side:

```bash
sudo apt install linuxptp pps-tools ethtool gpsd gpsd-clients chrony \
  build-essential linux-headers-$(uname -r)
```

What each piece is for:

- **linuxptp** — the core. Provides `ptp4l` (PTP daemon / grandmaster),
  `phc2sys`, `pmc`, and **`ts2phc`** — the tool that reads the F9T PPS on the
  i226 SDP EXTTS channel and steers the PHC to it. This is the actual
  "feed PPS into the card" mechanism.
- **pps-tools** — `ppstest` and the PPS headers, for confirming PPS edges if
  PPS is also routed through the kernel PPS subsystem.
- **ethtool** — `ethtool -T <iface>` to confirm the i226's PHC and
  hardware-timestamping capabilities.
- **gpsd / gpsd-clients** — F9T NMEA/UBX reading and `ubxtool` (already used by
  this repo's collectors).
- **chrony** — disciplines the *system* clock from GPS. Keep this separate from
  the PHC path: chrony steers the OS clock (so logs/NMEA stay sane); `ts2phc`
  steers the NIC PHC from the same PPS. See the daemon-conflict warning below.
- **build-essential + linux-headers** — for building `testptp` from source and
  any other from-source needs.

### The igc driver — nothing to install

The i226 driver (`igc`) is in-kernel and mainline since ~5.x, so on a current
Ubuntu it is already present. Do **not** install Intel's out-of-tree `igc` —
mainline is better maintained for timing. The i226-T1 exposes SDP pins on a
header; the driver maps them as `SDP0..SDP3` extts/perout channels. Verify once
the card is in:

```bash
modinfo igc            # confirms the driver exists
uname -r               # note kernel version
```

SDP/EXTTS support is **kernel-version-dependent**. If on an older LTS kernel,
the HWE kernel may give better `igc` timing support. Decide that only after
seeing what `ethtool -T` and `testptp` actually report — do not assume.

### testptp — the first-light EXTTS probe (built 2026-07-10)

`ts2phc` sets the SDP pin function and consumes EXTTS edges itself, so the
*runtime* path (`ts2phc` → `ptp4l`) doesn't need `testptp`. Its value is
**`testptp -e`** — raw, read-only EXTTS edge capture in isolation from `ts2phc`
— which is the clean way to prove "the pulse is physically arriving on this SDP"
before touching the PHC. We built it to identify the PPS's SDP (step 4).

**Header-skew gotcha (important).** `testptp.c` compiles against the *userspace*
uapi header `/usr/include/linux/ptp_clock.h`, which ships in `linux-libc-dev` —
on Ubuntu 24.04 that is **6.8-based even under a 6.17 HWE kernel**. A newer
`testptp.c` (`master`, `v6.17`) references
`struct ptp_sys_offset_extended.clockid` (added after 6.8) and **fails to
compile**. Fix: fetch the `testptp.c` matching the **userspace headers (v6.8)**,
not the running kernel.

```bash
cd /tmp
curl -sSL -o testptp.c \
  https://raw.githubusercontent.com/torvalds/linux/v6.8/tools/testing/selftests/ptp/testptp.c
gcc -Wall -o testptp testptp.c -lrt && ls -l /tmp/testptp
```

Built in `/tmp` (not a repo artifact). If v6.8 still trips on a missing field,
drop to `v6.6`.

## Bring-up steps (card + breakout in hand)

Each step gated on an observed reading before moving on (per CLAUDE.md). Steps
1–5 are done (i226/PHC verified, pulse wired, F9T in timing mode, SDP0
identified, PHC locked to the PPS via ts2phc); steps 6 onward (chrony → ptp4l →
reduce) remain.

### 1. Verify the i226 and its PHC — DONE (2026-07-08)

```bash
lspci | grep -i i226
ethtool -i enp3s0         # driver = igc (confirmed)
ethtool -T enp3s0         # PHC + HW timestamping caps (confirmed)
cat /sys/class/ptp/ptp0/n_external_timestamps   # EXTTS channels: 2
ls /sys/class/ptp/ptp0/pins/                     # SDP0..SDP3
```

Confirmed on the bench: `enp3s0` (real name, not a placeholder), `/dev/ptp0`,
`hardware-transmit`/`-receive`/`-raw-clock`, 2 EXTTS + 2 perout, SDP0–3 free.
See "Confirmed against hardware — 2026-07-08" above for the full readout.

### 2. Wire the F9T PPS into an SDP pin

Hardware in hand: a **6-pin SDP header soldered onto the i226 PCIe card** with a
**Timebeat U.FL PPS breakout** attached (U.FL coax; 50 Ω-termination DIP
switches per connector). Route the **ZED-F9T-20B** TIMEPULSE output to the
breakout's **PPS-in** U.FL. The i226 SDPs are 3.3 V and F9T TIMEPULSE is 3.3 V,
so no level-shift; common shared GND.

**Gotcha — 50 Ω termination kills the pulse (confirmed 2026-07-10).** The
breakout's per-connector 50 Ω-termination DIP switch must be **OFF** for the
F9T. The F9T TIMEPULSE is a weak CMOS push-pull output and cannot drive a 50 Ω
load to ground (~66 mA at 3.3 V) — with termination ON the high level collapses
and the pulse dies (seen as the board's PPS LED going dark while connected).
With termination OFF the SDP is a hi-Z input and the pulse survives. 50 Ω
termination is for line-driver PPS sources, not a GPIO.

Timebeat's pinout wasn't retrievable, so which SDP the PPS-in maps to was
determined **empirically** (step 4): it is **SDP0**. F9T POL_TP1=1 → rising
edge.

### 3. Put the F9T in timing mode

The F9T needs stationary/timing mode with a surveyed-in position for sub-25 ns
PPS. **Use this repo's existing `ubxtool` path, not u-center:**
`config/f9t/apply-timing-config.sh` (and `docs/f9t-setup.md`) set the PPS grid
to GPS, enable UBX-TIM-TP / UBX-TIM-SVIN, and run the survey-in. The dry-run
params there are intentionally loose (100 m / 120 s); tighten
(`SVIN_ACC_LIMIT ~20000` = 2 m, longer `SVIN_MIN_DUR`) for the real pass after
antenna siting. Confirm `UBX-TIM-SVIN valid 1` before trusting the PPS.

### 4. Identify which SDP receives the PPS — DONE (2026-07-10, EXTTS loop check)

With the F9T locked and emitting (step 3) and the breakout's 50 Ω termination
**off** (step 2), arm each SDP as an EXTTS input and see which one logs edges.
Read-only — `testptp` does not steer the PHC; `/dev/ptp0` needs root.

```bash
for p in 0 1 2 3; do
  echo "== SDP$p (pin index $p) =="
  sudo timeout 5 /tmp/testptp -d /dev/ptp0 -i 0 -L $p,1 -e 3
done
```

`-L p,1` sets pin index `p` to EXTTS on channel 0 (`-i 0`); `-e 3` reads three
events; `timeout` bounds a silent pin. The SDP printing `event index 0 at
<sec>.<nsec>` lines ~1 s apart is the one the PPS-in maps to.

**Result:** the F9T pulse lands on **SDP0** (pin index 0). The events showed a
rising edge, a falling edge **100.0 ms** later (matches `LEN_LOCK_TP1`), then
the next rising edge **~1.00001 s** on — i.e. 1 PPS, 100 ms wide, with the PHC
free-running about **+10 ppm** (uncorrected; `ts2phc` pulls that out next).
SDP1–3 armed cleanly but saw no edges. → hardware-confirmed
`ts2phc.pin_index 0`, `ts2phc.channel 0`. (Polarity ends up `both`, not
`rising` — igc is both-edges-only; see the gotcha in step 5.)

### 5. Get PPS into the PHC (ts2phc) — DONE (2026-07-10)

**Path A — PPS on an SDP as EXTTS (recommended; keeps it on the NIC clock).**
`ts2phc` reads the rising PPS edge on the SDP EXTTS channel and steers the PHC
to it at hardware-timestamp resolution — no OS jitter in the path. Validated
config `config/i226/ts2phc.conf`:

```ini
[global]
use_syslog 0
first_step_threshold 0.00002
ts2phc.pulsewidth 100000000
[enp3s0]
ts2phc.extts_polarity both
ts2phc.pin_index 0
ts2phc.channel 0
```

Values must be **bare** — linuxptp's parser takes everything after the key as
the value, so an inline `#` comment gives "malformed value / failed to parse".
`pulsewidth` = the F9T 100 ms `LEN_LOCK_TP1`; `extts_polarity both` per the igc
gotcha below; `pin_index 0` = SDP0 (step 4).

```bash
sudo ts2phc -f config/i226/ts2phc.conf -s generic -c enp3s0 -m
```

Invocation notes — each one cost a debug cycle, so heed them:
- **`-f` is the config flag.** ts2phc's `-c` means "add a PHC *sink*", not a
  config file (`-c /path/to.conf` → "failed to open clock").
- **`-s generic`** = the reference is an external 1-PPS with no ToD (the F9T
  edge). Do **not** set `ts2phc.master 1` — that makes the NIC a PPS *generator*
  (perout output), the opposite of reading the pulse in.
- **`-c enp3s0`** names the sink: the same NIC's PHC, disciplined from its EXTTS.

**igc gotcha — `PTP_EXTTS_REQUEST2 failed: Operation not supported`.** igc
timestamps **both edges only**; it can't do rising-only, so the rising +
strict-flag `PTP_EXTTS_REQUEST2` that ts2phc sends for `extts_polarity rising`
is rejected (EOPNOTSUPP). Fix (per the linuxptp maintainer — a config change,
not a code patch): set `extts_polarity both` **and** set `ts2phc.pulsewidth` to
the real pulse width; ts2phc then requests both edges (which igc supports) and
uses the width to ignore the falling one. (testptp works throughout because it
uses the legacy flagless `PTP_EXTTS_REQUEST`.) No timing penalty: the rising
edge is still the hardware timestamp; the falling edge is dropped in software
after capture.

**Result:** PHC locked to the F9T PPS — servo `s2`, steady-state offset
**~±10 ns**, `freq ~+10 ppm` (matches the free-run measured via testptp in
step 4 — two independent methods agree). This offset is ts2phc's servo residual
(a self-report, like the F9T's qErr); a proper characterization (offset series +
ADEV, ideally vs. an independent clock) is the next capture, not this glimpse.

**Path B — discipline system clock (chrony) then push to PHC with `phc2sys`.**
Lower quality (routes through the CPU clock). Use only if EXTTS can't be made to
work. Not needed — Path A works.

### 6. Discipline the system clock (chrony, independent path)

chrony keeps the OS clock sane from the F9T NMEA + PPS, independently of the
PHC. Add these refclock lines to the host's `/etc/chrony/chrony.conf`
(skeleton: `config/i226/chrony.conf`):

```ini
refclock SHM 0 refid NMEA offset 0.0 precision 1e-3 poll 4 noselect
refclock PPS /dev/pps0 lock NMEA refid PPS prefer
```

`/dev/pps0` is a **placeholder** — depends on how PPS is routed (kernel
`pps-gpio` or SDP-derived).

### 7. Run the PTP grandmaster (ptp4l)

With the PHC locked to GPS, serve PTP. Skeleton: `config/i226/ptp4l.conf`:

```ini
[global]
clockClass 6             # <CONFIRM> GPS-locked GM (only once truly locked)
clockAccuracy 0x20       # <CONFIRM> within 100 ns
priority1 128
tx_timestamp_timeout 10
[enp3s0]                 # <CONFIRM> real interface
```

```bash
ptp4l -f config/i226/ptp4l.conf -i <iface> --step_threshold=1 -m
```

`clockClass 6` advertises a GPS-traceable grandmaster in BMCA. AES67 / SMPTE
2110 media profiles differ (domain / priorities / dscp) — that's a separate
decision, not baked in here.

### 8. Reduce & plot

Collector reads EXTTS timestamps → PHC-vs-PPS offset series → offset plot +
Allan deviation (the headline GM number). Extend collectors to scrape
`ptp4l -m` master offset / RMS for the served side. (Matches the Stage-3
checklist in `docs/00-plan.md`.)

## Service ordering & the daemon-conflict rule

Boot order that works: **gpsd → chrony → ts2phc → ptp4l**
(GPS up → system clock sane → PHC locked to GPS → serve).

Do **not** let `phc2sys` and `ts2phc` both steer the same PHC — they will
fight. With Path A, **`ts2phc` owns the PHC and `ptp4l` only reads it**:

- **`ts2phc`** disciplines the NIC PHC from the F9T PPS.
- **chrony** disciplines the OS system clock from GPS (independently).
- **`ptp4l`** serves the disciplined PHC as a PTP grandmaster.

Confirm only one writer per clock before running anything unattended.

## Sanity checks

```bash
ppstest /dev/pps0                    # PPS edges arriving
# watch ts2phc "-m": master offset should settle to tens of ns
pmc -u -b 0 'GET TIME_STATUS_NP'     # ptp4l master offset
```

## Open items to confirm on hardware

- [x] Real interface name — `enp3s0` (confirmed 2026-07-08).
- [x] `ethtool -T` output: PHC index 0 + hw tx/rx/raw-clock (confirmed).
- [x] `igc` SDP/EXTTS support on this kernel — 2 EXTTS + 2 perout, SDP0–3
      exposed on 6.17.0-35 (confirmed); no HWE kernel needed.
- [ ] Which U.FL / SDP the PPS-in maps to → `ts2phc.pin_index` / `channel`
      (determine empirically — arm EXTTS, watch which SDP logs edges).
- [ ] **Software stack:** Timebeat sync daemon vs. linuxptp `ts2phc`/`ptp4l`.
- [ ] F9T TIMEPULSE wired to breakout PPS-in and F9T locked/emitting.
- [ ] `/dev/ppsN` device node for the routed PPS.
- [ ] `clockClass` / `clockAccuracy` that match the actual locked state.
- [ ] Target PTP profile (default vs. AES67 / SMPTE 2110) — affects
      `ptp4l.conf` domain/priorities/dscp.
