# Lab notebook

Dated entries, **newest on top**. Each entry: what was done, the capture file it
refers to (if any), and what the plot showed. Keep it terse and honest —
negative results are results.

---

## TEMPLATE (copy this block up top for each new entry)

### YYYY-MM-DD — short title
- **Setup:** F9T mode, survey-in state, what was connected.
- **Capture:** `data/YYYYMMDD-HHMMSS_<what>.log` (duration, rate).
- **Observed:** what the plots/numbers showed.
- **Next:** the one thing to do next.

---

### 2026-07-07 — first live contact; gpsd → raw ubxtool basis established
- **Setup:** SparkFun GNSS Timing Breakout (ZED-F9T-20B) on USB, `/dev/ttyACM0`
  (by-id `usb-u-blox_AG_-_www.u-blox.com_u-blox_GNSS_receiver-if00`). Confirmed
  via UBX-MON-VER: MOD=ZED-F9T-20B, FWVER=TIM 2.25, PROTVER=29.25, HW 00190000.
  Host had gpsd 3.25 auto-managing the port (`USBAUTO="true"` + `60-gpsd.rules`;
  boot `DEVICES=/dev/ttyUSB0`); stopped `gpsd.socket` + `gpsd.service` to take
  deterministic ownership for raw `ubxtool` (reversible via `systemctl start`).
  Receiver in default **navigation** mode (not timing/survey-in).
- **Capture:** none saved (interactive polls only; no file written).
- **Observed:** Healthy 3D fix — UBX-NAV-PVT fixType 3, ~13–20 SV used, GPS/
  Galileo/BeiDou/QZSS tracked (no GLONASS seen). Time valid: GPS week 2426,
  leapS 18, tAcc ~26 ns; receiver clock correct (2026-07-07). `ubxtool` 3.25
  does two-way UBX on the raw tty **without sudo**. Default USB output is the UBX
  nav set (NAV-PVT/-POSECEF/-VELECEF/-SAT/-SIG/-DOP/-TIMEGPS/-EOE); **UBX-TIM-TP
  is not in the default stream** (must be enabled for Stage 2). Aside: gpsd's SKY
  records carried a spurious 2019-04-09 timestamp while the receiver's own PVT/
  TIMEGPS time was correct — a gpsd labeling artifact, not the receiver.
- **Next:** read CFG-TMODE (then CFG-TP / TIM-TP message output) to capture the
  config baseline before changing anything.

---

### 0000-00-00 — repo initialized
- **Setup:** timing-bench scaffold created. F9T on USB, not yet characterized.
- **Capture:** none.
- **Observed:** n/a.
- **Next:** confirm F9T timing mode + survey-in (docs/f9t-setup.md), then take a
  first multi-hour Stage-1 capture.
