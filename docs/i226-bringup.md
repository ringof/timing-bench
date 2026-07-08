# i226 PPS-injection bring-up (Stage 3 runbook)

Prep and test plan for feeding the F9T hardware PPS into an Intel **i226** NIC's
PHC (PTP Hardware Clock) via an SDP EXTTS channel, then serving it as a
GPS-disciplined **PTP grandmaster** with `ptp4l`. This is the end-to-end
PPS-vs-PHC assessment and the "how good is our GM" number.

This is Stage 3 of `docs/00-plan.md` (§3 and the Stage-3 checklist).

> **Status: NOT hardware-validated.** The i226 card and the timeSync breakout
> are not yet installed. Everything below is a forward-looking runbook derived
> from documentation and prior planning — treat every step as an *unvalidated
> guess* until the hardware is present and a real reading confirms it. Nothing
> here should be read as "confirmed" or "done." Interface names (`enp3s0` is a
> placeholder), SDP pin/channel indices, and `clockClass`/`clockAccuracy`
> values in particular are to be **confirmed on the bench**, not trusted as-is.

Skeleton config files live in `config/i226/` (`ts2phc.conf`, `ptp4l.conf`,
`chrony.conf`), each carrying the same `<CONFIRM>` placeholders as the blocks
below. Do not run them before confirming those values on hardware.

## What's in scope

- **Now (no hardware needed):** install the host-side toolchain so the box is
  ready the day the card arrives.
- **When the card + breakout arrive:** verify → wire → discipline → inject →
  serve, one gated step at a time, each confirmed by an observed reading before
  the next.

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

### testptp — get it on hand

`testptp` is what confirms which SDP the F9T PPS lands on. It's not always
packaged; it lives in the kernel selftests tree.

```bash
which testptp          # Option A: sometimes shipped with linuxptp / kernel tools

# Option B: build from kernel selftests source (single file)
#   grab testptp.c matching `uname -r`, then:
#   gcc -o testptp testptp.c -lrt
```

Grab `testptp.c` from the kernel tree matching `uname -r`; it builds in seconds.

## When the card + breakout arrive

Each step gated on an observed reading before moving on (per CLAUDE.md).

### 1. Verify the i226 and its PHC

```bash
lspci | grep -i i226
ethtool -i <iface>        # confirm driver = igc
ethtool -T <iface>        # confirm PHC + HW timestamping capabilities
```

Want to see `hardware-transmit`, `hardware-receive`, `hardware-raw-clock`, and
a PTP Hardware Clock index. Record the actual interface name — `enp3s0` in the
config skeletons is a **placeholder**; use what the box reports.

### 2. Wire the F9T PPS into an SDP pin

Route the **ZED-F9T-20B** TIMEPULSE output to one of the i226 SDP header pins.
The i226 SDPs are 3.3 V tolerant and F9T TIMEPULSE is 3.3 V, so a direct
connection usually works (a series resistor is cheap insurance); level-shift if
the header turns out to be different logic. Common shared GND. **Note which
physical header pin maps to which SDP number** from the card's header docs —
this is board-specific and must be read off the actual hardware.

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
testptp -e                                   # find the live EXTTS pin index first
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

- [ ] Real interface name (not `enp3s0`).
- [ ] `ethtool -T` output: PHC index + timestamping caps.
- [ ] Kernel version vs. `igc` SDP/EXTTS support; HWE kernel needed?
- [ ] Which physical SDP header pin the vendor routed, and its driver
      `pin_index` / `channel` (`testptp -e`, `dmesg | grep igc`).
- [ ] `/dev/ppsN` device node for the routed PPS.
- [ ] `clockClass` / `clockAccuracy` that match the actual locked state.
- [ ] Target PTP profile (default vs. AES67 / SMPTE 2110) — affects
      `ptp4l.conf` domain/priorities/dscp.
