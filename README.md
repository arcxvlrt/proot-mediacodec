# proot-mediacodec

Hardware video encoding on Android (MediaCodec: `h264_mediacodec`, `hevc_mediacodec`) from a Linux distro running in [proot-distro](https://github.com/termux/proot-distro) on [Termux](https://termux.dev). No root and no custom build: you call Termux's own ffmpeg from inside the container.

## Quick start

1. In Termux (outside proot):
   ```sh
   pkg install ffmpeg
   ffmpeg -hide_banner -encoders | grep mediacodec   # h264_mediacodec, hevc_mediacodec, ...
   ```
2. Inside proot-distro, run Termux's ffmpeg by its full path, or put `ffmpeg-hw` on your PATH:
   ```sh
   ./ffmpeg-hw -i input.mp4 -c:v h264_mediacodec -b:v 8M -pix_fmt yuv420p output.mp4
   ```
3. Keep `LD_LIBRARY_PATH` away from Termux's `lib` folder. With `LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib` the hardware encoder aborts with
   ```
   gralloc-mapper is missing
   ```
   This happens in plain Termux too. Some guides export that variable so Termux programs run inside proot, but they don't need it: Termux binaries find their libraries through their built-in RUNPATH. `ffmpeg-hw` removes the variable before it starts ffmpeg.

## Why it works

Debian's ffmpeg is built for glibc Linux and has no MediaCodec support. Termux's ffmpeg is built for Android with MediaCodec enabled. proot-distro keeps Termux's prefix and the Android system folders (`/system`, `/vendor`, `/apex`, `/linkerconfig`) visible inside the container, and everything in it still runs as the Termux app, so that ffmpeg reaches the vendor's codec libraries and the media service just as it does in Termux.

With Termux's `lib` folder on `LD_LIBRARY_PATH`, loading the vendor's graphics buffer mapper (gralloc) fails, presumably because it picks up Termux's copies of libraries it depends on, and Android's libui aborts with the message above. The same message appears in [termux-x11 #960](https://github.com/termux/termux-x11/issues/960).

## Benchmark

`bench.sh` encodes 300 frames of a 1080x1920 test picture. The picture is drawn on the CPU too, so every row includes that work.

| Encoder | inside proot-distro Debian | in Termux |
|---|---|---|
| `h264_mediacodec` (hardware) | 59.2 fps, 5.3 s CPU | 84.7 fps, 4.7 s CPU |
| `hevc_mediacodec` (hardware) | 57.7 fps, 5.2 s CPU | 92.4 fps, 3.8 s CPU |
| `libx264 -preset veryfast` | 39.7 fps, 19.2 s CPU | 56.0 fps, 15.2 s CPU |
| `libx264 -preset medium` | 33.0 fps, 32.9 s CPU | 35.3 fps, 31.2 s CPU |
| `h264_mediacodec` with `LD_LIBRARY_PATH` = Termux lib | gralloc-mapper is missing | gralloc-mapper is missing |

The hardware encoder is faster and leaves the CPU almost free (4-6 times less CPU time than x264 veryfast) for whatever draws the frames. proot traces system calls, so everything is somewhat slower inside the container.

Measured on a Samsung Galaxy Tab S9 FE+ (Exynos 1380), Android 16 / One UI 8.5, Termux 0.118.3 (F-Droid), Termux's ffmpeg 9.0.2, proot-distro Debian 13. Other devices are untested; numbers from other phones and tablets are welcome in an issue.

```sh
./bench.sh       # inside proot-distro
bash bench.sh    # in Termux
```

## Tips

- MediaCodec encoders take a bitrate (`-b:v 8M`), not `-crf`.
- Give them `-pix_fmt yuv420p` (or `nv12`).
- Keep a CPU fallback: if the hardware encoder fails, encode again with `libx264 -preset veryfast`.
- Encoding is often not the slow part. In the Shorts pipeline this came from, drawing frames in Python (MoviePy) ran at about 2 frames/s. Doing the compositing in one ffmpeg filter graph (`scale` with `eval=frame`, `overlay`, `xfade`) and encoding with `h264_mediacodec` cut the render of a 30-second video from about 7 minutes to 30-80 seconds.

From Python:

```python
import os
import subprocess

TERMUX_FFMPEG = "/data/data/com.termux/files/usr/bin/ffmpeg"
env = {name: value for name, value in os.environ.items() if name != "LD_LIBRARY_PATH"}

for encoder in (["-c:v", "h264_mediacodec", "-b:v", "8M"], ["-c:v", "libx264", "-preset", "veryfast"]):
    command = [TERMUX_FFMPEG, "-y", "-i", "in.mp4", *encoder, "-pix_fmt", "yuv420p", "out.mp4"]
    if subprocess.run(command, env=env).returncode == 0:
        break
```

## 한국어 요약

안드로이드 폰·태블릿의 Termux에서 proot-distro로 띄운 리눅스(Debian 등) 안에서도 기기의 하드웨어 영상 인코더(MediaCodec)를 쓸 수 있어요.

1. Termux에서 `pkg install ffmpeg`
2. proot 안에서 Termux의 ffmpeg를 전체 경로(`/data/data/com.termux/files/usr/bin/ffmpeg`)로 실행하거나 `ffmpeg-hw`를 쓰고, `-c:v h264_mediacodec -b:v 8M`으로 인코딩
3. `LD_LIBRARY_PATH`에 Termux의 lib 폴더가 들어 있으면 `gralloc-mapper is missing` 오류로 꺼져요. 이 변수만 빼면 돼요.

갤럭시 탭 S9 FE+에서 하드웨어 인코딩은 x264보다 빠르고 CPU는 4~6배 덜 써요(위 표).

## License

[MIT](LICENSE)
