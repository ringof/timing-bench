# adev.gp — Allan deviation (log-log) from reduce/allan.py output.
# Input TSV columns:  tau_s  adev
#
# Usage:
#   gnuplot -e "ADEVDATA='data/xyz.adev.tsv'" plots/adev.gp
# If ADEVDATA unset, picks newest data/*.adev.tsv.

load "plots/common.gp"

if (!exists("ADEVDATA")) \
    ADEVDATA = system("ls -t data/*.adev.tsv 2>/dev/null | head -1")

set output "out/adev.png"
set title "Allan deviation"
set xlabel "averaging time {/Symbol t} (s)"
set ylabel "{/Symbol s}_y({/Symbol t})"
set logscale xy
set format x "10^{%L}"
set format y "10^{%L}"
set key bottom left box opaque

plot ADEVDATA using 1:2 with linespoints ls 1 title "ADEV"

print "wrote out/adev.png from " . ADEVDATA
