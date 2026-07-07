#!/usr/bin/env python3
"""parse_pps.py — reduce a raw timing capture into tidy TSV.

Input:  a raw capture from collect/ (ubxtool-decoded lines or gpsd JSON lines),
        each line prefixed with "host_epoch<TAB>payload".
Output: TSV on stdout with a stable column schema the gnuplot scripts expect:

    host_epoch  tp_offset_ns  quant_err_ns  fix_type  num_sv  survey_valid

Missing fields are emitted as NaN so gnuplot can skip them.

This is a functional stub: it handles the host-epoch prefix and the TSV schema,
and has clearly marked extraction points for the two input dialects. The exact
UBX-TIM-TP field names depend on the installed ubxtool decode format, so those
regexes are marked TODO and validated against a real capture during Stage 1.

Usage:
    python3 reduce/parse_pps.py data/CAPTURE.log > data/CAPTURE.tsv
"""
import sys
import json
import math
import re

NAN = float("nan")
COLUMNS = ["host_epoch", "tp_offset_ns", "quant_err_ns",
           "fix_type", "num_sv", "survey_valid"]


def fmt(v):
    if v is None:
        return "NaN"
    if isinstance(v, float) and math.isnan(v):
        return "NaN"
    return str(v)


def parse_ubx_line(payload, rec):
    """Extract fields from a ubxtool-decoded line. TODO: confirm field names.

    UBX-TIM-TP carries qErr (quantization error, ps in some builds / ns in
    others) and the timepulse offset. Adjust the regexes to the actual decode
    text once a real capture exists.
    """
    # TODO(validate): qErr units — ubxtool may report picoseconds. Normalize
    # to ns here so downstream is consistent.
    m = re.search(r"qErr[\s=:]+(-?\d+)", payload)
    if m:
        q = float(m.group(1))
        # assume ps -> ns until confirmed; TODO verify and drop the /1000.
        rec["quant_err_ns"] = q / 1000.0
    m = re.search(r"towMS[\s=:]+(-?\d+)", payload)  # placeholder anchor
    # TODO: derive tp_offset_ns from the appropriate TIM-TP subfields.
    m = re.search(r"numSV[\s=:]+(\d+)", payload)
    if m:
        rec["num_sv"] = int(m.group(1))
    m = re.search(r"gpsFix[\s=:]+(\d+)", payload)
    if m:
        rec["fix_type"] = int(m.group(1))
    return rec


def parse_gpsd_json(payload, rec):
    """Extract fields from a gpsd JSON line."""
    try:
        obj = json.loads(payload)
    except json.JSONDecodeError:
        return rec
    cls = obj.get("class")
    if cls == "TPV":
        if "mode" in obj:
            rec["fix_type"] = obj["mode"]          # 1=no fix,2=2D,3=3D
    elif cls == "SKY":
        used = obj.get("uSat")
        if used is None and "satellites" in obj:
            used = sum(1 for s in obj["satellites"] if s.get("used"))
        if used is not None:
            rec["num_sv"] = used
    elif cls in ("PPS", "TOFF"):
        # real_nsec / clock_nsec give the PPS offset; TODO map to tp_offset_ns.
        pass
    return rec


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: parse_pps.py CAPTURE.log > CAPTURE.tsv")
    path = sys.argv[1]

    print("\t".join(COLUMNS))
    with open(path, "r", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            # split host-epoch prefix from payload
            if "\t" in line:
                epoch, payload = line.split("\t", 1)
            else:
                epoch, payload = NAN, line
            rec = {c: NAN for c in COLUMNS}
            rec["host_epoch"] = epoch
            payload_s = payload.lstrip()
            if payload_s.startswith("{"):
                rec = parse_gpsd_json(payload_s, rec)
            else:
                rec = parse_ubx_line(payload_s, rec)
            # only emit rows that carried at least one timing/quality field
            if all(isinstance(rec[c], float) and math.isnan(rec[c])
                   for c in COLUMNS[1:]):
                continue
            print("\t".join(fmt(rec[c]) for c in COLUMNS))


if __name__ == "__main__":
    main()
