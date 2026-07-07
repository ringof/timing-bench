# skyplot_sats.gp — sats-used and fix type over time (health signal).
# Reads parse_pps.py TSV. Columns:
#   1:host_epoch 2:tp_offset_ns 3:quant_err_ns 4:fix_type 5:num_sv 6:survey_valid
#
# Usage:
#   gnuplot plots/skyplot_sats.gp
#   gnuplot -e "DATA='data/xyz.tsv'" plots/skyplot_sats.gp

load "plots/common.gp"

set output "out/skyplot_sats.png"
set title "F9T fix quality: satellites used and fix type"
set xlabel "host epoch (s)"
set ylabel "satellites used"
set y2label "fix type"
set ytics nomirror
set y2tics
set y2range [0:5]

plot DATA using 1:5 with points ls 1 title "num SV used" axes x1y1, \
     DATA using 1:4 with points ls 2 title "fix type"    axes x1y2

print "wrote out/skyplot_sats.png from " . DATA
