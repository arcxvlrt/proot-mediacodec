# proot-mediacodec

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | **简体中文**

> 本译文借助了机器翻译。如有不通顺的地方，欢迎提 PR 修正。

在 [proot-distro](https://github.com/termux/proot-distro) 里使用 Android 的硬件视频编码器（`h264_mediacodec`、`hevc_mediacodec`）。直接用 Termux 自带的 `ffmpeg`，不需要 root，也不需要自己编译。

我在 Galaxy Tab 的 proot-distro Debian 里渲染 YouTube Shorts 时碰到了这个问题。Debian 的 ffmpeg 完全不支持 MediaCodec，而在容器里调用 Termux 的 ffmpeg 又总是报 `gralloc-mapper is missing` 退出。最后发现原因只是一个环境变量。

## 用法

在 Termux 中：

```sh
pkg install ffmpeg
```

在 proot 里用完整路径运行 Termux 的 ffmpeg，或者用本仓库的 `ffmpeg-hw`：

```sh
./ffmpeg-hw -i in.mp4 -c:v h264_mediacodec -b:v 8M -pix_fmt yuv420p out.mp4
```

只要 `LD_LIBRARY_PATH` 没有指向 Termux 的 `lib` 目录，就这么简单。

## `gralloc-mapper is missing`

设置了 `LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib` 时，硬件编码器会输出这条信息并退出，在 proot 里和普通 Termux 里都一样。有些安装教程为了让 Termux 程序能在 proot 里运行而加上这个路径，其实没必要：Termux 的程序会通过自己的 RUNPATH 找到库。`ffmpeg-hw` 只是去掉这个变量，再运行 Termux 的 ffmpeg。

我猜这时厂商的 gralloc mapper 把依赖库解析到了 Termux 的副本上，于是加载失败。[termux-x11 #960](https://github.com/termux/termux-x11/issues/960) 里也是同样的信息。

## 数据

`bench.sh` 把 1080x1920 的测试画面编码 300 帧。测试画面本身也由 CPU 绘制，所以每一行都包含这部分开销。

| 编码器 | proot 内（Debian） | Termux |
|---|---|---|
| `h264_mediacodec` | 59.2 fps，CPU 5.3 秒 | 84.7 fps，CPU 4.7 秒 |
| `hevc_mediacodec` | 57.7 fps，CPU 5.2 秒 | 92.4 fps，CPU 3.8 秒 |
| `libx264 -preset veryfast` | 39.7 fps，CPU 19.2 秒 | 56.0 fps，CPU 15.2 秒 |
| `libx264 -preset medium` | 33.0 fps，CPU 32.9 秒 | 35.3 fps，CPU 31.2 秒 |
| `h264_mediacodec`，`LD_LIBRARY_PATH` = Termux lib | gralloc-mapper is missing | gralloc-mapper is missing |

Galaxy Tab S9 FE+（Exynos 1380），Android 16，F-Droid 版 Termux 0.118.3，ffmpeg 9.0.2，Debian 13。我手上只有这一台设备，欢迎在 issue 里分享其他手机的数据。

硬件编码器占用的 CPU 时间大约是 x264 veryfast 的四分之一到三分之一（medium 的六分之一）。当另有程序在绘制画面时，这一点比 fps 更重要。proot 会跟踪系统调用，所以在 proot 里一切都会慢一些。

```sh
./bench.sh       # 在 proot 里
bash bench.sh    # 在 Termux 里
```

## 备注

- MediaCodec 用码率（`-b:v`），不支持 `-crf`。
- 输入用 `yuv420p` 或 `nv12`。
- 留着 `libx264 -preset veryfast` 作为备用，以防没有硬件编码器。
- 对我来说，编码其实并不是最慢的环节：MoviePy 每秒只能画大约 2 帧。把合成改成一个 ffmpeg 滤镜图并用 `h264_mediacodec` 编码后，30 秒的视频从大约 7 分钟缩短到 30～80 秒。

在 Python 中：

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

## 许可证

[MIT](LICENSE)
