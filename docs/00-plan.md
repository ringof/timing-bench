# timing-bench — assessment plan

Living document. The question this repo answers: **how well is our timing
source working, and where does the error come from?** Staged so each stage is
useful on its own and builds toward end-to-end characterization of the PTP
grandmaster.

## What "working well" means here

The F9T on USB can self-report a lot before any external reference exists. We
exploit three independent signals, in increasing order of what they prove:

1. **Fix quality / survey-in** — sats used, fix type, and (in timing mode)
   survey-in status and the surveyed position variance. A drifting or
   marginal fix caps everything downstream. Cheap to log, good first health
   signal.

2. **Sawtooth / quantization error (UBX-TIM-TP)** — the F9T reports the
   quantization error of each timepulse (the sub-sample residual between its
   internal clock and the requested edge). Plotting this shows the residual
   you would remove with sawtooth correction, and its distribution is a direct
   quality readout of the PPS *as the receiver sees it*. Self-contained: needs
   only the USB device.

3. **PPS vs. an independent clock (end-to-end)** — once the i226 is installed,
   timestamp the F9T PPS against the NIC PHC via an SDP EXTTS channel and plot
   that offset series and its Allan deviation. This is the real number: it
   folds in cable, edge, and disciplining behavior, not just the receiver's
   self-opinion. Depends on hardware not yet in place.

Stages 1–2 are doable now with just the USB F9T. Stage 3 is the payoff and is
gated on the i226/ts2phc bring-up (see the separate PTP grandmaster work).

## Roadmap

Status as of 2026-07-14. The **grandmaster bring-up** (wiring → ts2phc → ptp4l →
systemd persistence, reboot-validated) is done — see `docs/i226-bringup.md`.
Captures so far were **dry-runs** (loose survey, ~6 h) that proved the toolchain;
the **real-data pass** (antenna siting → tight/long survey → real captures) is
the main remaining work.

### Stage 1 — F9T health logging
- [x] F9T in stationary/timing mode with a survey-in — **dry-run only** (loose
      100 m / 120 s; real siting-quality survey still TODO). See `f9t-setup.md`.
- [x] `collect/` logs UBX-TIM-TP + NAV at 1 Hz to `data/`
      (`collect/log_ubx_timing.sh`).
- [x] `reduce/parse_pps.py` emits tidy TSV (TIM-TP path validated on real data).
- [~] Plots — `plots/pps_offset.gp` done; `plots/skyplot_sats.gp` not yet
      exercised.
- [x] First notebook baseline capture (6 h overnight).

### Stage 2 — sawtooth characterization
- [ ] Quantization error over **≥ 24 h** (day/night sat geometry) — only ~6 h so
      far; **the 24 h run is next.**
- [x] `reduce/allan.py` ADEV (qErr τ⁻¹ confirmed) — corrected-vs-uncorrected
      comparison not yet done.
- [x] `plots/adev.gp` log-log ADEV.

### Stage 3 — end-to-end PHC assessment
- [x] Wire F9T TIMEPULSE → i226 SDP0 (Timebeat U.FL breakout).
- [x] `testptp -e` — EXTTS confirmed, pin = SDP0.
- [x] PHC-vs-PPS offset series (via ts2phc `-m`) reduced
      (`reduce/parse_ts2phc.py`).
- [x] Offset + ADEV plots (10.25 h run: ~4.7 ns RMS, τ⁻¹) — headline GM number.
- [ ] Scrape `ptp4l -m` master offset / RMS for the **served** side — needs the
      PTP client (Pi5).

### Remaining to close the plan
- [ ] **Real** antenna siting → tight/long survey-in → real Stage-1/2/3 captures.
- [ ] 24 h sawtooth run (Stage 2).
- [ ] PTP client (Pi5) + served-side measurement (Stage 3).
- [ ] Optional: corrected-vs-uncorrected ADEV; `plots/skyplot_sats.gp`.

## Conventions
- Raw captures: append-only, line-oriented, **epoch seconds first column**.
- Never edit raw. Reduced TSV is regenerable; plots are regenerable.
- One capture = one file, named `data/YYYYMMDD-HHMMSS_<what>.log`.
- Notebook entries dated, newest on top, note the capture file they refer to.
