#!/usr/bin/env bash
# Encodes a 1080x1920 test picture with Android's hardware encoders and with x264, and
# shows the LD_LIBRARY_PATH failure. Runs inside proot-distro or in Termux (there:
# bash bench.sh); needs Termux's ffmpeg (in Termux: pkg install ffmpeg).
# FRAMES=600 bash bench.sh for a longer run.
set -u
TERMUX_FFMPEG="${TERMUX_FFMPEG:-/data/data/com.termux/files/usr/bin/ffmpeg}"
FRAMES="${FRAMES:-300}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TIMEFORMAT='%R %U %S'

# encode LABEL LD_LIBRARY_PATH-or-empty ENCODER-ARGS...
encode() {
  local label=$1 lib_path=$2 real user sys
  shift 2
  if { time env -u LD_LIBRARY_PATH ${lib_path:+LD_LIBRARY_PATH=$lib_path} "$TERMUX_FFMPEG" -hide_banner -v error -y \
      -f lavfi -i "testsrc2=size=1080x1920:rate=30" -frames:v "$FRAMES" "$@" -pix_fmt yuv420p \
      "$TMP/test.mp4" 2>"$TMP/err"; } 2>"$TMP/time"; then
    read -r real user sys < "$TMP/time"
    awk -v n="$FRAMES" -v r="$real" -v c="$(awk -v u="$user" -v s="$sys" 'BEGIN { print u + s }')" -v l="$label" \
      'BEGIN { printf "%-46s %6.1f frames/s %7.1f s CPU\n", l, n / r, c }'
  else
    printf '%-46s failed: %s\n' "$label" "$(tail -n 1 "$TMP/err")"
  fi
}

echo "Encoding $FRAMES frames of 1080x1920 with $TERMUX_FFMPEG"
echo "(the test picture is drawn on the CPU too, so every row includes that work)"
encode "h264_mediacodec (hardware)" "" -c:v h264_mediacodec -b:v 8M
encode "hevc_mediacodec (hardware)" "" -c:v hevc_mediacodec -b:v 6M
encode "libx264 -preset veryfast (CPU)" "" -c:v libx264 -preset veryfast
encode "libx264 -preset medium (CPU)" "" -c:v libx264 -preset medium
encode "h264_mediacodec, LD_LIBRARY_PATH=Termux lib" "${TERMUX_FFMPEG%/bin/ffmpeg}/lib" -c:v h264_mediacodec -b:v 8M
