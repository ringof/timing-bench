# i226 PPS-injection bring-up (Stage 3 runbook)

Prep and test plan for feeding the F9T hardware PPS into an Intel **i226** NIC's
PHC (PTP Hardware Clock) via an SDP EXTTS channel, then serving it as a
GPS-disciplined **PTP grandmaster** with `ptp4l`. This is the end-to-end
PPS-vs-PHC assessment and the "how good is our GM" number.

This is Stage 3 of `docs/00-plan.md` (§3 and the Stage-3 checklist).

> **Status: partially hardware-verified (2026-07-08).** The i226 card IS
> installed and the **driver / PHC side is confirmed on the bench** (see
> "Confirmed against hardware" below): interface `enp3s0`, PHC `/dev/ptp0`,
> 2 EXTTS + 2 perout channels, SDP0–3 exposed and free. What is **still
> unvalidated** is the PPS-injection path itself — the physical SDP↔PPS-in
> mapping, the `ts2phc` / `ptp4l` config, and the `clockClass`/`clockAccuracy`
> values. Treat those as forward-looking guesses until a real reading confirms
> them. No PPS has been injected yet.

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

### testptp — deferred, not needed for the runtime path

**Decision 2026-07-08: don't build it yet.** `ts2phc` sets the SDP pin function
and consumes the EXTTS edges itself, so the runtime path (`ts2phc` → `ptp4l`)
doesn't need `testptp`, and its capability/pin listing is already available from
sysfs (`/sys/class/ptp/ptp0/…`). Its one unique value is **`testptp -e`** — raw
EXTTS edge capture in isolation from `ts2phc` — which is a useful *first-light
debug probe* only: if `ts2phc` shows nothing, `testptp -e` distinguishes "no
pulse / wrong pin" (physical) from "pin arriving, `ts2phc` misconfigured".

If/when needed, it's one file, builds in seconds — grab `testptp.c` from the
kernel tree matching `uname -r` and `gcc -o testptp testptp.c -lrt`.
(`which testptp` on this box: not installed.)

## Bring-up steps (card + breakout in hand)

Each step gated on an observed reading before moving on (per CLAUDE.md). Step 1
is done; steps 2 onward remain.

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

**Which SDP the PPS-in maps to is not yet known** (Timebeat's pinout wasn't
retrievable). Rather than trust a datasheet, determine it **empirically** once
the pulse is on the connector: arm the EXTTS channels and see which of SDP0–3
starts logging edges. That SDP number becomes `ts2phc.pin_index` / `channel`
(step 4). F9T POL_TP1=1 → rising edge.

### 3. Put the F9T in timing mode

The F9T needs stationary/timing mode with a surveyed-in position for sub-25 ns
PPS. **Use this repo's existing `ubxtool` path, not u-center:**
`config/f9t/apply-timing-config.sh` (and `docs/f9t-setup.md`) set the PPS grid
to GPS, enable UBX-TIM-TP / UBX-TIM-SVIN, and run the survey-in. The dry-run
params there are intentionally loose (100 m / 120 s); tighten
(`SVIN_ACC_LIMIT ~20000` = 2 m, longer `SVIN_MIN_DUR`) for the real pass after
antenna siting. Confirm `UBX-TIM-SVIN valid 1` before trusting the PPS.

### 4. Get PPS into the PHC (the nanosecond part)

Two paths — pick based on how it's wired:

**Path A — PPS on an SDP as EXTTS (recommended; keeps it on the NIC clock).**
`ts2phc` reads the PPS edge on the SDP EXTTS channel and steers the PHC to it,
at hardware-timestamp resolution — no OS jitter in the path. This is what earns
"nanosecond accuracy." Skeleton: `config/i226/ts2phc.conf`:

```ini
[global]
use_syslog 1
first_step_threshold 0.00002
[enp3s0]                       # <CONFIRM> real interface
ts2phc.channel 0              # <CONFIRM> SDP EXTTS channel the PPS is on
ts2phc.extts_polarity rising  # F9T POL_TP1=1 (rising)
ts2phc.pin_index 0            # <CONFIRM> driver SDP pin index (testptp -e)
```

```bash
# ts2phc arms the SDP EXTTS itself; run it and watch the -m offset settle.
# (Only if edges don't show, build testptp and `testptp -e` to isolate physical
#  vs config — see the testptp note above.)
ts2phc -c config/i226/ts2phc.conf -s generic -m
```

**Path B — discipline system clock (chrony) then push to PHC with `phc2sys`.**
Lower quality (routes through the CPU clock). Use only if EXTTS can't be made to
work.

### 5. Discipline the system clock (chrony, independent path)

chrony keeps the OS clock sane from the F9T NMEA + PPS, independently of the
PHC. Add these refclock lines to the host's `/etc/chrony/chrony.conf`
(skeleton: `config/i226/chrony.conf`):

```ini
refclock SHM 0 refid NMEA offset 0.0 precision 1e-3 poll 4 noselect
refclock PPS /dev/pps0 lock NMEA refid PPS prefer
```

`/dev/pps0` is a **placeholder** — depends on how PPS is routed (kernel
`pps-gpio` or SDP-derived).

### 6. Run the PTP grandmaster (ptp4l)

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

### 7. Reduce & plot

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
