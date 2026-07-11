# ts2phc_offset.gp — i226 PHC-vs-PPS offset and the ts2phc frequency correction,
# vs time, from a reduce/parse_ts2phc.py TSV. Column schema:
#   1:elapsed_s  2:offset_ns  3:freq_ppb
#
# Writes two PNGs:
#   out/ts2phc_offset.png  — PHC-PPS phase offset (ns) vs time   [headline]
#   out/ts2phc_freq.png    — ts2phc frequency correction (ppb) vs time (XO drift)
#
# Usage:
#   gnuplot -e "DATA='data/ts2phc_longrun.tsv'" plots/ts2phc_offset.gp
#   gnuplot plots/ts2phc_offset.gp                 # else newest data/*.tsv
#
# NOTE: this is the PHC-vs-PPS *servo residual* (how tightly ts2phc tracks the
# PPS edge), not absolute accuracy vs an independent clock.

load "plots/common.gp"

set xlabel "time since lock (s)"

# --- phase offset (the headline) ---
set output "out/ts2phc_offset.png"
set title "i226 PHC vs F9T PPS — phase offset (ts2phc servo residual)"
set ylabel "PHC {/Symbol -} PPS offset (ns)"
plot DATA using 1:2 with points ls 1 ps 0.2 title "offset (ns)"
print "wrote out/ts2phc_offset.png from " . DATA

# --- frequency correction (the oscillator drift the loop absorbs) ---
set output "out/ts2phc_freq.png"
set title "i226 PHC — ts2phc frequency correction (oscillator drift)"
set ylabel "frequency correction (ppb)"
plot DATA using 1:3 with lines ls 3 title "freq (ppb)"
print "wrote out/ts2phc_freq.png from " . DATA
