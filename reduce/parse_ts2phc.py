#!/usr/bin/env python3
"""parse_ts2phc.py — reduce a ts2phc "-m" capture into tidy TSV.

Input:  a ts2phc "-m" log (one line per second), e.g.
            ts2phc[41577.060]: /dev/ptp0 offset        7 s2 freq  +10483
        offset = PHC-vs-PPS phase error (ns); freq = applied frequency
        correction (ppb); sN = servo state (s2 = locked).

Output: TSV on stdout with a header the reducer/plots expect:

            elapsed_s   offset_ns   freq_ppb

        elapsed_s = seconds since the first kept sample (ts2phc's own monotonic
        timestamp, differenced). Feed offset_ns to reduce/allan.py
        (--col offset_ns --ns); elapsed_s+offset_ns to plots/pps_offset.gp;
        freq_ppb gives the oscillator-drift view.

Trims the lock-in transient: drops all leading non-locked (non-s2) samples plus
a settling guard (--settle) so the initial phase ramp doesn't swamp short-tau
ADEV. Any mid-run loss of lock (a non-s2 sample after the initial lock) or
timestamp gap is skipped and WARNED to stderr, rather than silently distorting
the series — allan.py assumes uniform 1 Hz, so a gap is a real caveat.

Usage:
    python3 reduce/parse_ts2phc.py data/ts2phc_longrun_XXXX.log > data/out.tsv
    python3 reduce/allan.py data/out.tsv --col offset_ns --ns > data/out.adev.tsv
"""
import argparse
import math
import sys
import re

# ts2phc[<mono_s>]: <clock> offset <ns> s<state> freq <ppb>
LINE_RE = re.compile(
    r"ts2phc\[(\d+\.\d+)\]:\s+\S+\s+offset\s+(-?\d+)\s+s(\d)\s+freq\s+([+-]?\d+)"
)


def parse(path, settle):
    """Return list of kept (mono_s, offset_ns, freq_ppb); report to stderr."""
    rows = []
    n_lines = 0
    with open(path, errors="replace") as f:
        for line in f:
            m = LINE_RE.search(line)
            if not m:
                continue
            n_lines += 1
            rows.append((float(m.group(1)), int(m.group(2)),
                         int(m.group(3)), int(m.group(4))))

    if not rows:
        sys.exit(f"no ts2phc offset lines found in {path}")

    # first locked (s2) sample, then drop `settle` more as a settling guard
    first_lock = next((i for i, r in enumerate(rows) if r[2] == 2), None)
    if first_lock is None:
        sys.exit("never reached servo state s2 (locked) — nothing to reduce")
    start = first_lock + settle

    kept = []
    n_relock = n_gap = 0
    prev_mono = None
    for mono, off, state, freq in rows[start:]:
        if state != 2:
            n_relock += 1        # lost lock mid-run: skip, don't distort ADEV
            prev_mono = None     # a skipped sample breaks continuity
            continue
        if prev_mono is not None and (mono - prev_mono) > 1.5:
            n_gap += 1           # missing second(s) between kept samples
        prev_mono = mono
        kept.append((mono, off, freq))

    _summary(n_lines, start, kept, n_relock, n_gap)
    return kept


def _summary(n_lines, dropped, kept, n_relock, n_gap):
    w = sys.stderr.write
    w(f"[parse_ts2phc] parsed {n_lines} lines; dropped {dropped} "
      f"(pre-lock+settle); kept {len(kept)}\n")
    if kept:
        dur = kept[-1][0] - kept[0][0]
        offs = [k[1] for k in kept]
        mean = sum(offs) / len(offs)
        rms = math.sqrt(sum((o - mean) ** 2 for o in offs) / len(offs))
        f0, f1 = kept[0][2], kept[-1][2]
        w(f"[parse_ts2phc] span {dur:.0f} s ({dur/3600:.2f} h); "
          f"offset mean {mean:.2f} ns rms {rms:.2f} ns; "
          f"freq {f0:+d} -> {f1:+d} ppb (drift {f1 - f0:+d})\n")
    if n_relock:
        w(f"[parse_ts2phc] WARNING: {n_relock} mid-run non-s2 sample(s) skipped "
          f"(lost lock)\n")
    if n_gap:
        w(f"[parse_ts2phc] WARNING: {n_gap} timestamp gap(s) >1.5 s in kept "
          f"series — breaks allan.py's uniform-1 Hz assumption\n")


def main():
    ap = argparse.ArgumentParser(description="reduce a ts2phc -m log to TSV")
    ap.add_argument("log", help="ts2phc -m capture file")
    ap.add_argument("--settle", type=int, default=30,
                    help="samples to drop after first s2 lock "
                         "(settling guard, default 30)")
    args = ap.parse_args()

    kept = parse(args.log, args.settle)
    t0 = kept[0][0]
    print("elapsed_s\toffset_ns\tfreq_ppb")
    for mono, off, freq in kept:
        print(f"{mono - t0:.3f}\t{off}\t{freq}")


if __name__ == "__main__":
    main()
