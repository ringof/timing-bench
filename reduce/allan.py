#!/usr/bin/env python3
"""allan.py — overlapping Allan deviation (ADEV) from a phase/offset series.

Input:  TSV from parse_pps.py (or any two-column epoch<TAB>value file).
Output: TSV of  tau_s  adev  (one row per averaging time) on stdout, suitable
        for plots/adev.gp.

Takes a phase series (offset in seconds vs. time). If your input is in
nanoseconds, pass --ns to scale. Assumes ~1 Hz sampling by default; pass
--rate to override.

This is a standalone implementation (no allantools dependency) so the repo
stays light. Overlapping ADEV, octave-spaced tau.

Usage:
    python3 reduce/allan.py data/CAPTURE.tsv --col quant_err_ns --ns > data/CAPTURE.adev.tsv
"""
import argparse
import math
import sys


def read_series(path, col_name):
    xs = []
    with open(path) as f:
        header = f.readline().rstrip("\n").split("\t")
        try:
            idx = header.index(col_name)
        except ValueError:
            sys.exit(f"column '{col_name}' not in header: {header}")
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if idx >= len(parts):
                continue
            v = parts[idx]
            try:
                xs.append(float(v))
            except ValueError:
                xs.append(float("nan"))
    return xs


def overlapping_adev(phase, rate):
    """phase: list of phase values in seconds, sampled at `rate` Hz."""
    # Drop NaN entries rather than forward-filling. NaN appears when the chosen
    # column is sparse — e.g. a TIM-TP+NAV-PVT capture interleaves qErr rows with
    # NAV-PVT rows that carry no qErr. Forward-filling would duplicate each real
    # qErr across those rows and badly distort the ADEV. Dropping assumes the
    # surviving samples are ~uniformly spaced at `rate` (true for our 1 Hz qErr,
    # which had zero dropped timepulses); it is NOT gap-aware for real dropouts.
    x = [v for v in phase if not math.isnan(v)]
    N = len(x)
    if N < 3:
        return []
    tau0 = 1.0 / rate
    out = []
    m = 1
    while m <= (N - 1) // 2:
        s = 0.0
        count = 0
        for i in range(0, N - 2 * m):
            d = x[i + 2 * m] - 2 * x[i + m] + x[i]
            s += d * d
            count += 1
        if count > 0:
            tau = m * tau0
            adev = math.sqrt(s / (2 * count)) / tau
            out.append((tau, adev))
        m *= 2  # octave spacing
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tsv")
    ap.add_argument("--col", default="quant_err_ns",
                    help="column to analyze (default quant_err_ns)")
    ap.add_argument("--ns", action="store_true",
                    help="input is nanoseconds; scale to seconds")
    ap.add_argument("--rate", type=float, default=1.0,
                    help="sample rate Hz (default 1.0)")
    args = ap.parse_args()

    series = read_series(args.tsv, args.col)
    if args.ns:
        series = [v * 1e-9 if not math.isnan(v) else v for v in series]

    print("tau_s\tadev")
    for tau, adev in overlapping_adev(series, args.rate):
        print(f"{tau:g}\t{adev:g}")


if __name__ == "__main__":
    main()
