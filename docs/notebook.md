# Lab notebook

Dated entries, **newest on top**. Each entry: what was done, the capture file it
refers to (if any), and what the plot showed. Keep it terse and honest —
negative results are results.

---

## TEMPLATE (copy this block up top for each new entry)

### YYYY-MM-DD — short title
- **Setup:** F9T mode, survey-in state, what was connected.
- **Capture:** `data/YYYYMMDD-HHMMSS_<what>.log` (duration, rate).
- **Observed:** what the plots/numbers showed.
- **Next:** the one thing to do next.

---

### 2026-07-11 — Stage 3 characterized: 10.25 h ts2phc long run (PHC vs F9T PPS)
- **Setup:** i226 PHC (`/dev/ptp0`, enp3s0) disciplined from the F9T 1 PPS on
  SDP0 via `ts2phc` (`config/i226/ts2phc.conf`). 10.25 h unattended capture.
- **Capture:** `data/ts2phc_longrun_20260710-154402.log` — 36,915 lines @ 1 Hz.
  ts2phc held servo `s2` (locked) for all but the first sample: **zero relocks**
  over 10+ h; `.err` clean.
- **Reduce:** `reduce/parse_ts2phc.py` (drops pre-`s2` + 30-sample settle guard,
  gap/relock-aware) → `data/ts2phc_longrun.tsv` (`elapsed_s/offset_ns/freq_ppb`,
  36,884 kept). `reduce/allan.py --col offset_ns --ns` →
  `data/ts2phc_longrun.adev.tsv`. Plots: `plots/ts2phc_offset.gp` (offset+freq),
  `plots/adev.gp` (ADEV).
- **Observed:**
  - **Offset:** mean **0.03 ns**, **RMS 4.69 ns** — a flat ±10 ns band.
    (`out/ts2phc_offset.png`)
  - **ADEV:** clean **τ⁻¹ over 14 octaves**, 9.2e-9 @1 s → 5.0e-13 @16384 s;
    white-phase / quantization-limited, no floor. (`out/adev.png`)
  - **Freq:** non-monotonic **thermal** excursion, ~**0.9 ppm peak-to-peak**
    (hump → plateau ~+9775 ppb → sharp step to ~+10700 ppb with ~25-min
    oscillations in the last ~2 h) — a bare i226 XO, no TCXO, breathing with the
    room. The loop **absorbs** it: freq swings while offset stays flat.
    (`out/ts2phc_freq.png`)
  - **Transient:** a cluster of phase outliers (−66/−56/−43 ns) at t≈10.5–12 ks
    (~3 h in), no lock loss, quick recovery. **Cause: a robot vacuum jostled the
    bench** (on-site obs) — U.FL/coax mechanical sensitivity. Strong
    timing+mechanical correlation, not provable from the ts2phc log alone.
- **Learned:**
  - Disciplining works: the PHC tracks the PPS to **4.7 ns RMS / τ⁻¹** straight
    through a ~0.9 ppm thermal frequency swing (incl. a sharp step).
  - **Mechanically sensitive:** a passing robot vacuum = a −66 ns glitch.
    Strain-relief the U.FL/coax + antenna lead for clean runs; keep the vacuum
    away. The servo recovered gracefully (good robustness data point).
  - **Prediction miss (mine):** I expected a long-τ ADEV upturn from the drift.
    Wrong — ts2phc corrects the frequency so it never leaks into phase; ADEV
    stays τ⁻¹. Also mischaracterized the drift as +0.35 ppm monotonic (start-vs-
    tail); it's ~0.9 ppm non-monotonic thermal.
- **Boundary:** this is the **servo tracking residual** (PHC vs its own PPS
  reference), NOT absolute accuracy vs an independent clock. The F9T/GPS sets
  the real long-τ limit; that independent comparison is future work.
- **Artifacts:** config `config/i226/ts2phc.conf`; reduce
  `reduce/parse_ts2phc.py` + `reduce/allan.py`; plots `plots/ts2phc_offset.gp` +
  `plots/adev.gp`; data `data/ts2phc_longrun.tsv` + `.adev.tsv` (raw
  `data/ts2phc_longrun_20260710-154402.log`); images `out/adev.png`,
  `out/ts2phc_offset.png`, `out/ts2phc_freq.png`.
- **Next:** chrony (system clock) + `ptp4l` grandmaster (steps 6–7; note the
  `ptp4l.conf` inline-comment fix still owed); eventually antenna siting + an
  independent-clock comparison for the absolute number.

---

### 2026-07-10 (afternoon) — ts2phc capture→reduce pipeline validated; long run started
- **Setup:** Same path (F9T → i226 SDP0 → ts2phc → `/dev/ptp0`, locked). Goal:
  prove the capture→reduce chain on a short run before committing to a long one.
- **Config parse bug (fixed, commit 8c52393):** `config/i226/ts2phc.conf` had
  inline `#` comments on value lines. linuxptp's parser takes *everything after
  the key* as the value → `malformed value for option ts2phc.pulsewidth /
  failed to parse`. Only full-line `#` comments are allowed; values must be
  **bare**.
- **Capture:** `ts2phc … -m | tee data/ts2phc_testrun_20260710-153242.log`
  (2 min, 120 samples). Reduce = offset is whitespace **field 4** of the `-m`
  line → `awk '{print $4}'` → `allan.py --col offset_ns --ns`.
- **Observed:**
  - Raw ADEV(1 s) = **185 ns** — *not the real number*; dominated by the
    lock-in transient (−2250 ns re-acquisition in the first ~10 s).
  - Trimmed (drop first 15 samples, through settle): mean **0.01 ns**, **RMS
    4.15 ns**, **ADEV(1 s) = 9.5 ns → ~τ⁻¹ → 0.18 ns @ 32 s**. White-phase /
    quantization, same character as the F9T qErr. Cross-check √3·RMS ≈ 7.2 ns ≈
    ADEV(1 s) — consistent.
- **Learned:** the pre-`s2` lock-in transient **must be trimmed** before ADEV or
  it swamps short τ. The awk extraction is throwaway; a committed
  `reduce/parse_ts2phc.py` (parse `-m`, auto-drop pre-lock) is TODO before
  reducing the long run.
- **Long run:** started backgrounded, line-buffered, disconnect-safe —
  `sudo nohup stdbuf -oL ts2phc -f config/i226/ts2phc.conf -s generic -c enp3s0
  -m > data/ts2phc_longrun_20260710-154402.log &`. One long-lived process
  (ts2phc is a stable daemon — no segment rotation, unlike the UBX collector).
  Stop: `sudo pkill -f 'ts2phc -f config/i226'`.
- **Boundary:** still ts2phc's servo self-report (PHC vs its own PPS reference),
  not vs an independent clock.
- **Next:** soak (hours/overnight) → write `reduce/parse_ts2phc.py` → reduce +
  plot → the headline PHC-vs-PPS ADEV.

---

### 2026-07-10 — i226 PHC locked to the F9T PPS via ts2phc (Stage 3 first light)
- **Setup:** Host `radio`. F9T (timing mode, `fixType 5`, tAcc ~55 ns, 12 SV,
  GPS grid) TIMEPULSE → Timebeat U.FL breakout PPS-in → i226 SDP0. gpsd stopped.
- **Path proven end to end:** F9T pulse → i226 EXTTS → `ts2phc` → `/dev/ptp0`
  (enp3s0) disciplined. Config + run in `config/i226/ts2phc.conf` and
  `docs/i226-bringup.md` steps 4–5.
- **Observed (ts2phc -m):** servo `s0→s1→s2`; steady-state offset **~±10 ns**
  (mostly single digits), **freq ~+10010 ppb (+10 ppm)** — matches the PHC
  free-run measured independently via testptp (rising edges 1.00001 s apart).
  Two methods agree.
- **Gotchas nailed (each cost a cycle):**
  1. **50 Ω termination collapses the pulse.** F9T TIMEPULSE is weak CMOS; can't
     drive 50 Ω. DIP off → pulse survives (PPS LED cross-check). ON → LED dark.
  2. **testptp header skew.** `linux-libc-dev` is 6.8 on Ubuntu 24.04 even under
     the 6.17 kernel → build testptp from **v6.8** source, not master/v6.17.
  3. **ts2phc `-f` vs `-c`.** `-c` = add a PHC *sink*, not config; config is
     `-f`. And `ts2phc.master 1` makes the NIC a perout *generator* (strace:
     `PTP_PF_PEROUT` + `PTP_PEROUT_REQUEST2`), not an EXTTS reader — use
     `-s generic -c enp3s0`, no master.
  4. **igc is both-edges-only.** `extts_polarity rising` → `PTP_EXTTS_REQUEST2
     failed: EOPNOTSUPP`. Fix (linuxptp maintainer): `extts_polarity both` +
     `ts2phc.pulsewidth 100000000` (the 100 ms F9T pulse) so ts2phc drops the
     falling edge. testptp worked throughout because it uses the legacy flagless
     `PTP_EXTTS_REQUEST`. No timing penalty — rising edge still HW-timestamped.
- **Boundary:** ±10 ns is ts2phc's servo residual (self-report), not a measured
  PHC-vs-independent-clock number. That characterization (offset log + ADEV) is
  the next capture.
- **Next:** capture the ts2phc offset series over a long run → reduce (ADEV,
  distribution); then chrony (system clock) + ptp4l grandmaster (steps 6–7).

---

### 2026-07-08 — i226 Stage-3 prep: driver/PHC side verified on the bench
- **Setup:** Host `radio`. Intel **i226 PCIe card** (`lspci: 03:00.0 … I226-LM
  rev 04`) with a **user-soldered 6-pin SDP header** + a **Timebeat U.FL PPS
  breakout** (50 Ω-term DIP switches). F9T **not** wired to the breakout yet; no
  PPS injected.
- **Toolchain:** installed `linuxptp 4.0`, `pps-tools 1.0.2`, `ethtool`,
  `gpsd`/`gpsd-clients 3.25`, `chrony 4.5`, build-essential,
  `linux-headers-6.17.0-35`. `igc` in-tree, kernel **6.17.0-35-generic**.
  `testptp` **not** installed (deferred — `ts2phc` doesn't need it; keep
  `testptp -e` as a first-light debug probe only).
- **Confirmed (hardware):**
  - `enp3s0`, driver igc, fw `2020:888d`, bus `0000:03:00.0`; link DOWN (no
    cable — fine for PHC).
  - `ethtool -T enp3s0`: hw tx/rx + hardware-raw-clock; **PTP Hardware Clock:
    0** → `/dev/ptp0`.
  - `/sys/class/ptp/ptp0`: `clock_name f0b2b93551a9` (= enp3s0 MAC, confirms
    ptp0↔enp3s0); **2 EXTTS + 2 perout**; **SDP0–SDP3**, all `0 0` (unassigned).
    (`n_pins` scalar absent this kernel; `pins/` enumerates them.)
- **Resolved:** the LM-vs-T1 physical worry — it's a PCIe card with the SDP
  header soldered on, so the breakout attaches; driver-level EXTTS injection is
  viable.
- **Open:** which U.FL/SDP is **PPS-in** (→ `ts2phc.pin_index`/`channel`) —
  Timebeat pinout unreachable (403), so find it **empirically** (arm EXTTS, see
  which SDP logs edges once the F9T pulse is on the connector). Also undecided:
  **Timebeat sync daemon vs. linuxptp `ts2phc`/`ptp4l`** (breakout config uses
  Timebeat "pin/index", index 0 = PPS-in; the `config/i226/` skeletons assume
  linuxptp).
- **Next:** confirm F9T pulse wired to breakout PPS-in and F9T locked/emitting;
  then one edge-arm to identify the SDP.

---

### 2026-07-07 (afternoon) — config as plain commands; config script removed
- **Setup:** F9T on USB; re-applied the timing config.
- **What happened:** `config/f9t/apply-timing-config.sh` overreached — its
  read-back+retry `valset()` (2–4 ubxtool opens per setting) **hung on the very
  first setting** on real hardware. The container "validation" (a fake ubxtool I
  wrote) couldn't have caught it; only the bench did.
- **Fix (observed):** distilled the config to plain one-line `ubxtool -z`
  commands (now in `docs/f9t-setup.md`), run one at a time on the bench:
  grid=GPS (TIM-TP `refInfo 0x0`, week 2426), TIM-TP + TIM-SVIN enabled;
  `CFG-TMODE` read-back MODE=1 / SVIN_MIN_DUR=120 / SVIN_ACC_LIMIT=1000000;
  survey-in completed (`valid 1 active 0`, dur 120, obs 121; meanV → 3D σ ≈ 22 m,
  the expected coarse dry-run result).
- **Decision:** config is plain, one-at-a-time commands in `docs/f9t-setup.md`;
  `apply-timing-config.sh` **removed**. No config scripts — they hid behavior and
  broke; plain commands are observable and were confirmed on hardware.
- **Next:** antenna siting → tighter/longer survey → real Stage-1/2 capture.

---

### 2026-07-07 (evening) — extended dry run: 6 h capture; collector robust; qErr τ⁻¹ over 13 octaves
- **Setup:** F9T timing mode (GPS grid, RAM). Hardened `collect/log_ubx_timing.sh`
  — hourly rotating segments, fresh `ubxtool -w 3600` handle each, TIM-TP+NAV-PVT.
- **Capture:** `data/run_20260707-062948/` — 7 segments (6×1 h + partial),
  ~6.07 h, 21,842 TIM-TP. Reduced: `data/sample_overnight_timtp.tsv`, `.adev.tsv`.
- **Observed:**
  - **Robustness (the goal):** manifest = exactly `lines=50400 tim_tp=3600` for
    all 6 full hours (zero dropped timepulses), `ubxtool.err` empty, clean
    rotation + Ctrl-C stop, no back-off. The fresh-handle-per-hour design held
    all night; a failure would have cost ≤1 segment and shown as a low count.
  - **qErr:** stable ±~4 ns uniform sawtooth (min −4.04, max 3.81, mean −0.11,
    RMS 2.25 ns) across the full 6 h — no drift, no gaps.
  - **ADEV:** pure **τ⁻¹** over 13 octaves (3.97e-9 @1 s → 4.71e-13 @8192 s),
    slope ≈ −1.00 → white phase / quantization noise; no floor or structure.
- **Fixed/learned:** ubxtool default `--wait` ≈ 2 s (captures need `-w`);
  `allan.py` drops NaN (not forward-fill) for interleaved TIM-TP+NAV-PVT;
  `pps_offset.gp` x-axis = elapsed seconds; `apply-timing-config.sh` valset now
  read-back-verifies (kills the false "no ACK" WARNs).
- **Boundary:** this is the receiver's self-reported *quantization*, not its true
  stability or the value of sawtooth correction — those are Stage 3 (PPS vs an
  independent clock, needs the i226).
- **Next:** antenna siting → tight/long survey-in → real Stage-1/2 capture.

---

### 2026-07-07 — dry-run pipeline works end-to-end; τ⁻¹ sawtooth ADEV
- **Setup:** F9T in TIME mode (dry-run survey, GPS grid, RAM). Raw TIM-TP capture.
- **Capture:** `data/sample_dryrun_timtp.log` (~5 min, 300 TIM-TP @ 1 Hz).
  Reduced: `data/sample_dryrun_timtp.tsv`, `data/sample_dryrun_timtp.adev.tsv`.
- **Observed:** qErr sawtooth bounded **±~3.9 ns**, RMS **2.18 ns**, mean ≈ 0
  (uniform, as expected: 3.9/√3 ≈ 2.25 ≈ RMS). ADEV a clean **τ⁻¹** line
  (σ_y(1 s) ≈ 3.6e-9 → 3.0e-11 @ 128 s) = white phase / quantization noise, i.e.
  the *uncorrected* sawtooth. Whole chain collect → `parse_pps.py` → `allan.py`
  → gnuplot ran on real data; `parse_pps.py` handled the TIM-TP decode as-is
  (qErr ps→ns correct).
- **Learned:** ubxtool default `--wait` ≈ 2 s → captures need `-w <dur>`. The
  `collect/log_ubx_timing.sh` stub also passes the device positionally instead of
  `-f`. Both to fix. Sawtooth *correction* (corrected-vs-uncorrected ADEV) needs
  no new data — a later reduce step.
- **Next:** fix + harden the collector for long unattended runs (segmented,
  rotating output, auto-restart — a single long-lived handle is fragile); tidy
  the qErr-vs-time x-axis; then an overnight extended dry run.

---

### 2026-07-07 — timing mode via survey-in (dry-run params); TIM-SVIN, not NAV-SVIN
- **Setup:** ZED-F9T-20B, raw ubxtool, RAM-only changes. Goal for this pass: a
  **dry run** — get end-to-end through collect → reduce → plot and a good-enough
  answer *before* investing in antenna siting. So survey accuracy was
  deliberately loosened.
- **Capture:** none yet (survey config only); position coarse by design.
- **Observed / did:**
  - **Step 3 survey-in.** Set `CFG-TMODE-SVIN_MIN_DUR` + `SVIN_ACC_LIMIT`
    (`SVIN_ACC_LIMIT` is U4 in **0.1 mm**; 2 m = 20000), verified, then
    `CFG-TMODE-MODE = 1` (RAM). All RAM-only.
  - **NAV-SVIN → TIM-SVIN correction.** First attempt enabled
    `CFG-MSGOUT-UBX_NAV_SVIN_USB` — **NAK'd**: NAV-SVIN isn't supported on this
    TIM firmware (it's an F9P/HPG message). This firmware reports survey-in via
    **`UBX-TIM-SVIN` (0x0d 0x04)**; output key `CFG-MSGOUT-UBX_TIM_SVIN_USB`
    (`0x2091009a`), per the F9 TIM 2.25 Interface Description. Also learned: a
    multi-item `-z` VALSET is **atomic** — one bad key NAKs the whole batch
    (which had silently taken `MODE=1` down with it; isolating `MODE=1` ACK'd).
  - **Accuracy reality check.** With an honest 2 m limit, `TIM-SVIN meanV`
    ≈ 4.2e8 mm² → 3D σ ≈ **20 m**, falling slowly — reaching 2 m at this antenna
    spot would likely take hours. Antenna environment is the limiter (matches the
    earlier nav-mode position wander).
  - **Dry-run pivot.** Restarted survey with `SVIN_MIN_DUR = 120 s`,
    `SVIN_ACC_LIMIT = 1000000` (100 m) so it completes on time regardless of
    accuracy. Completed: `TIM-SVIN valid 1 active 0` at obs 121; `NAV-PVT
    fixType 5` (time-only). F9T now a stationary timing source (coarse position).
- **Next:** capture ~2 min of TIM-TP, align `collect/log_ubx_timing.sh` +
  `parse_pps.py` to the real ubxtool decode, then `allan.py` + gnuplot for the
  qErr + ADEV answer. A proper long/tight survey comes after antenna siting.

---

### 2026-07-07 — config baseline; TIM-TP enabled (RAM); PPS grid switched to GPS
- **Setup:** Same bench, still nav mode, raw `ubxtool`; gpsd left stopped.
- **Capture:** `config/f9t/20260707-041251_asfound.txt` (as-found config snapshot; read-only).
- **Observed:**
  - **Config baseline** (RAM=Default unless noted): `CFG-TMODE-MODE=0` (nav);
    `CFG-TP` = 1 PPS, 100 ms locked width, aligned-to-TOW, rising, GNSS-synced,
    `USE_LOCKED=1`, `TIMEGRID_TP1=4`, `ANT_CABLEDELAY=50 ns`, TP2 off; `CFG-RATE`
    1 Hz, `TIMEREF=1` (GPS); `CFG-SIGNAL` GPS/GAL/BDS/QZSS/SBAS, L1/E1/B1 only
    (GLONASS unsupported by TIM 2.25); USB `CFG-MSGOUT` NAV set on (non-default →
    persisted), `TIM_TP_USB=0`.
  - **Step 1 — TIMEGRID resolved:** `TIMEGRID_TP1 = 4 = GAL (Galileo)`, the
    firmware factory default (F9-TIM-2.25 Interface Description, Tables 70 & 115).
    Note the *Integration Manual* PDF covers -00B/-10B, not our -20B; the
    *Interface Description* matches TIM 2.25 and is the authority.
  - **Step 2 — TIM-TP enabled (RAM only):** `ubxtool -z CFG-MSGOUT-UBX_TIM_TP_USB,1,1`
    (LAYERS bitmask: RAM=1; ubxtool default is RAM+Flash=5, so `,1` is required
    for RAM-only). VALSET ACK'd; `UBX-TIM-TP` streams at 1 Hz. `qErr` unit = **ps**
    (Int. Desc. p168); first-light ±~3.4 ns (2521, −2430, −153, 1514, 3442 ps).
    flags: GNSS timebase / UTC available / RAIM active / qErr valid / TP locked.
  - **Grid empirically confirmed Galileo:** TIM-TP `refInfo=0x3` (timeRefGnss=3)
    and `week=1402` (Galileo System Time week; GST epoch = GPS week 1024, so
    2426−1024=1402), vs `NAV-TIMEGPS` GPS week 2426.
  - **`parse_pps.py` qErr TODO resolved:** qErr is ps → the assumed ps→ns `/1000`
    is correct.
- **Decision + applied:** PPS time grid → **GPS** (`CFG-TP-TIMEGRID_TP1 = 1`,
  RAM-only). Applied and confirmed: TIM-TP now reads `refInfo=0x0` (timeRefGnss=0,
  GPS) and `week=2426` (GPS week); qErr unchanged in character (±~3 ns). TP2 left
  on Galileo (disabled anyway).
- **Next:** Step 3 survey-in (`SVIN_MIN_DUR=3600 s`, `SVIN_ACC_LIMIT` in 0.1 mm
  units — e.g. 2 m = 20000), RAM-only.

---

### 2026-07-07 — first live contact; gpsd → raw ubxtool basis established
- **Setup:** SparkFun GNSS Timing Breakout (ZED-F9T-20B) on USB, `/dev/ttyACM0`
  (by-id `usb-u-blox_AG_-_www.u-blox.com_u-blox_GNSS_receiver-if00`). Confirmed
  via UBX-MON-VER: MOD=ZED-F9T-20B, FWVER=TIM 2.25, PROTVER=29.25, HW 00190000.
  Host had gpsd 3.25 auto-managing the port (`USBAUTO="true"` + `60-gpsd.rules`;
  boot `DEVICES=/dev/ttyUSB0`); stopped `gpsd.socket` + `gpsd.service` to take
  deterministic ownership for raw `ubxtool` (reversible via `systemctl start`).
  Receiver in default **navigation** mode (not timing/survey-in).
- **Capture:** none saved (interactive polls only; no file written).
- **Observed:** Healthy 3D fix — UBX-NAV-PVT fixType 3, ~13–20 SV used, GPS/
  Galileo/BeiDou/QZSS tracked (no GLONASS seen). Time valid: GPS week 2426,
  leapS 18, tAcc ~26 ns; receiver clock correct (2026-07-07). `ubxtool` 3.25
  does two-way UBX on the raw tty **without sudo**. Default USB output is the UBX
  nav set (NAV-PVT/-POSECEF/-VELECEF/-SAT/-SIG/-DOP/-TIMEGPS/-EOE); **UBX-TIM-TP
  is not in the default stream** (must be enabled for Stage 2). Aside: gpsd's SKY
  records carried a spurious 2019-04-09 timestamp while the receiver's own PVT/
  TIMEGPS time was correct — a gpsd labeling artifact, not the receiver.
- **Next:** read CFG-TMODE (then CFG-TP / TIM-TP message output) to capture the
  config baseline before changing anything.

---

### 0000-00-00 — repo initialized
- **Setup:** timing-bench scaffold created. F9T on USB, not yet characterized.
- **Capture:** none.
- **Observed:** n/a.
- **Next:** confirm F9T timing mode + survey-in (docs/f9t-setup.md), then take a
  first multi-hour Stage-1 capture.
