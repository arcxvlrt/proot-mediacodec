# proot-mediacodec

[English](README.md) | **한국어** | [日本語](README.ja.md) | [简体中文](README.zh-CN.md)

[proot-distro](https://github.com/termux/proot-distro) 안에서 안드로이드 하드웨어 영상 인코더(`h264_mediacodec`, `hevc_mediacodec`)를 쓰는 방법입니다. Termux 기본 `ffmpeg` 그대로 쓰고, 루팅이나 따로 빌드할 것은 없습니다.

갤럭시 탭의 proot-distro Debian에서 유튜브 쇼츠를 렌더링하다가 만난 문제입니다. Debian의 ffmpeg는 MediaCodec을 아예 지원하지 않고, 컨테이너 안에서 Termux의 ffmpeg를 부르면 `gralloc-mapper is missing`을 내며 계속 죽었습니다. 원인은 환경 변수 하나였습니다.

## 사용법

Termux에서:

```sh
pkg install ffmpeg
```

proot 안에서는 Termux의 ffmpeg를 전체 경로로 실행하거나, 이 저장소의 `ffmpeg-hw`를 씁니다:

```sh
./ffmpeg-hw -i in.mp4 -c:v h264_mediacodec -b:v 8M -pix_fmt yuv420p out.mp4
```

`LD_LIBRARY_PATH`가 Termux의 `lib` 폴더를 가리키지만 않으면 이걸로 끝입니다.

## `gralloc-mapper is missing`

`LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib`이면 하드웨어 인코더가 이 메시지를 내고 종료됩니다. proot 안에서도, 그냥 Termux에서도 똑같습니다. proot 안에서 Termux 프로그램을 돌리려고 이 경로를 넣으라는 설치 안내도 있는데, 필요 없습니다. Termux 실행 파일은 자기 RUNPATH로 라이브러리를 찾습니다. `ffmpeg-hw`는 이 변수만 지우고 Termux의 ffmpeg를 실행합니다.

제 추측으로는, 이때 제조사의 gralloc 매퍼가 필요한 라이브러리 대신 Termux의 사본을 잡아서 불러오기에 실패하는 것 같습니다. [termux-x11 #960](https://github.com/termux/termux-x11/issues/960)에도 같은 메시지가 나옵니다.

## 측정값

`bench.sh`는 1080x1920 테스트 화면 300프레임을 인코딩합니다. 테스트 화면 자체도 CPU가 그리기 때문에 모든 줄에 그 작업이 들어 있습니다.

| 인코더 | proot 안 (Debian) | Termux |
|---|---|---|
| `h264_mediacodec` | 59.2 fps, CPU 5.3초 | 84.7 fps, CPU 4.7초 |
| `hevc_mediacodec` | 57.7 fps, CPU 5.2초 | 92.4 fps, CPU 3.8초 |
| `libx264 -preset veryfast` | 39.7 fps, CPU 19.2초 | 56.0 fps, CPU 15.2초 |
| `libx264 -preset medium` | 33.0 fps, CPU 32.9초 | 35.3 fps, CPU 31.2초 |
| `h264_mediacodec`, `LD_LIBRARY_PATH` = Termux lib | gralloc-mapper is missing | gralloc-mapper is missing |

갤럭시 탭 S9 FE+ (엑시노스 1380), Android 16, F-Droid판 Termux 0.118.3, ffmpeg 9.0.2, Debian 13. 가진 기기가 이것 하나라서, 다른 폰에서 잰 결과는 이슈로 알려 주시면 고맙겠습니다.

하드웨어 인코더는 x264 veryfast의 4분의 1에서 3분의 1 정도(medium의 6분의 1)만 CPU를 씁니다. 다른 프로그램이 화면을 그리고 있을 때는 fps보다 이게 더 중요합니다. proot는 시스템 호출을 가로채기 때문에 proot 안에서는 전부 조금씩 느립니다.

```sh
./bench.sh       # proot 안에서
bash bench.sh    # Termux에서
```

## 참고

- MediaCodec은 `-crf` 대신 비트레이트(`-b:v`)를 받습니다.
- 입력은 `yuv420p`나 `nv12`로 넘깁니다.
- 하드웨어 인코더가 없을 때를 대비해 `libx264 -preset veryfast`를 대안으로 두세요.
- 제 경우엔 인코딩이 느린 원인도 아니었습니다. MoviePy가 프레임을 초당 2장 정도밖에 못 그렸거든요. 합성을 ffmpeg 필터 그래프 하나로 옮기고 `h264_mediacodec`으로 인코딩했더니 30초 영상이 약 7분에서 30~80초로 줄었습니다.

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
