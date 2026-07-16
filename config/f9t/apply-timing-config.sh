#!/usr/bin/env bash

# 0. Own the port (gpsd auto-manages the F9T)
sudo systemctl stop gpsd.socket gpsd.service

# 1. Confirm the device answers
ubxtool -P 29.25 -f /dev/ttyACM0 -p MON-VER | grep -E 'MOD=|FWVER='

# 2. PPS timepulse grid -> GPS   (RAM: layer 1)
ubxtool -P 29.25 -f /dev/ttyACM0 -z CFG-TP-TIMEGRID_TP1,1,1

# 3. Enable UBX-TIM-TP on USB    (sawtooth qErr)
ubxtool -P 29.25 -f /dev/ttyACM0 -z CFG-MSGOUT-UBX_TIM_TP_USB,1,1

# 4. Enable UBX-TIM-SVIN on USB  (survey-in status)
ubxtool -P 29.25 -f /dev/ttyACM0 -z CFG-MSGOUT-UBX_TIM_SVIN_USB,1,1

# 5. Survey-in: stop, set params, start   (SVIN_ACC_LIMIT is 0.1mm units; 1000000 = 100 m)
ubxtool -P 29.25 -f /dev/ttyACM0 -z CFG-TMODE-MODE,0,1
ubxtool -P 29.25 -f /dev/ttyACM0 -z CFG-TMODE-SVIN_MIN_DUR,120,1
ubxtool -P 29.25 -f /dev/ttyACM0 -z CFG-TMODE-SVIN_ACC_LIMIT,1000000,1
ubxtool -P 29.25 -f /dev/ttyACM0 -z CFG-TMODE-MODE,1,1

# 6. Verify what actually took (read-back)
ubxtool -P 29.25 -f /dev/ttyACM0 -w 4 -g CFG-TMODE

# 7. Watch survey / confirm timing mode
timeout 6 ubxtool -P 29.25 -f /dev/ttyACM0 -w 4 2>&1 | grep -A2 'UBX-TIM-SVIN'
