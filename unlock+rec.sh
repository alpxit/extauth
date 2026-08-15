#!/bin/bash

TS=`date`
IMGFMT=pgm
QRCODEPATH=/tmp/qrcode.$IMGFMT
LOGPATH=/tmp/unlockByQrCode.log
LOGPATH="/dev/tty"
SESSID=`loginctl list-sessions | grep $(whoami) | grep user | awk '{print $1}'`
TOTPKEYID=$(keyctl show | grep TOTPKEY | awk '{print $1}')
if [ -z $TOTPKEYID ]; then
  echo "Oops... TOTP key is absent!!!! alert...."
  exit
fi

# -r 0.5 -update 1 -vf "extractplanes=y,crop=800:720:200:0,scale=400:360" $QRCODEPATH \

rm -f $QRCODEPATH

ffmpeg -loglevel quiet -hide_banner -y \
 -f v4l2 -i /dev/video0 \
 -f alsa -sample_rate 44100 -i hw:CARD=PCH,DEV=0 \
 -map 0:v -map 1:a -f segment -strftime 1 -segment_time 43200 -strict experimental \
 -segment_format mpegts -fflags +genpts+igndts -muxdelay 0.1 -ac 1 -c:a aac -b:a 256k -c:v libx264 -crf 26 -preset veryfast -tune zerolatency -bf 0 -flush_packets 1 \
 /mnt/hdd/data/camcap_%Y-%m-%d_%H-%M-%S.ts \
 -map 0:v -vf "fps=2,format=gray" -c:v $IMGFMT -f image2pipe - | \
ffmpeg -loglevel quiet -hide_banner -y \
 -f image2pipe -i - -vf "select='gt(scene,0.10)'" -update 1 -c:v $IMGFMT -f image2 $QRCODEPATH &
ffpid=$!
ffpid1=$((ffpid-1))

sleep 1

loginctl lock-session $SESSID

sleep 1


while true
do

  sleep 2

#  inotifywait -qe 'create,moved_to' -t 10 $DWNLPATH
#  inotifywait -qqe 'close' -t 10 $QRCODEPATH

  if [ ! -f "$QRCODEPATH" ]; then
    continue
  fi

  TS=`date`
#  echo "$TS Wait until the file received..." >> $LOGPATH

  UNLOCKKEY=`zbarimg -q --raw $QRCODEPATH`
  rm -f $QRCODEPATH

  if [ ! -z "$UNLOCKKEY" ]; then
    THEKEY=`keyctl pipe $TOTPKEYID | oathtool -s 30 -d 6 -b --totp -`
    echo "keys need/recieved: $THEKEY==$UNLOCKKEY" >> $LOGPATH
#    ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/glass-water-1.wav" 2>/dev/null &
    if [ "$THEKEY" == "$UNLOCKKEY" ]; then
      echo "unlock sessionid $SESSID" >> $LOGPATH
#      kill -SIGQUIT $ffpid
      loginctl unlock-session $SESSID
      sleep 2
      kill -9  $ffpid $ffpid1   # workaround to prevent sustem UI frizing
#      ffplay -autoexit -nodisp -hide_banner "/usr/share/sounds/sound-icons/glass-water-1.wav" 2>/dev/null &
      exit
    else
      echo "Oops codes does not match... [$THEKEY] $UNLOCKKEY" >> $LOGPATH
    fi
  fi

done
