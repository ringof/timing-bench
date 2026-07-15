# i226 PPS-injection bring-up (Stage 3 runbook)

Prep and test plan for feeding the F9T hardware PPS into an Intel **i226** NIC's
PHC (PTP Hardware Clock) via an SDP EXTTS channel, then serving it as a
GPS-disciplined **PTP grandmaster** with `ptp4l`. This is the end-to-end
PPS-vs-PHC assessment and the "how good is our GM" number.

This is Stage 3 of `docs/00-plan.md` (§3 and the Stage-3 checklist).

> **Status: full grandmaster chain up (2026-07-11).** F9T 1 PPS → SDP0 →
> `ts2phc` locks `/dev/ptp0` (~±10 ns, steps 1–5); system clock disciplined from
> the F9T via gpsd+chrony (~±1.5 ms, GPS preferred / NTP fallback, step 6);
> `ptp4l` serves the PHC as a GPS-locked grandmaster on TAI, advertising
> `clockClass 6` / `currentUtcOffset 37` (valid) / GPS (step 7, verified via
> `pmc`). The whole chain is **systemd-persistent — validated across a cold
> reboot** (all services auto-start, flags re-assert, PHC comes up on TAI).
> **Not yet done:** a PTP **client** — enp3s0 has no link/peer yet (the Pi5).

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
1–6 done, and the step-7 `ptp4l` grandmaster is up and verified (serving the TAI
PHC as a GPS-locked GM); what remains under step 7 is a PTP **client** (a link/
peer on enp3s0 — the Pi5) plus flag-persistence and reboot-TAI determinism.

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

### 6. Discipline the system clock (chrony via gpsd) — DONE (2026-07-11)

Option A: gpsd reads the F9T → in-band GPS time to SHM unit 0 → chrony refclock,
`prefer`red over the NTP pools. Keeps the OS clock GPS-traceable but **coarse
(~ms)** — the precise timing lives in the PHC (step 5), deliberately separate.
`prefer` buys traceability/independence, **not accuracy** (coarse in-band GPS ≈
internet NTP numerically). Validated files: `config/i226/chrony.conf` (drop-in)
+ `config/i226/gpsd.default`.

chrony drop-in → `/etc/chrony/conf.d/10-gps.conf` (main `chrony.conf` untouched):

```ini
refclock SHM 0 refid GPS precision 1e-3 offset 0.063 poll 4 prefer
```

gpsd → `/etc/default/gpsd`, then unmask + enable:

```ini
DEVICES="/dev/serial/by-id/usb-u-blox_AG_-_www.u-blox.com_u-blox_GNSS_receiver-if00"
GPSD_OPTIONS="-n"
USBAUTO="false"
```
```bash
sudo systemctl unmask gpsd.socket gpsd.service
sudo systemctl enable --now gpsd.socket gpsd.service   # enabled at boot; -n feeds SHM
sudo systemctl restart chrony
chronyc sources        # expect #* GPS, reach climbing, offset ~ms
```

Gotchas / notes (each cost time):
- **`-n` is mandatory.** chrony reads gpsd's SHM, which is *not* a gpsd client,
  so without `-n` a socket-activated gpsd never starts and SHM stays empty.
- **gpsd units may be `masked`** (masked earlier to keep gpsd off the F9T during
  raw-ubxtool / ts2phc work) — `systemctl unmask` first.
- **Calibrate the in-band latency.** Raw, GPS reads **+63 ms** off (a stable
  systematic); `offset 0.063` cancels it → ~±1.5 ms. Uncalibrated + `prefer`
  drags the clock 63 ms off and evicts NTP as falsetickers. chrony *subtracts*
  `offset` from the raw sample, so cancel a +63 ms lead with a **positive**
  `0.063` (a wrong sign ~doubles it).
- **Fallback is holdover-then-NTP, not instant.** With `prefer`, a stale GPS
  sample is held a long time (its dispersion grows only ~1 ppm, so ~hours to
  exceed the internet NTP's ~20 ms root distance) — the clock coasts on holdover
  (stays sane), then hands to NTP. A **reboot with gpsd down uses NTP
  immediately.** Delete the drop-in to disable GPS outright.
- **gpsd owns `/dev/ttyACM0`.** Stop gpsd (`sudo systemctl stop gpsd`) before raw
  `ubxtool` reconfig of the F9T.

**Result:** `#* GPS` preferred at **~±1.5 ms**, NTP pools as `^-` fallback,
persistent across reboots.

### 7. Run the PTP grandmaster (ptp4l) — GM side DONE (2026-07-11); client/link pending

**How absolute time is assembled (why steps 5 *and* 6 both exist).** PTP hands
out *absolute* time, which is two independent pieces glued together:
- **Which second it is** — needs only coarse accuracy (better than ±0.5 s). The
  GPS-disciplined **system clock (step 6, ~ms)** supplies this; a few ms of
  error doesn't change which second you're in.
- **Where in that second the tick falls** — needs ns. The **PPS via the PHC
  (step 5)** supplies this.

Glued together: system clock says `12:00:00.007` → the second is `12:00:00`;
PPS edge at `…00.000000002` → 2 ns into it; result `12:00:00.000000002`,
ns-absolute. The ms reference does **not** cap accuracy at ms — it only *names
the second*; the PPS provides the precision inside it. So step 6 is the
"name the second" half (not redundant), and **ptp4l's absolute-time source is
the PHC** — its second named by the system clock, its sub-second pinned to ns by
the PPS.

**Correctness check — is the PHC on the RIGHT second? — DONE.** PTP runs in
**TAI**, the system clock is **UTC** (TAI−UTC = 37 s). Verified with
`phc_ctl /dev/ptp0 get` vs `date -u`: the PHC reads **+37 s ahead of UTC**, i.e.
it is on **TAI** — the correct PTP timescale, **no step needed**. (Heads-up: the
`phc_ctl … cmp` sign reads the *opposite* way; trust the direct `get` epoch
comparison.) So the only action is to declare **`currentUtcOffset 37`** (done,
below) so clients resolve TAI→UTC. Caveat: the PHC is on TAI *this session* —
confirm it lands on TAI deterministically after a reboot (a to-do, not verified).

With the PHC on TAI, serve PTP. Validated config `config/i226/ptp4l.conf` (bare
values — inline `#` comments break the parser, same as ts2phc):

```ini
[global]
clockClass 6
clockAccuracy 0x21
utc_offset 37
timeSource 0x20
priority1 128
tx_timestamp_timeout 50
[enp3s0]
```

```bash
sudo ptp4l -f config/i226/ptp4l.conf -i enp3s0 -m
```

**Then assert the traceability flags** — ptp4l.conf can't set these; they default
to 0, which makes a client distrust the UTC offset and land on TAI (37 s off). A
runtime management SET (does **not** survive a ptp4l restart — re-run after each
start; for a service, `ExecStartPost`):

```bash
sudo pmc -u -b 0 'SET GRANDMASTER_SETTINGS_NP clockClass 6 clockAccuracy 0x21 \
  offsetScaledLogVariance 0xffff currentUtcOffset 37 leap61 0 leap59 0 \
  currentUtcOffsetValid 1 ptpTimescale 1 timeTraceable 1 frequencyTraceable 1 \
  timeSource 0x20'
sudo pmc -u -b 0 'GET TIME_PROPERTIES_DATA_SET'   # verify the flags read 1
```

**Result (2026-07-11):** ptp4l selected `/dev/ptp0`, assumed the grand master
role (identity `f0b2b9.fffe.3551a9`), and advertises `clockClass 6`,
`currentUtcOffset 37` + `Valid 1`, `timeTraceable 1`, `frequencyTraceable 1`,
`timeSource GPS (0x20)`, `ptpTimescale 1`. Confirmed via `pmc`.

**Persistence (systemd) — DONE (2026-07-14), validated across a cold reboot.**
gpsd + chrony were already persistent; the grandmaster chain now is too:
- `config/i226/ts2phc.service` — custom unit; disciplines the PHC at boot.
- `config/i226/ptp4l@enp3s0.override.conf` — drop-in on the shipped
  `ptp4l@.service`: `After=ts2phc.service` + `ExecStartPost` the flags helper.
- `config/i226/ptp4l-gm-settings.sh` — re-asserts the GM traceability flags on
  every start (they reset to 0 otherwise → client would land on TAI).

Install steps are in each file's header (configs → `/etc/linuxptp/`; `enable
--now`). **Reboot result:** gpsd/chrony/ts2phc/ptp4l all auto-started, the flags
came up `1`, and — answering the open question — **the PHC came up on TAI (+37 s)
deterministically** (igc initializes it there), so no TAI-set step is needed.

**Still open — the client.** `enp3s0` is `link down` (`port 1 … FAULTY`) with
nothing plugged in; the GM holds the role but can't announce until a client/
switch is cabled (then `FAULTY → MASTER`). **Pi5 is next:** check `ethtool -T
eth0` on the Pi5 (HW timestamping? the RP1 NIC may be SW-only), cable it to
`enp3s0`, run linuxptp slave + phc2sys/chrony.

A media profile (AES67 / SMPTE 2110) would change domain/priorities/dscp — a
separate decision, not baked in here.

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
