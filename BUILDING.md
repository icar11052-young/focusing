# Focusing 시험 배포본 빌드

버전은 0.2.0-beta.1이다. Windows x64용 공개 소스이며, 일반 사용자는 Releases에서 설치 프로그램 또는 무설치 ZIP을 받으면 된다.

## 도구

- AutoHotkey 2.0.26의 AutoHotkey64.exe. 공식 설치 경로 기본값은 `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe`이다.
- [Ahk2Exe 1.1.37.02a2](https://github.com/AutoHotkey/Ahk2Exe/releases/tag/Ahk2Exe1.1.37.02a2).
- [Inno Setup 7.1.0](https://github.com/jrsoftware/issrc/releases/tag/is-7_1_0).

확인한 도구 파일 SHA-256.

| 파일 | SHA-256 |
|---|---|
| AutoHotkey64.exe 2.0.26 | A2A54B8ABC476D7671D4DE0771BB54BF5F2373D79FF6871D0BA6A62C3B88AE00 |
| Ahk2Exe1.1.37.02a2.zip | C29B8C3A5124850D79FC9E66E2CA79677C377D7F31631AD3022BA159C5D9E3BE |
| innosetup-7.1.0-x64.exe | 0362A383ED217D4C4239B5933866DD96D3EB2102737DA92F80F6057A4B40DF2F |
| AutoHotkey v2.0.26 소스 ZIP | 765ADA5AE0A543F470BCD30371A7B95438E59351B0A20508C516DF76A4F73CA4 |

## 실행

PowerShell에서 도구의 실제 경로를 전달한다.

```powershell
./build.ps1 -Ahk2Exe 'C:\Tools\Ahk2Exe.exe' -Runtime 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' -Iscc 'C:\Tools\Inno Setup\ISCC.exe'
```

출력은 `payload/Focusing.exe`와 `build/Focusing-0.2.0-beta.1-windows-x64-setup.exe`이다. 서명되지 않은 빌드다. 다른 시각에 빌드하면 실행 파일의 해시가 달라질 수 있다.

무설치 묶음은 payload의 전체 파일과 빈 `portable.flag`를 ZIP으로 압축한다. 사용자 INI, Data 폴더, 개발 로그를 넣지 않는다. 설치형에는 portable.flag를 넣지 않는다.

## 회귀 검사

AutoHotkey가 설치된 개발 PC에서 실행한다. 테스트는 실제 소스 함수를 추출하고 Windows API를 대체한 격리 검사다.

```powershell
./tests/test-focus-fix.ps1 -SourcePath ./src/Focusing.ahk
./tests/test-stability.ps1 -SourcePath ./src/Focusing.ahk
./tests/test-drag.ps1 -SourcePath ./src/Focusing.ahk
```

`Focusing.exe --self-test`는 UI·타이머·마우스 훅을 시작하기 전에 진단값을 표준 출력으로 내보내고 종료한다. 설정 디렉터리가 없으면 생성한다. 실제 사용자 창에서의 동작 검증을 대체하지 않는다.

## 배포판 변경

개인판의 펫 제외, 창 겹침 복구, 토글, 비율 저장, 더블클릭, 드래그 수정이 포함된다. 배포판은 실행기 내장, 아이콘 내장, 사용자별/무설치 설정 경로, 버전·도움말, 중복 실행 방지, 컴파일된 실행 파일의 관리자 재시작을 추가한다. 설치 시 자동 실행은 선택 사항이다.

AutoHotkey의 라이선스와 대응 소스는 payload/licenses에 포함된다. Focusing 자체 소스는 GPL-2.0-only로 공개하며, 배포본은 이 GitHub 저장소의 Releases에서 제공한다.


## Mac

macOS14 이상과 Xcode Command Line Tools에서 ./macos/build.sh를 실행합니다. arm64·x86_64를 함께 빌드하고 ad-hoc 서명합니다. Apple 공증은 수행하지 않습니다. build/macos/Focusing.app/Contents/MacOS/Focusing --self-test로 배치 계산 검사를 실행합니다.

## 자동 빌드

.github/workflows/build.yml은 Windows runner에서 ci-windows.ps1로 공식 도구 해시·회귀검사·실행진단·설치·제거를 검사합니다. Mac runner는 universal 앱·DMG·ZIP을 생성합니다. Windows 소스 실행에는 src/PairShortcuts.ahk와 src/PairTools.ps1이 필요합니다. build.ps1은 PairTools.ps1을 payload에 복사합니다. 실제 INI·Data·Pairs·로그·서명 인증서는 배포하지 않습니다.


Mac 실제 창 통합 검사에는 macos/tests/Fixture.swift를 실행 파일로 빌드한 별도 시험 앱이 필요합니다. 앱의 CFBundleIdentifier를 com.young.focusing.fixture, 실행 파일명을 Fixture로 설정하고 실행하면 개인 문서 없는 두 창이 열립니다. 손쉬운 사용 권한이 있는 개발 환경에서 Focusing --integration-test를 실행하면 이 식별자의 시험 창만 대상으로 제목줄·탭 제외, 좌우 배치·교환·복원과12회550ms 유지 검사를 수행합니다. CI에서는 권한이 필요한 실제 창 통합 검사를 실행하지 않습니다.
