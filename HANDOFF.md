# Handoff notes

State of the repo at handoff, and the shortest path to being productive.

## What works right now (verified)
The full pipeline runs end to end on synthetic sample data committed under
`data/sample_*`:

```
collect/  →  reduce/parse_pps.py  →  reduce/allan.py  →  plots/*.gp  →  out/*.png
```

- `reduce/parse_pps.py` parses gpsd-JSON captures into the tidy TSV schema.
- `reduce/allan.py` computes overlapping ADEV (standalone, no allantools).
- All three gnuplot scripts render (`pps_offset`, `adev`, `skyplot_sats`).
- Sample ADEV shows the expected ~τ^-0.5 slope, confirming the math.

Regenerate the sample outputs anytime:
```bash
python3 reduce/parse_pps.py data/sample_gpsd-json.log > data/sample_gpsd-json.tsv
python3 reduce/allan.py data/sample_phase.tsv --col quant_err_ns --ns > data/sample_phase.adev.tsv
gnuplot -e "DATA='data/sample_gpsd-json.tsv'" plots/skyplot_sats.gp
gnuplot -e "ADEVDATA='data/sample_phase.adev.tsv'" plots/adev.gp
gnuplot -e "DATA='data/sample_phase.tsv'" plots/pps_offset.gp
```

## What is stubbed and needs real hardware to finish
The collectors and the UBX side of the parser are written against expected
formats but **not yet validated against a live F9T** — the sample data is
synthetic. Concrete TODOs, in order:

1. **F9T config** (`docs/f9t-setup.md`): fill in the actual timing-mode /
   survey-in / TP values used, and dump live config into `config/f9t/`.
2. **UBX field names** (`reduce/parse_pps.py`, `parse_ubx_line`): the
   `qErr` / `numSV` / `gpsFix` regexes are guesses. Take one real
   `log_ubx_timing.sh` capture and confirm the exact ubxtool decode text,
   then fix the regexes and the **qErr units** (ps vs ns — there's a TODO
   marking the assumed ps→ns divide).
3. **ubxtool invocation** (`collect/log_ubx_timing.sh`): confirm `-e`/`-w`
   flags against the installed gpsd/ubxtool version.
4. Take a first real multi-hour Stage-1 capture and log it in
   `docs/notebook.md`.

## Decision left open for Katie
Which intake path is primary — **ubxtool** (better for sawtooth/qErr, Stage 2)
or **gpsd/gpspipe** (convenient if gpsd already manages the device). Both
collectors exist; the plan (`docs/00-plan.md`) leans ubxtool for timing work.

## Roadmap pointer
`docs/00-plan.md` has the staged plan. Stages 1–2 (F9T self-assessment) need
only the USB device. Stage 3 (PPS-vs-PHC via i226 SDP EXTTS) is the headline
end-to-end number and is gated on the i226 install.
