# Focusing · 포커싱

**클릭하면 지금 쓰는 창이 커집니다.**

Windows에서 두 창을 나란히 놓고 일할 때, 작업 중인 창을 넓히고 옆 창을 줄여 주는 작은 오픈소스 도구입니다.

**A small open-source Windows utility that expands the window you work in while keeping the other window beside it.**

[Windows 설치 파일](https://github.com/icar11052-young/focusing/releases/download/v0.1.0-beta.1/Focusing-0.1.0-beta.1-windows-x64-setup.exe) · [무설치 ZIP](https://github.com/icar11052-young/focusing/releases/download/v0.1.0-beta.1/Focusing-0.1.0-beta.1-windows-x64-portable.zip) · [릴리스와 해시](https://github.com/icar11052-young/focusing/releases/tag/v0.1.0-beta.1)

Windows 10/11 x64 · 초기 베타 · AutoHotkey 별도 설치 불필요. **Mac용은 아직 없습니다.**

## 어떻게 쓰나요?

1. 설치형을 설치하거나, 무설치 ZIP 전체를 쓰기 가능한 폴더에 풉니다.
2. Focusing을 실행하면 작업 표시줄 트레이에 아이콘이 생깁니다.
3. 같은 모니터에 두 창을 나란히 놓습니다.
4. 작은 창의 제목 표시줄을 클릭하거나 **Ctrl+클릭**하면 그 창이 커집니다.
5. 청록색 막대를 **드래그**하면 비율을 조절하고, **더블클릭**하면 좌우 창을 바꿉니다.

일반 클릭으로 확대하려면 트레이의 트리거 방식에서 바꿀 수 있습니다.

| 단축키 | 기능 |
|---|---|
| Ctrl+Alt+F12 | 켜기/끄기 |
| Win+Alt+Shift+1 | 왼쪽 크게 |
| Win+Alt+Shift+2 | 오른쪽 크게 |
| Win+Alt+Shift+S | 좌우 교환 |
| Win+Alt+Shift+T | 클릭 방식 순환 |

## 설치와 설정

- 설치형은 현재 사용자 계정에 설치됩니다. 로그인 시 자동 실행과 바탕 화면 바로가기는 설치 중 선택할 수 있습니다.
- 설치형 설정은 `%APPDATA%\Focusing\focusing.ini`에 저장됩니다. Windows 설정에서 앱을 제거해도 설정은 보존합니다.
- 무설치형은 함께 든 `portable.flag`를 확인해 같은 폴더의 `Data\focusing.ini`에 설정을 저장합니다. 폴더 전체를 복사하면 설정도 옮겨집니다.
- 종료는 트레이 메뉴에서 선택합니다. 기존 개인용 포커싱 스크립트와 배포본을 동시에 실행하지 마세요.

## 베타 상태

개발 PC에서 주요 창 조절 동작과 설치·재설치·제거를 확인했습니다. 소스 함수를 추출한 격리 회귀 검사 66개가 통과했습니다. 이 검사는 실제 Windows UI의 모든 환경을 대신하지 않습니다.

- 코드 서명이 없는 초기 베타이므로 Windows 다운로드/실행 경고가 표시될 수 있습니다.
- 다른 PC의 실제 UI, 혼합 화면 배율, 사용자 정의 제목 표시줄과 관리자 권한 앱 조합은 추가 검증이 필요합니다.
- 앱의 최소 창 너비에 따라 설정한 비율에 도달하지 못할 수 있습니다.
- 계정·결제·사용 통계 전송 기능이 없습니다.

## 문제 제보와 참여

[Issues](https://github.com/icar11052-young/focusing/issues)에서 사용한 Windows 버전, 앱 이름, 화면 배율, 재현 순서를 알려주세요. 스크린샷에는 개인정보가 보이지 않도록 해주세요. 개선 제안과 Pull Request도 환영합니다.

직접 빌드하거나 테스트하려면 [BUILDING.md](BUILDING.md)를 참고하세요. AutoHotkey 런타임 대응 소스와 제3자 고지는 [payload/licenses](payload/licenses)에 있습니다.

## 후원

프로그램과 소스 코드는 무료로 제공합니다. 자율 후원을 받을 수 있도록 준비 중이며, 현재 활성화된 결제·후원 링크는 없습니다. 유용했다면 프로젝트 공유나 버그 제보로도 참여할 수 있습니다.

## 라이선스

Focusing 자체 소스·문서·아이콘은 [GPL-2.0-only](LICENSE)로 배포합니다. Copyright (c) 2026 icar11052-young. 제3자 구성요소는 각각의 라이선스와 고지를 따릅니다.
