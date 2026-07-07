# NEO-F9T setup (SparkFun board, USB)

Records how the F9T is configured so captures are reproducible. Fill the TODOs
with the actual values used once confirmed against the hardware.

## Device
- Board: SparkFun NEO-F9T
- Connection: USB CDC-ACM. Appears as `/dev/ttyACM0` (verify: `dmesg | grep -i cdc_acm`)
- The F9T also emits a hardware PPS on its TIMEPULSE pin; USB is only the
  config/telemetry path. End-to-end PPS assessment (Stage 3) uses that pin into
  the i226 SDP, not USB.

## Timing mode
The F9T is a *timing* receiver — put it in stationary mode with a survey-in (or
a fixed surveyed position) for best timepulse stability. In moving/nav mode the
timepulse is far noisier.

- [ ] Set to stationary / TIME mode (CFG-TMODE).
- [ ] Survey-in: TODO min duration (e.g. 86400 s) and TODO position accuracy
      threshold (e.g. 2.0 m), OR program a known fixed ECEF/LLH position once
      survey converges.
- [ ] Confirm survey-in valid before trusting timing captures.

## Timepulse (TP) config
- [ ] TP frequency: 1 Hz (1 PPS) — CFG-TP.
- [ ] Pulse length / duty: TODO.
- [ ] Confirm UBX-TIM-TP messages enabled on the USB port so quantization
      error is logged.

## Messages to enable (for collectors)
On the USB port, enable at 1 Hz:
- UBX-TIM-TP    (timepulse + quantization/sawtooth error)  ← key for Stage 2
- UBX-NAV-STATUS (fix type)
- UBX-NAV-SAT or UBX-NAV-SIG (sats used)
- Optional: UBX-NAV-TIMEUTC / -TIMEGPS

## Saved config
Dump the live config to `config/f9t/` so it's version-controlled:
```bash
# with ubxtool (gpsd):
ubxtool -p CFG-VALGET ...   # TODO exact keys
# or save the u-center config .txt into config/f9t/
```

## Tooling notes
- `ubxtool` ships with gpsd. `gpspipe` for NMEA/JSON stream.
- If gpsd is running it will hold `/dev/ttyACM0`; stop it to talk raw, or read
  through gpsd (gpspipe) instead. Don't do both at once.
