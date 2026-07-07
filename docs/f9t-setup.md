# ZED-F9T setup (SparkFun GNSS Timing Breakout, USB)

Records how the F9T is configured so captures are reproducible. Values marked
**confirmed** were read from the live device; **TODO** items are not yet set or
read. Do not treat a TODO as done until a device read confirms it.

## Confirmed against hardware — 2026-07-07
- Module: **ZED-F9T-20B** (SparkFun GNSS Timing Breakout). Firmware **TIM 2.25**,
  protocol **29.25**, HW `00190000`, ROM BASE `0x3BFC8935`, swVersion
  `EXT CORE 1.00 (535349)` — all from UBX-MON-VER.
- USB enumerates as u-blox VID:PID `1546:01a9`, CDC-ACM → `/dev/ttyACM0`. Stable
  path: `/dev/serial/by-id/usb-u-blox_AG_-_www.u-blox.com_u-blox_GNSS_receiver-if00`.
- Two-way UBX over the raw tty works with gpsd's `ubxtool` 3.25, **no sudo**:
  `ubxtool -P 29.25 -f /dev/ttyACM0 -p MON-VER`.
- Fix state at first contact: 3D (UBX-NAV-PVT fixType 3), ~13–20 SV used,
  GPS/Galileo/BeiDou/QZSS tracked (GLONASS not observed). Time valid: GPS
  week 2426, leapS 18, tAcc ~26 ns.
- Default USB output is the UBX nav set (NAV-PVT / -POSECEF / -VELECEF / -SAT /
  -SIG / -DOP / -TIMEGPS / -EOE). **UBX-TIM-TP is NOT in the default stream** —
  must be enabled for sawtooth / Stage-2 work.
- Operating mode: **navigation** — confirmed `CFG-TMODE-MODE = 0` (RAM and
  default); survey-in disabled, all TMODE position/SVIN fields zero.

## Device
- Board: SparkFun GNSS Timing Breakout, **ZED-F9T-20B** module. (Not u-blox's
  separate NEO-F9T package; this board's module self-reports MOD=ZED-F9T-20B.)
- Connection: USB CDC-ACM at `/dev/ttyACM0` (verify: `ls -l /dev/serial/by-id/`).
- The F9T also emits a hardware PPS on its TIMEPULSE pin; USB is only the
  config/telemetry path. End-to-end PPS assessment (Stage 3) uses that pin into
  the i226 SDP, not USB.

## Intake path — raw ubxtool (decided 2026-07-07)
Primary intake is **raw `ubxtool` on `/dev/ttyACM0`**, not gpsd. Reason: gpsd
does not surface UBX-TIM-TP quantization error and complicates timing-mode
config. gpsd is fine as a secondary Stage-1 health view.

gpsd on this host auto-manages USB GNSS devices (`/etc/default/gpsd` has
`USBAUTO="true"`, plus the `60-gpsd.rules` udev rule; boot `DEVICES=/dev/ttyUSB0`
does not include our board). It will claim `/dev/ttyACM0` on replug or whenever
a gpsd client connects. To take deterministic ownership for raw captures:
```bash
sudo systemctl stop gpsd.socket gpsd.service    # release the port
# ... raw ubxtool work ...
sudo systemctl start gpsd.socket gpsd.service   # hand it back to gpsd
```
`USBAUTO` re-grabs on a physical replug; don't replug mid-capture (or mask the
units if you need it bulletproof for a long unattended run).

## Timing mode
The F9T is a *timing* receiver — put it in stationary mode with a survey-in (or
a fixed surveyed position) for best timepulse stability. In moving/nav mode the
timepulse is far noisier. **Currently in nav mode** — confirmed `CFG-TMODE-MODE = 0`.

- [x] Read CFG-TMODE — `MODE = 0` (nav); all position/SVIN fields zero.
- [ ] Set survey-in: `CFG-TMODE-MODE = 1` (SURVEY_IN). Planned first pass:
      `SVIN_MIN_DUR = 3600 s`, `SVIN_ACC_LIMIT` (U4, units **0.1 mm**) — e.g.
      2 m = `20000`. RAM-only during bringup.
- [ ] Monitor `UBX-NAV-SVIN` until `valid = 1`; record surveyed position + variance.
- [ ] Confirm survey-in valid before trusting timing captures.

## Timepulse (TP) config — confirmed from CFG-TP (2026-07-07)
- TP1 enabled; 1 PPS (`PERIOD_TP1 = PERIOD_LOCK_TP1 = 1000000 µs`).
- Pulse width when GNSS-locked: 100 ms (`LEN_LOCK_TP1 = 100000 µs`); `LEN_TP1 = 0`
  (no pulse until lock). `ALIGN_TO_TOW_TP1 = 1`, `POL_TP1 = 1` (rising),
  `SYNC_GNSS_TP1 = 1`, `USE_LOCKED_TP1 = 1`. `ANT_CABLEDELAY = 50 ns`. TP2 off.
- `TIMEGRID_TP1 = 4 = GAL (Galileo)` as-found — firmware factory default
  (F9-TIM-2.25 Interface Description, Tables 70 & 115); PPS references Galileo
  System Time (confirmed by TIM-TP `refInfo=0x3`, `week=1402`). **DECISION
  2026-07-07: set to GPS (`TIMEGRID_TP1 = 1`), RAM-only** — APPLIED & confirmed 2026-07-07
  (TIM-TP now `refInfo=0x0`, `week=2426`).
- UBX-TIM-TP enabled on USB in **RAM only** (see Messages). `qErr` is reported in
  **picoseconds** (Int. Desc. p168); first-light values ±~3.4 ns.

## Messages to enable (for collectors)
On the USB port, at 1 Hz:
- UBX-TIM-TP (timepulse + quantization/sawtooth error) ← key for Stage 2.
  **Enabled in RAM 2026-07-07** via `CFG-MSGOUT-UBX_TIM_TP_USB=1` (RAM only, not
  yet persisted). `qErr` in ps.
- UBX-NAV-PVT / -SAT / -SIG / -POSECEF / -DOP / -VELECEF / -TIMEGPS / -EOE
  [already on by default on USB].
- Optional: UBX-NAV-TIMEUTC.

## Saved config
As-found baseline snapshot: `config/f9t/20260707-041251_asfound.txt` (MON-VER +
CFG-TMODE/TP/RATE/SIGNAL + TIM_TP_USB, RAM & default layers).

Read a config group from the running device (validated `-g <group>` form):
```bash
ubxtool -P 29.25 -f /dev/ttyACM0 -g CFG-TMODE     # or CFG-TP, CFG-RATE, CFG-SIGNAL
```
Write a config item (VALSET). **LAYERS is a decimal bitmask: RAM=1, BBR=2,
Flash=4.** ubxtool's default when LAYERS is omitted is **RAM+Flash (5)** — so for
RAM-only you MUST pass `,1`:
```bash
ubxtool -P 29.25 -f /dev/ttyACM0 -z CFG-MSGOUT-UBX_TIM_TP_USB,1,1   # RAM only
```

## Tooling notes
- `ubxtool` (gpsd 3.25) talks to the raw device with `-f /dev/ttyACM0` and the
  F9T protocol via `-P 29.25`. Confirmed working without sudo on this host.
- If gpsd is running it will hold `/dev/ttyACM0` (see Intake path). Stop it to
  talk raw, or read through gpsd (gpspipe) — not both at once.
