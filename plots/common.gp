# common.gp — shared gnuplot defaults. `load` this at the top of each script
# so all outputs share one look and style changes happen in one place.

set terminal pngcairo size 1100,620 enhanced font "Sans,11"
set grid lw 1 lc rgb "#dddddd"
set border lw 1 lc rgb "#666666"
set key top right box opaque
set tics nomirror
set style line 1 lc rgb "#1f6feb" lw 2 pt 7 ps 0.5   # primary series
set style line 2 lc rgb "#d1242f" lw 2 pt 7 ps 0.5   # secondary/compare
set style line 3 lc rgb "#2da44e" lw 2 pt 7 ps 0.5   # tertiary

# Helper: newest matching file in data/. Override DATA on the command line:
#   gnuplot -e "DATA='data/xyz.tsv'" plots/pps_offset.gp
if (!exists("DATA")) DATA = system("ls -t data/*.tsv 2>/dev/null | head -1")
