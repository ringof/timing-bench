# F9T timing-mode setup plan

Living plan for moving the ZED-F9T-20B from its as-found navigation config into
a reliable **stationary timing** configuration, enabling the telemetry needed
for Stage 1 (health) and Stage 2 (sawtooth), and capturing before/after config
so the bench is reproducible.

Executed under the CLAUDE.md working agreement: **one step at a time**, each
gated on the previous step's observed result; every `CFG-VALSET` immediately
read back with `CFG-VALGET`; **RAM-first** — nothing persisted to Flash/BBR
until validated; change-doc block + explicit approval before any commit.

## As-found baseline (confirmed 2026-07-07; RAM = Default unless noted)
- Module ZED-F9T-20B, FW TIM 2.25, PROTVER 29.25; `/dev/ttyACM0`, raw ubxtool
  3.25 two-way, no sudo; gpsd stopped to own the port.
- `CFG-TMODE-MODE = 0` (navigation / survey-in disabled).
- Timepulse TP1 enabled: 1 PPS (`PERIOD*=1000000`), 100 ms locked width
  (`LEN_LOCK=100000`), `ALIGN_TO_TOW=1`, `POL=1` (rising), `SYNC_GNSS=1`,
  `USE_LOCKED=1`; `TIMEGRID_TP1 = 4 = GAL (Galileo)`; `ANT_CABLEDELAY
  = 50 ns`; TP2 disabled.
- USB message out: NAV PVT/SAT/POSECEF/DOP/VELECEF/TIMEGPS (+SIG/EOE) enabled
  (non-default → a customized config is persisted somewhere); `UBX_TIM_TP_USB
  = 0`.
- `CFG-RATE`: 1 Hz (`MEAS=1000`, `NAV=1`), `TIMEREF = 1` (GPS).
- `CFG-SIGNAL`: GPS/GAL/BDS/QZSS/SBAS enabled, L1/E1/B1 band only (L2/E5b/B2
  off). GLONASS unsupported by this firmware.

## Open questions to resolve
1. **`TIMEGRID_TP1 = 4`** — RESOLVED: `4 = GAL (Galileo)`, firmware factory
   default (Int. Desc. Tables 70 & 115), confirmed empirically by TIM-TP
   `refInfo=0x3` + `week=1402` (GST week). **DECISION 2026-07-07: set to GPS
   (`TIMEGRID_TP1 = 1`), RAM-only — APPLIED & confirmed** (TIM-TP `refInfo=0x0`,
   `week=2426`).
2. **Survey-in vs fixed position** — DECIDED: survey-in, short first pass
   (`SVIN_MIN_DUR ~3600 s`, `SVIN_ACC_LIMIT` a few meters) for first-light
   validation; a longer/tighter survey or a fixed known position can come later.
3. **Persistence** — DECIDED: RAM-only during bringup; save to BBR/Flash only
   at Step 5, and only once validated.

## Steps (each gated on observed result)

### Step 0 — snapshot the as-found config into `config/f9t/` — DONE (config/f9t/20260707-041251_asfound.txt)
Dump `CFG-TMODE`, `CFG-TP`, `CFG-RATE`, `CFG-SIGNAL`, and the USB `CFG-MSGOUT`
values (RAM layer) to a versioned `config/f9t/YYYYMMDD_asfound.txt` before any
change. This is the reproducible "before" and fulfils the docs' "dump live
config" TODO.

### Step 1 — resolve `TIMEGRID_TP1 = 4` — DONE (= GAL/Galileo; decision: switch to GPS)
Confirm the `CFG-TP-TIMEGRID` enum against the interface description /
integration manual (in `docs/datasheets/`). Decide: keep as-is, or set to GPS
(1) / UTC (0). No change until the meaning is confirmed.

### Step 2 — enable UBX-TIM-TP on USB (RAM only) — DONE (RAM; qErr in ps, ±~3.4 ns first-light)
`CFG-VALSET CFG-MSGOUT-UBX_TIM_TP_USB = 1` in RAM. Read back; confirm
`UBX-TIM-TP` messages appear and carry a quantization-error field. Capture a
short sample and inspect qErr — this unblocks Stage 2 and lets us see the
sawtooth *before* committing to timing mode. Also settles the `parse_pps.py`
qErr units/field-name TODO against real data.

### Step 3 — set timing mode: survey-in (RAM only) — DONE (dry-run params)
Preceded by applying the PPS-grid change (`TIMEGRID_TP1 = 1`, GPS, RAM).
`CFG-TMODE-MODE = 1` (survey-in), `SVIN_MIN_DUR`, `SVIN_ACC_LIMIT` (U4, units
0.1 mm). Monitor **`UBX-TIM-SVIN`** (NOT NAV-SVIN — unsupported on TIM firmware;
output key `CFG-MSGOUT-UBX_TIM_SVIN_USB` = `0x2091009a`) until `valid=1`.
- Dry-run pass (2026-07-07): `SVIN_MIN_DUR=120 s`, `SVIN_ACC_LIMIT=1000000`
  (100 m) — intentionally loose so the pipeline can be exercised before antenna
  siting. Completed at obs 121; `NAV-PVT fixType 5`.
- Real pass (after siting): tighter limit (~2 m) + longer duration; record the
  surveyed position and its variance.

### Step 4 — validate timing behavior
With survey valid and stationary: observe the qErr distribution and confirm
`NAV-PVT` is now stationary. Sanity-check the PPS config still reads as
intended. Note results in `docs/notebook.md`.

### Step 5 — persistence decision + save
If validated, optionally persist the changed keys to BBR/Flash. Re-snapshot
config into `config/f9t/` as the "after" baseline. Update `docs/f9t-setup.md`
(fill the survey-in / TP TODOs with the values actually used) and the notebook.

### Step 6 — first real Stage-1 capture
**Dry-run first** (2026-07-07 onward): a short capture now to validate the
collect → reduce → plot toolchain end-to-end (and fix the `collect/` +
`parse_pps.py` stubs against the real ubxtool decode) — accuracy not the point.
The genuine multi-hour capture (TIM-TP + NAV at 1 Hz) follows antenna siting;
reduce with `parse_pps.py` + `allan.py`; render plots; notebook entry.

## Guardrails
- RAM-first; nothing to Flash/BBR until Step 5 and only if validated.
- Every `CFG-VALSET` is followed immediately by a `CFG-VALGET` read-back.
- Treat each step's outcome as unknown until observed; do not chain steps.
- Change-doc block in chat + explicit approval before any commit; ask before
  push. Develop on branch `f9t-bringup`.
