# proot-mediacodec

[English](README.md) | [한국어](README.ko.md) | **日本語** | [简体中文](README.zh-CN.md)

[Termux](https://termux.dev) 上の [proot-distro](https://github.com/termux/proot-distro) で動かす Linux ディストリビューションから、Android 端末のハードウェア動画エンコーダー（MediaCodec: `h264_mediacodec`、`hevc_mediacodec`）を使う方法です。root もビルドも不要で、Termux リポジトリ標準の `ffmpeg` パッケージをコンテナ内から呼び出すだけです。

## クイックスタート

1. Termux で（proot の外）:
   ```sh
   pkg install ffmpeg
   ffmpeg -hide_banner -encoders | grep mediacodec   # h264_mediacodec, hevc_mediacodec, ...
   ```
2. proot-distro の中で Termux の ffmpeg をフルパスで実行するか、`ffmpeg-hw` を PATH に置いて使います:
   ```sh
   ./ffmpeg-hw -i input.mp4 -c:v h264_mediacodec -b:v 8M -pix_fmt yuv420p output.mp4
   ```
3. `LD_LIBRARY_PATH` に Termux の `lib` フォルダーを入れないでください。`LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib` だと、ハードウェアエンコーダーは次のエラーで異常終了します。
   ```
   gralloc-mapper is missing
   ```
   素の Termux でも同じです。proot 内で Termux のプログラムを動かすためにこの変数を設定するよう勧めるガイドもありますが、不要です。Termux のバイナリは組み込みの RUNPATH で自分のライブラリを見つけます。`ffmpeg-hw` は ffmpeg を起動する前にこの変数を消します。

## なぜ動くのか

Debian の ffmpeg は glibc の Linux 向けにビルドされていて、MediaCodec に対応していません。Termux の ffmpeg は Android 向けに MediaCodec を有効にしてビルドされています。proot-distro はコンテナ内でも Termux のプレフィックスと Android のシステムフォルダー（`/system`、`/vendor`、`/apex`、`/linkerconfig`）をそのまま見せ、中のプロセスも Termux アプリとして動きます。そのため、この ffmpeg は Termux 上と同じようにメーカーのコーデックライブラリとメディアサービスに届きます。

`LD_LIBRARY_PATH` に Termux の `lib` フォルダーがあると、メーカーのグラフィックバッファーマッパー（gralloc）の読み込みに失敗します。依存ライブラリとして Termux 側のコピーを拾ってしまうためと考えられます。すると Android の libui が上のメッセージを出して異常終了します。同じメッセージは [termux-x11 #960](https://github.com/termux/termux-x11/issues/960) にも出ています。

## ベンチマーク

`bench.sh` は 1080x1920 のテスト画像を 300 フレームエンコードします。テスト画像も CPU で描くので、どの行にもその処理が含まれます。

| エンコーダー | proot-distro Debian 内 | Termux |
|---|---|---|
| `h264_mediacodec`（ハードウェア） | 59.2 fps、CPU 5.3 秒 | 84.7 fps、CPU 4.7 秒 |
| `hevc_mediacodec`（ハードウェア） | 57.7 fps、CPU 5.2 秒 | 92.4 fps、CPU 3.8 秒 |
| `libx264 -preset veryfast` | 39.7 fps、CPU 19.2 秒 | 56.0 fps、CPU 15.2 秒 |
| `libx264 -preset medium` | 33.0 fps、CPU 32.9 秒 | 35.3 fps、CPU 31.2 秒 |
| `LD_LIBRARY_PATH` = Termux の lib での `h264_mediacodec` | gralloc-mapper is missing | gralloc-mapper is missing |

ハードウェアエンコーダーは速く、CPU をほとんど使わない（CPU 時間は x264 veryfast の 4〜6 分の 1）ので、フレームを描く処理に CPU を回せます。proot はシステムコールをトレースするため、コンテナ内では全体にやや遅くなります。

測定環境: Samsung Galaxy Tab S9 FE+（Exynos 1380）、Android 16 / One UI 8.5、Termux 0.118.3（F-Droid）、Termux の ffmpeg 9.0.2、proot-distro Debian 13。ほかの端末は未検証です。ほかのスマートフォンやタブレットでの結果を issue で教えてもらえるとうれしいです。

```sh
./bench.sh       # proot-distro 内で
bash bench.sh    # Termux で
```

## ヒント

- MediaCodec エンコーダーは `-crf` ではなくビットレート（`-b:v 8M`）で画質を決めます。
- `-pix_fmt yuv420p`（または `nv12`）で渡してください。
- CPU の代替手段を残しておきましょう。ハードウェアエンコーダーが失敗したら `libx264 -preset veryfast` でもう一度エンコードします。
- エンコードがボトルネックでないことも多いです。この方法が生まれたショート動画制作では、Python（MoviePy）でフレームを描く処理が毎秒 2 フレーム程度でした。合成を 1 つの ffmpeg フィルターグラフ（`scale` の `eval=frame`、`overlay`、`xfade`）に移して `h264_mediacodec` でエンコードすると、30 秒の動画のレンダリングが約 7 分から 30〜80 秒になりました。

Python から:

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

## ライセンス

[MIT](LICENSE)
