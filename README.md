# proot-mediacodec

**English** | [한국어](README.ko.md) | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

Use Android's hardware video encoder (`h264_mediacodec`, `hevc_mediacodec`) from inside [proot-distro](https://github.com/termux/proot-distro), with the stock Termux `ffmpeg`. No root, no custom build.

I ran into this while rendering YouTube Shorts on a Galaxy Tab in proot-distro Debian. Debian's ffmpeg has no MediaCodec at all, and Termux's ffmpeg kept dying with `gralloc-mapper is missing` when I called it from the container. It turned out to be one environment variable.

## Usage

In Termux:

```sh
pkg install ffmpeg
```

Inside proot, run Termux's ffmpeg by its full path, or use `ffmpeg-hw` from this repo:

```sh
./ffmpeg-hw -i in.mp4 -c:v h264_mediacodec -b:v 8M -pix_fmt yuv420p out.mp4
```

That's all, as long as `LD_LIBRARY_PATH` doesn't point at Termux's `lib` folder.

## `gralloc-mapper is missing`

With `LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib`, the hardware encoder aborts with that message, inside proot and in plain Termux alike. Some setup guides add this path so Termux binaries run inside proot. They don't need it: Termux binaries find their libraries through their own RUNPATH. `ffmpeg-hw` just unsets the variable and runs Termux's ffmpeg.

My guess is that the vendor's gralloc mapper then picks up Termux's copies of the libraries it depends on and fails to load. [termux-x11 #960](https://github.com/termux/termux-x11/issues/960) shows the same message.

## Numbers

`bench.sh` encodes 300 frames of a 1080x1920 test picture. The picture itself is drawn on the CPU, so that work is in every row.

| Encoder | inside proot (Debian) | Termux |
|---|---|---|
| `h264_mediacodec` | 59.2 fps, 5.3 s CPU | 84.7 fps, 4.7 s CPU |
| `hevc_mediacodec` | 57.7 fps, 5.2 s CPU | 92.4 fps, 3.8 s CPU |
| `libx264 -preset veryfast` | 39.7 fps, 19.2 s CPU | 56.0 fps, 15.2 s CPU |
| `libx264 -preset medium` | 33.0 fps, 32.9 s CPU | 35.3 fps, 31.2 s CPU |
| `h264_mediacodec`, `LD_LIBRARY_PATH` = Termux lib | gralloc-mapper is missing | gralloc-mapper is missing |

Galaxy Tab S9 FE+ (Exynos 1380), Android 16, Termux 0.118.3 from F-Droid, ffmpeg 9.0.2, Debian 13. It's the only device I have, so numbers from other phones are welcome in an issue.

The hardware encoder needs roughly a quarter to a third of the CPU time of x264 veryfast (a sixth of medium), which matters more than the fps when something else is drawing the frames. Everything is slower inside proot because proot traces system calls.

```sh
./bench.sh       # inside proot
bash bench.sh    # in Termux
```

## Notes

- MediaCodec takes a bitrate (`-b:v`), not `-crf`.
- Feed it `yuv420p` or `nv12`.
- Keep `libx264 -preset veryfast` as a fallback for when the hardware encoder isn't there.
- For me encoding wasn't even the slow part: MoviePy drew frames at about 2 fps. Doing the compositing in a single ffmpeg filter graph and encoding with `h264_mediacodec` took a 30-second video from about 7 minutes to 30-80 seconds.
- If the video is made of still photos, don't feed them with `-loop 1`: that reads and decodes the file again for every frame. Give each photo as a single frame and repeat it in the filter graph instead (`-framerate 30 -i photo.png` with `format=yuv420p,tpad=stop_mode=clone:stop_duration=6,trim=duration=6`). In my 30-second slideshow the ffmpeg time dropped by about 40% (88 s to 47 s) with the same output. This only helps with stills; video clips have a different picture in every frame anyway. Text that never changes works the same way: draw it into the background image once instead of overlaying it on every frame.

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

## License

[MIT](LICENSE)
