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
- Operating mode: **navigation** (not timing). Inferred from NAV-PVT motion
  (nonzero velocity, dithering position). Authoritative CFG-TMODE read: **TODO**.

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
timepulse is far noisier. **Currently in nav mode** (see Confirmed section;
CFG-TMODE read still pending).

- [ ] Read CFG-TMODE to record the current mode authoritatively.
- [ ] Set to stationary / TIME mode (CFG-TMODE-MODE).
- [ ] Survey-in: TODO min duration and TODO position accuracy threshold, OR
      program a known fixed ECEF/LLH position once survey converges.
- [ ] Confirm survey-in valid before trusting timing captures.

## Timepulse (TP) config
- [ ] Read CFG-TP to record current TP settings.
- [ ] TP frequency: 1 Hz (1 PPS) — CFG-TP.
- [ ] Pulse length / duty: TODO.
- [ ] Enable UBX-TIM-TP on USB so quantization error is logged (confirmed NOT in
      the default stream as of 2026-07-07).

## Messages to enable (for collectors)
On the USB port, enable at 1 Hz:
- UBX-TIM-TP    (timepulse + quantization/sawtooth error)  ← key for Stage 2, not on by default
- UBX-NAV-PVT / -STATUS (fix type)   [NAV-PVT already on by default]
- UBX-NAV-SAT or UBX-NAV-SIG (sats used)  [already on by default]
- Optional: UBX-NAV-TIMEUTC / -TIMEGPS   [TIMEGPS already on by default]

## Saved config
Goal: dump the live config to `config/f9t/` so it's version-controlled. Known
working read is the MON-VER poll above; the exact `ubxtool -g <group>` syntax for
CFG groups is being validated on this device (next step), so treat the commands
below as the intended method, not yet a proven recipe:
```bash
# read a config group from the running device (RAM/active layer):
ubxtool -P 29.25 -f /dev/ttyACM0 -g CFG-TMODE     # to validate
# then CFG-TP, CFG-MSGOUT, etc., and capture a full baseline into config/f9t/
```

## Tooling notes
- `ubxtool` (gpsd 3.25) talks to the raw device with `-f /dev/ttyACM0` and the
  F9T protocol via `-P 29.25`. Confirmed working without sudo on this host.
- If gpsd is running it will hold `/dev/ttyACM0` (see Intake path). Stop it to
  talk raw, or read through gpsd (gpspipe) — not both at once.
