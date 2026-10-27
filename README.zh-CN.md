# proot-mediacodec

[English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md) | **简体中文**

在 [Termux](https://termux.dev) 的 [proot-distro](https://github.com/termux/proot-distro) 中运行的 Linux 发行版里，使用 Android 设备的硬件视频编码器（MediaCodec：`h264_mediacodec`、`hevc_mediacodec`）。无需 root，也无需自行编译：只要在容器里调用 Termux 软件源自带的 `ffmpeg` 软件包。

## 快速开始

1. 在 Termux 中（proot 之外）：
   ```sh
   pkg install ffmpeg
   ffmpeg -hide_banner -encoders | grep mediacodec   # h264_mediacodec, hevc_mediacodec, ...
   ```
2. 在 proot-distro 中用完整路径运行 Termux 的 ffmpeg，或者把 `ffmpeg-hw` 放进 PATH：
   ```sh
   ./ffmpeg-hw -i input.mp4 -c:v h264_mediacodec -b:v 8M -pix_fmt yuv420p output.mp4
   ```
3. 不要让 `LD_LIBRARY_PATH` 指向 Termux 的 `lib` 目录。设置了 `LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib` 时，硬件编码器会报下面的错误并退出：
   ```
   gralloc-mapper is missing
   ```
   在普通 Termux 中也一样。有些教程为了在 proot 中运行 Termux 程序而设置这个变量，其实并不需要：Termux 的程序通过内置的 RUNPATH 找到自己的库。`ffmpeg-hw` 会在启动 ffmpeg 之前删除这个变量。

## 原理

Debian 的 ffmpeg 是为 glibc Linux 编译的，不支持 MediaCodec。Termux 的 ffmpeg 是为 Android 编译的，启用了 MediaCodec。proot-distro 在容器内仍然能看到 Termux 的前缀目录和 Android 系统目录（`/system`、`/vendor`、`/apex`、`/linkerconfig`），容器里的进程也仍然以 Termux 应用的身份运行，所以这个 ffmpeg 能像在 Termux 中一样访问厂商的编解码库和媒体服务。

当 `LD_LIBRARY_PATH` 中有 Termux 的 `lib` 目录时，厂商的图形缓冲区映射器（gralloc）会加载失败，推测是它依赖的库被解析到了 Termux 的副本。随后 Android 的 libui 输出上面的信息并终止程序。[termux-x11 #960](https://github.com/termux/termux-x11/issues/960) 中也出现了同样的信息。

## 基准测试

`bench.sh` 把 1080x1920 的测试画面编码 300 帧。测试画面同样由 CPU 绘制，所以每一行都包含这部分工作。

| 编码器 | proot-distro Debian 内 | Termux |
|---|---|---|
| `h264_mediacodec`（硬件） | 59.2 fps，CPU 5.3 秒 | 84.7 fps，CPU 4.7 秒 |
| `hevc_mediacodec`（硬件） | 57.7 fps，CPU 5.2 秒 | 92.4 fps，CPU 3.8 秒 |
| `libx264 -preset veryfast` | 39.7 fps，CPU 19.2 秒 | 56.0 fps，CPU 15.2 秒 |
| `libx264 -preset medium` | 33.0 fps，CPU 32.9 秒 | 35.3 fps，CPU 31.2 秒 |
| `LD_LIBRARY_PATH` 指向 Termux lib 时的 `h264_mediacodec` | gralloc-mapper is missing | gralloc-mapper is missing |

硬件编码器更快，而且几乎不占用 CPU（CPU 时间只有 x264 veryfast 的四到六分之一），可以把 CPU 留给绘制画面的程序。proot 会跟踪系统调用，所以容器内整体会慢一些。

测试设备：三星 Galaxy Tab S9 FE+（Exynos 1380），Android 16 / One UI 8.5，Termux 0.118.3（F-Droid），Termux 的 ffmpeg 9.0.2，proot-distro Debian 13。其他设备尚未测试，欢迎在 issue 中分享其他手机和平板的结果。

```sh
./bench.sh       # 在 proot-distro 中
bash bench.sh    # 在 Termux 中
```

## 提示

- MediaCodec 编码器用码率（`-b:v 8M`）控制画质，不支持 `-crf`。
- 输入 `-pix_fmt yuv420p`（或 `nv12`）。
- 保留 CPU 备用方案：硬件编码器失败时，用 `libx264 -preset veryfast` 重新编码。
- 编码往往不是最慢的环节。在产生这个方法的短视频流程中，用 Python（MoviePy）绘制画面每秒只有约 2 帧。把合成改为一个 ffmpeg 滤镜图（`scale` 的 `eval=frame`、`overlay`、`xfade`）并用 `h264_mediacodec` 编码后，30 秒视频的渲染从约 7 分钟缩短到 30～80 秒。

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
