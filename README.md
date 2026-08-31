# Underground Arcade Prototype

어두운 한국 지하상가를 배경으로 한 Godot 4.7 데스크톱 생존 호러 검증 프로토타입입니다.

## Play

[Play the Web build](https://junshelp.github.io/diablo-style-sprite-validation/)

현재 공개 빌드는 gameplay 검증용 단색 placeholder art를 사용합니다. 승인 대기 중인 canonical character와 8방향 animation atlas는 포함하지 않습니다.

## Run locally

Godot 4.7에서 `project.godot`을 열거나 다음 명령으로 Web build를 다시 생성할 수 있습니다.

```sh
godot --headless --path . --export-release Web web/index.html
```

Web build는 local HTTP server를 통해 여세요. GitHub Pages workflow는 commit된 `web/` 디렉터리만 배포합니다.

## Font

Web 한국어 UI에는 Google Fonts의 Noto Sans KR을 번들합니다. 라이선스는 `assets/fonts/OFL.txt`에 있습니다.
