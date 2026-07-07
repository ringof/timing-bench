#!/usr/bin/env bash
# log_nmea_pps.sh — capture NMEA + PPS via gpsd (gpspipe).
#
# Alternative collector for when gpsd is already managing the F9T. Logs the
# gpsd JSON stream (which includes TPV/SKY and, if a PPS source is configured,
# PPS/TOFF reports) to a timestamped file in data/.
#
# This path is convenient but less direct for sawtooth work than
# log_ubx_timing.sh — gpsd may not surface UBX-TIM-TP quantization error.
# Prefer the ubx collector for Stage 2.
#
# Requires: gpsd running and managing the F9T; gpspipe (gpsd-clients).
#
# Usage:
#   ./collect/log_nmea_pps.sh [SECONDS] [GPSD_HOSTPORT]
#   SECONDS       default 3600
#   GPSD_HOSTPORT default localhost:2947
set -euo pipefail

DUR="${1:-3600}"
HOSTPORT="${2:-localhost:2947}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
OUT="data/${STAMP}_gpsd-json.log"

mkdir -p data

echo "# gpsd=${HOSTPORT} start_utc=${STAMP} duration_s=${DUR}" | tee "$OUT"
echo "logging gpsd JSON to ${OUT} for ${DUR}s ..." >&2

# gpspipe -w = JSON (watch) mode. Prefix each line with a host epoch timestamp.
# timeout bounds the run. TODO: if a kernel PPS (/dev/pps0) is wired, ensure
# gpsd is started with it so PPS/TOFF reports appear in the stream.
timeout "$DUR" gpspipe -w "$HOSTPORT" \
  | while IFS= read -r line; do
      printf '%s\t%s\n' "$(date -u +%s.%N)" "$line"
    done >> "$OUT"

echo "done: ${OUT}" >&2
