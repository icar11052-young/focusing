Windows 수정판과 Mac 첫 공개를 함께 배포하는 0.2.0-beta.1입니다.

## 다운로드

- Windows10/11 x64 — `windows-x64-setup.exe` 또는 전체 `windows-x64-portable.zip`.
- macOS14 이상 · Apple Silicon / Intel — `macos-universal.dmg` 또는 `macos-universal.zip`.
- `source.zip` — 양쪽 소스와 빌드·검사 파일, AutoHotkey 대응 소스.
- `SHA256SUMS.txt` — 각 파일의 SHA-256.

## 주요 변경

Windows는 혼합 배율·다중 화면 좌표와 숨은 창 테두리 여백, 탭·제목줄 드래그 오인을 보완했습니다.
청록색 경계 막대의 우클릭으로 두 앱과 비율을 다시 여는 묶음 바로가기를 만들 수 있습니다.

Mac은 빈 제목줄/Control 클릭 확대, 비율 핸들, 좌우 교환·복원을 지원합니다.
웨일의 오른쪽 위 고래 영역을 확대 대상으로 인식하고 확대 직후 배치가 되돌아가는 문제를 보완했습니다.
일부 앱의 첫 클릭 활성화 보정과 로그인 자동 실행은 메뉴에서 선택합니다.

## 설치 안내와 제한

Mac은 손쉬운 사용 권한이 필요하며 유료 개발자 서명·Apple 공증이 없는 베타입니다.
macOS가 차단하면 출처를 확인한 뒤 시스템 설정에서 해당 앱의 실행 허용 여부를 직접 결정하세요.
Windows도 코드 서명 없는 베타라 보안 경고가 나타날 수 있습니다.

Windows 회귀 검사66개·실행 진단·시험 설치와 제거, Mac universal 빌드·서명·배치 계산10개를 CI에서 통과했습니다.
개발 Mac에서 별도 시험 창21개 검사와 웨일 실제 확대 유지의 사용자 확인을 수행했습니다.
Intel Mac 실사용과 모든 앱·화면·배율 조합을 검증한 것은 아닙니다.

기존 개인 개발판이나 다른 자동 창 배치 도구와 동시 실행하지 마세요.
자동 업데이트 기능은 없으므로 기존 앱을 종료한 뒤 새 버전을 설치합니다.
설정과 개인 창 묶음·로그는 배포 파일에 포함하지 않았습니다.
사용 통계·계정·결제 기능이 없습니다.

[Mac 설치·사용 안내](https://github.com/icar11052-young/focusing/blob/main/macos/README.md) · [변경 기록](https://github.com/icar11052-young/focusing/blob/main/CHANGELOG.md) · [문제 제보](https://github.com/icar11052-young/focusing/issues)
