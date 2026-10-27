# proot-mediacodec

[English](README.md) | [한국어](README.ko.md) | **日本語** | [简体中文](README.zh-CN.md)

> この翻訳は機械翻訳の助けを借りています。おかしな所があれば PR で直してもらえると助かります。

[proot-distro](https://github.com/termux/proot-distro) の中から Android のハードウェア動画エンコーダー（`h264_mediacodec`、`hevc_mediacodec`）を使う方法です。Termux 標準の `ffmpeg` をそのまま使い、root も独自ビルドも要りません。

Galaxy Tab の proot-distro Debian で YouTube ショートをレンダリングしていて、この問題に当たりました。Debian の ffmpeg は MediaCodec にまったく対応しておらず、コンテナ内から Termux の ffmpeg を呼ぶと `gralloc-mapper is missing` で落ち続けました。原因は環境変数ひとつでした。

## 使い方

Termux で:

```sh
pkg install ffmpeg
```

proot の中では Termux の ffmpeg をフルパスで実行するか、このリポジトリの `ffmpeg-hw` を使います:

```sh
./ffmpeg-hw -i in.mp4 -c:v h264_mediacodec -b:v 8M -pix_fmt yuv420p out.mp4
```

`LD_LIBRARY_PATH` が Termux の `lib` フォルダーを指していなければ、これだけです。

## `gralloc-mapper is missing`

`LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib` だと、ハードウェアエンコーダーはこのメッセージを出して終了します。proot の中でも素の Termux でも同じです。proot 内で Termux のバイナリを動かすためにこのパスを足すよう書いたセットアップ手順もありますが、不要です。Termux のバイナリは自分の RUNPATH でライブラリを見つけます。`ffmpeg-hw` はこの変数を消して Termux の ffmpeg を実行するだけです。

推測ですが、このときメーカーの gralloc マッパーが依存ライブラリとして Termux 側のコピーを拾い、読み込みに失敗しているようです。[termux-x11 #960](https://github.com/termux/termux-x11/issues/960) にも同じメッセージが出ています。

## 数値

`bench.sh` は 1080x1920 のテスト画像を 300 フレームエンコードします。テスト画像自体も CPU で描くので、その処理はどの行にも入っています。

| エンコーダー | proot 内（Debian） | Termux |
|---|---|---|
| `h264_mediacodec` | 59.2 fps、CPU 5.3 秒 | 84.7 fps、CPU 4.7 秒 |
| `hevc_mediacodec` | 57.7 fps、CPU 5.2 秒 | 92.4 fps、CPU 3.8 秒 |
| `libx264 -preset veryfast` | 39.7 fps、CPU 19.2 秒 | 56.0 fps、CPU 15.2 秒 |
| `libx264 -preset medium` | 33.0 fps、CPU 32.9 秒 | 35.3 fps、CPU 31.2 秒 |
| `h264_mediacodec`、`LD_LIBRARY_PATH` = Termux の lib | gralloc-mapper is missing | gralloc-mapper is missing |

Galaxy Tab S9 FE+（Exynos 1380）、Android 16、F-Droid 版 Termux 0.118.3、ffmpeg 9.0.2、Debian 13。手元にこの 1 台しかないので、ほかの端末での数値を issue で教えてもらえるとうれしいです。

ハードウェアエンコーダーの CPU 時間は x264 veryfast のおよそ 4 分の 1 から 3 分の 1（medium の 6 分の 1）です。ほかの処理がフレームを描いているときは、fps よりこちらが効きます。proot はシステムコールをトレースするので、proot 内ではどれも少し遅くなります。

```sh
./bench.sh       # proot の中で
bash bench.sh    # Termux で
```

## メモ

- MediaCodec は `-crf` ではなくビットレート（`-b:v`）を受け取ります。
- 入力は `yuv420p` か `nv12` にします。
- ハードウェアエンコーダーがない場合に備えて、`libx264 -preset veryfast` を代わりに残しておきましょう。
- 自分の場合、そもそもエンコードが遅さの原因ではありませんでした。MoviePy はフレームを毎秒 2 枚ほどしか描けなかったからです。合成を 1 つの ffmpeg フィルターグラフに移して `h264_mediacodec` でエンコードしたら、30 秒の動画が約 7 分から 30〜80 秒になりました。
- 静止画から作る動画なら、写真を `-loop 1` で入力しないでください。フレームごとにファイルを読み直してデコードします。代わりに写真を 1 フレームとして入力し、フィルターグラフの中で繰り返します（`-framerate 30 -i photo.png` と `format=yuv420p,tpad=stop_mode=clone:stop_duration=6,trim=duration=6`）。自分の 30 秒のスライドショーでは、出力は同じまま ffmpeg の時間が約 40% 減りました（88 秒 → 47 秒）。効果があるのは静止画のときだけです。動画クリップはどのみちフレームごとに絵が違うので。変わらない文字も同じで、毎フレーム重ねる代わりに背景画像へ一度だけ描き込めば済みます。

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
