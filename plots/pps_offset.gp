# pps_offset.gp — F9T quantization (sawtooth) error vs time.
# Reads a TSV from reduce/parse_pps.py. Column schema:
#   1:host_epoch 2:tp_offset_ns 3:quant_err_ns 4:fix_type 5:num_sv 6:survey_valid
#
# Usage:
#   gnuplot plots/pps_offset.gp                       # newest data/*.tsv
#   gnuplot -e "DATA='data/xyz.tsv'" plots/pps_offset.gp

load "plots/common.gp"

set output "out/pps_offset.png"
set title "F9T timepulse quantization error vs time"
set xlabel "host epoch (s)"
set ylabel "quantization error (ns)"

# NaN-safe: gnuplot skips non-numeric / NaN rows automatically.
plot DATA using 1:3 with points ls 1 title "qErr (ns)"

print "wrote out/pps_offset.png from " . DATA
