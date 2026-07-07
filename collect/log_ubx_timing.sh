#!/usr/bin/env bash
# log_ubx_timing.sh — capture UBX timing telemetry from the F9T via ubxtool.
#
# Preferred collector for timing work: pulls UBX-TIM-TP which carries the
# F9T's own timepulse quantization (sawtooth) error. Writes raw ubxtool text
# to a timestamped file in data/. reduce/parse_pps.py turns it into TSV.
#
# Requires: gpsd's ubxtool. If gpsd owns the device, this reads through it;
# otherwise point ubxtool at the tty directly.
#
# Usage:
#   ./collect/log_ubx_timing.sh [DEVICE] [SECONDS]
#   DEVICE  default /dev/ttyACM0   (or a gpsd host:port like localhost:2947)
#   SECONDS default 3600
set -euo pipefail

DEV="${1:-/dev/ttyACM0}"
DUR="${2:-3600}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT="data/${STAMP}_ubx-timing.log"

mkdir -p data

echo "# device=${DEV} start_utc=${STAMP} duration_s=${DUR}" | tee "$OUT"
echo "logging UBX-TIM-TP + NAV to ${OUT} for ${DUR}s ..." >&2

# TODO: confirm the exact ubxtool invocation/flags against the installed gpsd
# version. -w wraps the run for DUR seconds; -v 2 for verbose decode. We prefix
# each decoded line with an epoch timestamp so downstream parsing has a clock
# independent of the receiver.
#
# Enable messages first (idempotent); ignore errors if already enabled.
ubxtool -e TIM-TP  "$DEV" >/dev/null 2>&1 || true
ubxtool -e NAV-SAT "$DEV" >/dev/null 2>&1 || true

# Stream and timestamp. ubxtool -w runs for DUR seconds and decodes to stdout.
ubxtool -w "$DUR" -v 2 "$DEV" \
  | while IFS= read -r line; do
      printf '%s\t%s\n' "$(date -u +%s.%N)" "$line"
    done >> "$OUT"

echo "done: ${OUT}" >&2
