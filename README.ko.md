# proot-mediacodec

[English](README.md) | **한국어** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

[Termux](https://termux.dev)에서 [proot-distro](https://github.com/termux/proot-distro)로 띄운 리눅스 배포판 안에서 안드로이드 기기의 하드웨어 영상 인코더(MediaCodec: `h264_mediacodec`, `hevc_mediacodec`)를 쓰는 방법이에요. 루팅도 빌드도 필요 없어요. Termux 저장소의 기본 `ffmpeg` 패키지를 컨테이너 안에서 불러서 쓰면 돼요.

## 빠른 시작

1. Termux에서 (proot 밖):
   ```sh
   pkg install ffmpeg
   ffmpeg -hide_banner -encoders | grep mediacodec   # h264_mediacodec, hevc_mediacodec, ...
   ```
2. proot-distro 안에서 Termux의 ffmpeg를 전체 경로로 실행하거나, `ffmpeg-hw`를 PATH에 넣어서 써요:
   ```sh
   ./ffmpeg-hw -i input.mp4 -c:v h264_mediacodec -b:v 8M -pix_fmt yuv420p output.mp4
   ```
3. `LD_LIBRARY_PATH`에 Termux의 `lib` 폴더를 넣지 마세요. `LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib`이면 하드웨어 인코더가 이 오류를 내며 꺼져요.
   ```
   gralloc-mapper is missing
   ```
   그냥 Termux에서도 똑같아요. proot 안에서 Termux 프로그램을 돌리려고 이 변수를 설정하라는 안내도 있지만 필요 없어요. Termux 실행 파일은 안에 들어 있는 RUNPATH로 자기 라이브러리를 찾아요. `ffmpeg-hw`는 ffmpeg를 실행하기 전에 이 변수를 지워요.

## 왜 되는가

Debian의 ffmpeg는 glibc 리눅스용으로 빌드돼서 MediaCodec을 지원하지 않아요. Termux의 ffmpeg는 안드로이드용으로 MediaCodec을 켜고 빌드돼 있어요. proot-distro는 컨테이너 안에서도 Termux 폴더와 안드로이드 시스템 폴더(`/system`, `/vendor`, `/apex`, `/linkerconfig`)를 그대로 보여 주고, 그 안의 프로세스도 여전히 Termux 앱으로 실행돼요. 그래서 이 ffmpeg는 Termux에서와 똑같이 제조사의 코덱 라이브러리와 미디어 서비스에 닿을 수 있어요.

`LD_LIBRARY_PATH`에 Termux의 `lib` 폴더가 있으면 제조사의 그래픽 버퍼 매퍼(gralloc)를 불러오지 못해요. 필요한 라이브러리 대신 Termux의 사본을 가져가는 것으로 보여요. 그러면 안드로이드의 libui가 위 메시지를 내며 프로그램을 멈춰요. 같은 메시지가 [termux-x11 #960](https://github.com/termux/termux-x11/issues/960)에도 나와요.

## 측정

`bench.sh`는 1080x1920 테스트 화면 300프레임을 인코딩해요. 테스트 화면도 CPU가 그리기 때문에 모든 줄에 그 작업이 들어 있어요.

| 인코더 | proot-distro Debian 안 | Termux |
|---|---|---|
| `h264_mediacodec` (하드웨어) | 59.2 fps, CPU 5.3초 | 84.7 fps, CPU 4.7초 |
| `hevc_mediacodec` (하드웨어) | 57.7 fps, CPU 5.2초 | 92.4 fps, CPU 3.8초 |
| `libx264 -preset veryfast` | 39.7 fps, CPU 19.2초 | 56.0 fps, CPU 15.2초 |
| `libx264 -preset medium` | 33.0 fps, CPU 32.9초 | 35.3 fps, CPU 31.2초 |
| `LD_LIBRARY_PATH` = Termux lib인 `h264_mediacodec` | gralloc-mapper is missing | gralloc-mapper is missing |

하드웨어 인코더가 더 빠르고 CPU를 거의 쓰지 않아서(x264 veryfast보다 CPU 시간이 4~6배 적음), 화면을 그리는 작업에 CPU를 남겨 줘요. proot는 시스템 호출을 가로채기 때문에 컨테이너 안에서는 전체적으로 조금 느려요.

측정 기기: 삼성 갤럭시 탭 S9 FE+ (엑시노스 1380), Android 16 / One UI 8.5, Termux 0.118.3 (F-Droid), Termux ffmpeg 9.0.2, proot-distro Debian 13. 다른 기기는 아직 시험하지 않았어요. 다른 폰이나 태블릿에서 잰 결과를 이슈로 알려 주시면 반가워요.

```sh
./bench.sh       # proot-distro 안에서
bash bench.sh    # Termux에서
```

## 팁

- MediaCodec 인코더는 `-crf` 대신 비트레이트(`-b:v 8M`)로 화질을 정해요.
- `-pix_fmt yuv420p`(또는 `nv12`)로 넘겨 주세요.
- CPU 대안을 남겨 두세요. 하드웨어 인코더가 실패하면 `libx264 -preset veryfast`로 다시 인코딩하면 돼요.
- 인코딩이 느린 원인이 아닐 때가 많아요. 이 방법이 나온 쇼츠 제작 과정에서는 Python(MoviePy)으로 프레임을 그리는 단계가 초당 2프레임 정도였어요. 합성을 ffmpeg 필터 그래프 하나(`scale`의 `eval=frame`, `overlay`, `xfade`)로 옮기고 `h264_mediacodec`으로 인코딩하자, 30초 영상 렌더링이 약 7분에서 30~80초로 줄었어요.

Python에서:

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

## 라이선스

[MIT](LICENSE)
