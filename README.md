# Focusing · 포커싱

**작은 창의 빈 제목줄을 클릭하면 작업 창이 커지고 옆 창이 줄어듭니다.**

Windows와 Mac에서 나란히 놓은 두 창의 비율을 바꾸는 무료 오픈소스 도구입니다.
A small open-source window focus utility for Windows and macOS.

## 다운로드

**[배포판과 다운로드](https://github.com/icar11052-young/focusing/releases/tag/v0.2.0-beta.1)** · [변경 기록](CHANGELOG.md)

| 운영체제 | 파일 |
|---|---|
| Windows10/11 x64 | windows-x64-setup.exe 또는 windows-x64-portable.zip |
| macOS14 이상 · Apple Silicon / Intel | macos-universal.dmg 또는 macos-universal.zip |
| 개발용 | source.zip |

초기 베타입니다. Windows 배포본은 AutoHotkey 별도 설치가 필요 없습니다. Mac 배포본은 유료 개발자 서명·Apple 공증이 없어 보안 경고가 나타날 수 있습니다.

## 사용

1. 같은 모니터에 두 창을 나란히 놓습니다.
2. 작은 창의 **빈 제목줄 또는 Ctrl/Control+클릭**으로 큰 쪽을 전환합니다.
3. 청록색 막대를 끌어 비율을 조절합니다.
4. 막대를 더블클릭하면 좌우 위치를 교환합니다.

웹페이지 본문·탭·닫기 버튼은 기본 자동 확대 대상이 아닙니다. 제목줄 인식이 어려우면 Ctrl/Control+클릭을 사용하세요.

## Windows

설치형은 사용자 계정에 설치되며 로그인 자동 실행·바탕 화면 아이콘은 설치 중 선택합니다. 무설치 ZIP은 전체를 쓰기 가능한 폴더에 풉니다. 함께 든 PairTools.ps1·licenses도 유지하세요.

설정은 설치형 %APPDATA%\Focusing, 무설치형 Data에 저장됩니다. 제거해도 개인 설정은 보존합니다. 경계 막대 우클릭 → ‘이 두 창 바로가기 만들기’로 앱 두 개와 비율을 다시 여는 바로가기를 만듭니다. 특정 브라우저 탭·문서 복원은 보장하지 않습니다. 혼합 배율 좌표·숨은 테두리 여백·탭 클릭·제목줄 드래그 오인을 보완했습니다.

| 단축키 | 기능 |
|---|---|
| Ctrl+Alt+F12 | 켜기/끄기 |
| Win+Alt+Shift+1 / 2 | 왼쪽 / 오른쪽 크게 |
| Win+Alt+Shift+S | 좌우 교환 |
| Win+Alt+Shift+T | 클릭 방식 순환 |

## Mac

**[Mac 설치·권한·사용 안내](macos/README.md)**를 참고하세요. 메뉴 막대 앱이며 손쉬운 사용 권한이 필요합니다. 로그인 자동 실행은 선택 사항입니다. 웨일 빈 탭 줄·오른쪽 위 고래 장식 영역을 지원하고 일부 앱의 첫 클릭 보정도 선택 기능으로 제공합니다.

## 검증과 제한

Windows 격리 회귀 검사66개와 빌드·실행 진단·시험 설치/제거는 GitHub Actions에서 수행합니다. Mac은 universal 빌드·서명·배치 계산10개를 검사합니다. 개발 Mac에서 시험 창21개 검사 및 실제 웨일 확대 유지도 확인했습니다. 다른 PC·Intel Mac 실사용·모든 다중 화면/배율·관리자 앱·사용자 정의 제목줄을 전부 확인한 것은 아닙니다. 앱의 최소 창 크기에 따라 원하는 비율에 도달하지 못할 수 있습니다. 다른 자동 창 배치 도구나 두 실행본을 동시에 사용하면 충돌할 수 있습니다.

앱에는 계정·결제·사용 통계 전송이 없습니다. 개인 창 묶음·설정·로그는 배포하지 않습니다.

## 제보·빌드·라이선스

[Issues](https://github.com/icar11052-young/focusing/issues)에 운영체제·앱·배율·재현 순서를 알려주세요. 개인정보가 포함된 스크린샷은 피해주세요.
[빌드 안내](BUILDING.md) · [검사 실행 기록](https://github.com/icar11052-young/focusing/actions)

소스·문서·아이콘은 [GPL-2.0-only](LICENSE)로 공개합니다. 제3자 구성요소의 라이선스와 AutoHotkey 대응 소스는 payload/licenses에 있습니다. 후원은 준비 중이며 현재 결제·후원 링크는 없습니다.
