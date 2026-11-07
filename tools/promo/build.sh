#!/bin/zsh
set -e
cd ${0:A:h}
ENC=(-c:v libx264 -pix_fmt yuv420p -preset medium -crf 20 -r 30 -an)
# scéna z videa: src start end speed frame_png out
scene() {
  local src=$1 s=$2 e=$3 sp=$4 fr=$5 out=$6 hold=${7:-0}
  ffmpeg -v error -y -i $src -loop 1 -i gfx/$fr.png -filter_complex "
    [0:v]fps=30,trim=$s:$e,setpts=(PTS-STARTPTS)/$sp,tpad=stop_mode=clone:stop_duration=$hold,scale=700:1519,setsar=1[v];
    color=c=0x0B0D12:s=1080x1920:r=30[bg];
    [bg][v]overlay=190:361:shortest=1[x];
    [x][1:v]overlay=0:0:shortest=1,fade=t=in:st=0:d=0.3,format=yuv420p[o]" -map "[o]" $ENC seg/$out.mp4
  local d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 seg/$out.mp4)
  ffmpeg -v error -y -i seg/$out.mp4 -vf "fade=t=out:st=$(echo "$d - 0.3" | bc):d=0.3" $ENC seg/${out}_f.mp4 && mv seg/${out}_f.mp4 seg/$out.mp4
}
card() { ffmpeg -v error -y -loop 1 -t $2 -i gfx/$1.png -vf "fps=30,format=yuv420p,fade=t=in:st=0:d=0.4,fade=t=out:st=$(echo "$2 - 0.4" | bc):d=0.4" $ENC seg/$3.mp4; }
card intro 3 s00
scene raw.mp4 18.3 30.3 1.2 frame_feed s01
scene raw.mp4 37.8 48.2 1.2 frame_night s02
scene raw.mp4 67.5 75.9 1.0 frame_challenges s03
scene raw.mp4 83.2 91.6 1.0 frame_challenge s04
scene result.mp4 2.55 3.18 1.0 frame_result s05 3.5
scene raw.mp4 98.8 111.3 1.2 frame_profile s06
scene raw.mp4 119.8 126.8 1.0 frame_recap s07
scene raw.mp4 136.1 155.8 1.5 frame_wrapped s08
scene settings.mp4 2.5 2.95 1.0 frame_settings s09 3
card outro 3 s10
ls seg/s*.mp4 | sort | sed "s/^/file '/;s/$/'/" > list.txt
ffmpeg -v error -y -f concat -safe 0 -i list.txt -c copy promo.mp4
ffprobe -v error -show_entries format=duration -of csv=p=0 promo.mp4
