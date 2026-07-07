#!/usr/bin/env bash
# log_ubx_timing.sh — robust long-run capture of F9T timing telemetry (UBX).
#
# Captures UBX-TIM-TP (timepulse quantization / sawtooth qErr) and UBX-NAV-PVT
# (fix type / sats / time — health context), host-epoch-prefixed, into hourly
# rotating segment files under a per-run directory.
#
# Built for long unattended runs. Instead of one long-lived ubxtool handle, each
# segment is a fresh, bounded `ubxtool -w SEGMENT` session; when it ends —
# normally or from a USB/process hiccup — the loop immediately starts the next.
# A failure therefore costs at most the current segment, and every completed
# segment is a closed, complete file. Every line carries a host epoch, so any
# gap/dropout is visible in the data rather than silent. Runs until Ctrl-C.
#
# Prereqs: device already configured (config/f9t/apply-timing-config.sh) and
# gpsd not holding the port. For an overnight run, consider masking gpsd.socket
# so nothing can respawn and steal /dev/ttyACM0.
#
# Usage:
#   ./collect/log_ubx_timing.sh
#   DEV=/dev/ttyACM0 PROTVER=29.25 SEGMENT=3600 ./collect/log_ubx_timing.sh
#   # stop with Ctrl-C. Reduce a whole run (segments concatenated in order):
#   cat data/run_<stamp>/seg_*.log | python3 reduce/parse_pps.py /dev/stdin > out.tsv
set -uo pipefail

DEV="${DEV:-/dev/ttyACM0}"
PROTVER="${PROTVER:-29.25}"
SEGMENT="${SEGMENT:-3600}"                       # seconds per segment file (1 hour)
RUNDIR="${RUNDIR:-data/run_$(date -u +%Y%m%d-%H%M%S)}"

command -v ubxtool >/dev/null 2>&1 || { echo "ubxtool not found" >&2; exit 1; }

mkdir -p "$RUNDIR"
MANIFEST="$RUNDIR/manifest.txt"
ERRLOG="$RUNDIR/ubxtool.err"
echo "# run start $(date -u +%FT%TZ)  dev=$DEV protver=$PROTVER segment=${SEGMENT}s" \
  | tee "$MANIFEST" >&2

stop=0
trap 'stop=1; echo "[stop] signal received — finishing current segment, then exit" >&2' INT TERM

seg=0
while [ "$stop" -eq 0 ]; do
  seg=$((seg + 1))
  ts="$(date -u +%Y%m%d-%H%M%S)"
  out="$RUNDIR/seg_$(printf '%04d' "$seg")_${ts}.log"
  echo "[seg $seg] -> $out (<= ${SEGMENT}s)" >&2

  # One bounded ubxtool session (fresh handle). Keep only TIM-TP + NAV-PVT
  # blocks, then host-epoch-prefix every line. Line-buffered end to end so a
  # kill loses at most the last line.
  ubxtool -P "$PROTVER" -f "$DEV" -w "$SEGMENT" 2>>"$ERRLOG" \
    | stdbuf -oL awk '
        /^UBX-TIM-TP:/ || /^UBX-NAV-PVT:/ { keep=1; print; fflush(); next }
        /^[A-Za-z]/ { keep=0; next }
        keep { print; fflush() }
      ' \
    | while IFS= read -r line; do
        printf '%s\t%s\n' "$(date -u +%s.%N)" "$line"
      done >> "$out"

  n=$(wc -l < "$out" 2>/dev/null || echo 0)
  tp=$(grep -c '	UBX-TIM-TP:' "$out" 2>/dev/null || echo 0)
  echo "seg $seg  $(basename "$out")  lines=$n  tim_tp=$tp  end=$(date -u +%FT%TZ)" \
    | tee -a "$MANIFEST" >&2

  # If a segment produced almost nothing (device gone / port stolen), back off
  # briefly instead of spinning — but keep trying, so a transient recovers.
  if [ "$n" -lt 2 ] && [ "$stop" -eq 0 ]; then
    echo "[warn] near-empty segment; backing off 5s (device/port issue?)" >&2
    sleep 5
  fi
done

echo "# run end $(date -u +%FT%TZ)  segments=$seg" | tee -a "$MANIFEST" >&2
echo "done. run dir: $RUNDIR" >&2
