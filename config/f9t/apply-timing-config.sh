#!/usr/bin/env bash
# apply-timing-config.sh — bring the ZED-F9T-20B into the bench timing config.
#
# Reproduces the configuration established during bring-up (see docs/notebook.md
# and docs/f9t-setup.md). All device changes are RAM-only (LAYERS=1) and revert
# on power-cycle / replug — re-run this after a reset. Nothing here is persisted
# to Flash/BBR (that is the deliberate, later Step 5).
#
# Steps, in the order proven on the bench:
#   1. Stop gpsd so we own /dev/ttyACM0 (it auto-manages USB GNSS via USBAUTO).
#   2. Identity sanity check (UBX-MON-VER).
#   3. PPS timepulse grid -> GPS          (CFG-TP-TIMEGRID_TP1 = 1)
#   4. Enable UBX-TIM-TP on USB           (sawtooth / qErr, Stage 2)
#   5. Enable UBX-TIM-SVIN on USB         (survey-in status; NOT NAV-SVIN)
#   6. Set survey-in params and (re)start (CFG-TMODE)
#   7. Poll UBX-TIM-SVIN until valid.
#
# This file grows as more of the pipeline (capture -> reduce -> plot) is proven.
#
# Usage:
#   ./config/f9t/apply-timing-config.sh
#   # override any default via env vars, e.g. a tighter real survey after siting:
#   SVIN_MIN_DUR=3600 SVIN_ACC_LIMIT=20000 ./config/f9t/apply-timing-config.sh
set -euo pipefail

DEV="${DEV:-/dev/ttyACM0}"
PROTVER="${PROTVER:-29.25}"
LAYER="${LAYER:-1}"                            # UBX-CFG-VALSET layers bitmask: RAM=1, BBR=2, Flash=4
# Survey-in parameters. DRY-RUN defaults (intentionally loose/short so the
# pipeline can be exercised before antenna siting). Tighten for the real run.
SVIN_MIN_DUR="${SVIN_MIN_DUR:-120}"            # seconds
SVIN_ACC_LIMIT="${SVIN_ACC_LIMIT:-1000000}"   # units of 0.1 mm  (1000000 = 100 m)

command -v ubxtool >/dev/null 2>&1 || { echo "ubxtool not found (install gpsd tools)" >&2; exit 1; }

ubx() { ubxtool -P "$PROTVER" -f "$DEV" "$@"; }

valset() {  # valset KEY,VAL   — applies to $LAYER; aborts on NAK
  local kv="$1" out
  out="$(ubx -z "${kv},${LAYER}" 2>&1 || true)"
  if printf '%s\n' "$out" | grep -q 'ACK-NAK'; then
    echo "  NAK: ${kv}  (layer ${LAYER})" >&2
    return 1
  elif printf '%s\n' "$out" | grep -q 'ACK-ACK'; then
    echo "  ok:  ${kv}  (layer ${LAYER})"
  else
    echo "  WARN: no ACK seen for ${kv}" >&2
  fi
}

echo "== F9T timing config -> ${DEV}  (protver ${PROTVER}, layer ${LAYER}, RAM-only) =="

echo "[1] stop gpsd (own the port)"
sudo systemctl stop gpsd.socket gpsd.service || true

echo "[2] device check (UBX-MON-VER)"
ubx -p MON-VER 2>&1 | grep -E 'MOD=|FWVER=' \
  || { echo "  no MON-VER response from ${DEV}" >&2; exit 1; }

echo "[3] PPS timepulse grid -> GPS"
valset CFG-TP-TIMEGRID_TP1,1

echo "[4] enable UBX-TIM-TP on USB (sawtooth qErr)"
valset CFG-MSGOUT-UBX_TIM_TP_USB,1

echo "[5] enable UBX-TIM-SVIN on USB (survey-in status)"
valset CFG-MSGOUT-UBX_TIM_SVIN_USB,1

echo "[6] survey-in: MIN_DUR=${SVIN_MIN_DUR}s  ACC_LIMIT=${SVIN_ACC_LIMIT} (0.1mm)"
valset CFG-TMODE-MODE,0                        # stop any running survey first
valset CFG-TMODE-SVIN_MIN_DUR,"${SVIN_MIN_DUR}"
valset CFG-TMODE-SVIN_ACC_LIMIT,"${SVIN_ACC_LIMIT}"
valset CFG-TMODE-MODE,1                        # start fresh survey with these params

echo "[7] waiting for survey-in valid (UBX-TIM-SVIN)..."
max_iter=$(( SVIN_MIN_DUR / 5 + 60 ))
for _ in $(seq 1 "$max_iter"); do
  line="$(timeout 3 ubx 2>&1 | grep -m1 -E 'valid [0-9] active' || true)"
  [ -n "$line" ] && echo "  ${line}"
  case "$line" in
    *"valid 1"*) echo "survey-in complete."; break ;;
  esac
  sleep 5
done

echo "done.  Verify config: ubxtool -P ${PROTVER} -f ${DEV} -g CFG-TMODE"
