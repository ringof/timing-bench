# timing-bench

A living bench for characterizing timing sources and, eventually, the full
GPS → PHC → PTP chain. First occupant: a SparkFun u-blox **ZED-F9T-20B** timing
receiver on USB. Later occupants: an Intel **i226** PHC disciplined by the F9T
PPS (via `ts2phc`), served as a PTP grandmaster (`ptp4l`).

The repo is organized as a pipeline so it stays a real assessment tool rather
than a script pile:

```
collect/  →  reduce/  →  plots/
 (raw)       (tidy)      (png/svg)
```

- **collect/** grabs raw data from the instrument. Append-only, never edited.
- **reduce/** turns raw captures into tidy, column-oriented series.
- **plots/** are gnuplot scripts that render from reduced data. Always
  regenerable; nothing in `out/` is precious.

Raw data lives in `data/` and generated images in `out/`; both are gitignored
except small committed samples so the plots have something to render in CI/demo.

## Start here

1. `docs/00-plan.md` — what we're assessing and the staged roadmap.
2. `docs/f9t-setup.md` — how the F9T is configured (timing mode, survey-in, TP).
3. `docs/notebook.md` — dated lab notebook, newest entry on top.

## Quick start (F9T on USB)

```bash
# 1. Configure the F9T for stationary timing (see docs/f9t-setup.md), then:
./collect/log_ubx_timing.sh    # OR ./collect/log_nmea_pps.sh  (pick one path)
# 2. Reduce a capture:
python3 reduce/parse_pps.py data/<capture>.log > data/<capture>.tsv
# 3. Plot:
gnuplot plots/pps_offset.gp    # reads the newest .tsv in data/
```

## Intake paths

Two collectors are provided; use whichever matches your setup:

- **ubxtool** (`log_ubx_timing.sh`) — pulls UBX-TIM-TP directly. Best for the
  F9T's own quantization-error (sawtooth) readout. Preferred for timing work.
- **gpsd/gpspipe** (`log_nmea_pps.sh`) — NMEA + PPS via gpsd. Convenient if
  gpsd is already managing the device.

Don't run both against the same tty at once; gpsd will hold the port.

## Status

Early. Collectors and reducers are functional stubs with clearly marked TODOs.
The F9T self-assessment path (sawtooth + fix quality) works with USB only.
The end-to-end PHC/EXTTS assessment is roadmapped in `docs/00-plan.md` §3 and
depends on the i226 install.
