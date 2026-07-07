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
