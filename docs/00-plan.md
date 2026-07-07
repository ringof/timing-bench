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

### Stage 1 — F9T health logging (NOW)
- [ ] Confirm F9T in stationary/timing mode with a completed survey-in
      (see `f9t-setup.md`).
- [ ] `collect/` logs UBX-TIM-TP + UBX-NAV-STATUS/-SAT at 1 Hz to `data/`.
- [ ] `reduce/parse_pps.py` emits tidy TSV: epoch, tp_offset_ns, quant_err_ns,
      fix_type, num_sv, survey_valid.
- [ ] `plots/pps_offset.gp`, `plots/skyplot_sats.gp` render from that TSV.
- [ ] First notebook entry with a baseline capture (≥ a few hours).

### Stage 2 — sawtooth characterization (NOW)
- [ ] Log quantization error over a long run (≥ 24 h to see day/night sat
      geometry effects).
- [ ] `reduce/allan.py` computes ADEV/MDEV of the corrected vs. uncorrected
      series.
- [ ] `plots/adev.gp` log-log ADEV. Compare corrected vs. uncorrected to
      quantify the value of sawtooth correction.

### Stage 3 — end-to-end PHC assessment (LATER, gated on i226)
- [ ] Wire F9T TIMEPULSE → i226 SDP (via timeSync breakout).
- [ ] `testptp -e` to confirm EXTTS edges and identify the pin index.
- [ ] Collector reads EXTTS timestamps; reduce to PHC-vs-PPS offset series.
- [ ] Plot offset + ADEV; this becomes the headline "how good is our GM" plot.
- [ ] Extend collectors to scrape `ptp4l -m` master offset / RMS for the
      served side.

## Conventions
- Raw captures: append-only, line-oriented, **epoch seconds first column**.
- Never edit raw. Reduced TSV is regenerable; plots are regenerable.
- One capture = one file, named `data/YYYYMMDD-HHMMSS_<what>.log`.
- Notebook entries dated, newest on top, note the capture file they refer to.
