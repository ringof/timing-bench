#!/bin/sh
# ptp4l-gm-settings.sh — assert the grandmaster time-properties flags that
# ptp4l.conf cannot set (currentUtcOffsetValid / timeTraceable /
# frequencyTraceable) and that reset to 0 on every ptp4l start. Run as the
# ExecStartPost of ptp4l@enp3s0 (see config/i226/ptp4l@enp3s0.override.conf).
#
# currentUtcOffsetValid=0 would make a client distrust the +37 s offset and land
# on TAI. Retries until ptp4l's management socket answers. Best-effort: it never
# fails the unit (a boot loop is worse than briefly-wrong flags) — verify with
#   sudo pmc -u -b 0 'GET TIME_PROPERTIES_DATA_SET'
set -u

SETCMD='SET GRANDMASTER_SETTINGS_NP clockClass 6 clockAccuracy 0x21 offsetScaledLogVariance 0xffff currentUtcOffset 37 leap61 0 leap59 0 currentUtcOffsetValid 1 ptpTimescale 1 timeTraceable 1 frequencyTraceable 1 timeSource 0x20'

i=0
while [ "$i" -lt 10 ]; do
	if pmc -u -b 0 "$SETCMD" 2>/dev/null | grep -qE 'currentUtcOffsetValid[[:space:]]+1'; then
		exit 0
	fi
	i=$((i + 1))
	sleep 1
done

echo "ptp4l-gm-settings: pmc SET not confirmed after 10 tries" \
	| systemd-cat -t ptp4l-gm-settings -p warning
exit 0
