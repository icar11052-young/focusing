# 공식 도구를 검증하고 Windows 검사와 배포 파일 생성을 실행한다.
$ErrorActionPreference='Stop'
$tools=Join-Path $env:RUNNER_TEMP 'focusing-tools'
New-Item -ItemType Directory -Force $tools | Out-Null
function Download([string]$url,[string]$name){$p=Join-Path $tools $name;Invoke-WebRequest $url -OutFile $p;return $p}
function Check-Hash([string]$p,[string]$expected){if((Get-FileHash $p -Algorithm SHA256).Hash -ne $expected){throw "Hash mismatch: $p"}}
$runtimeZip=Download 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26.zip' 'runtime.zip'
Expand-Archive $runtimeZip (Join-Path $tools 'runtime')
$runtime=Join-Path $tools 'runtime\AutoHotkey64.exe'
Check-Hash $runtime 'A2A54B8ABC476D7671D4DE0771BB54BF5F2373D79FF6871D0BA6A62C3B88AE00'
$compilerZip=Download 'https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe1.1.37.02a2/Ahk2Exe1.1.37.02a2.zip' 'compiler.zip'
Check-Hash $compilerZip 'C29B8C3A5124850D79FC9E66E2CA79677C377D7F31631AD3022BA159C5D9E3BE'
Expand-Archive $compilerZip (Join-Path $tools 'compiler')
$compiler=(Get-ChildItem (Join-Path $tools 'compiler') -Recurse -Filter Ahk2Exe.exe | Select-Object -First 1).FullName
$inno=Download 'https://github.com/jrsoftware/issrc/releases/download/is-7_1_0/innosetup-7.1.0-x64.exe' 'inno.exe'
Check-Hash $inno '0362A383ED217D4C4239B5933866DD96D3EB2102737DA92F80F6057A4B40DF2F'
$innoDir=Join-Path $tools 'inno'
$p=Start-Process $inno -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="'+$innoDir+'"')) -Wait -PassThru
if($p.ExitCode -ne 0){throw 'Inno Setup installation failed'}
foreach($test in @('test-focus-fix.ps1','test-stability.ps1','test-drag.ps1')){& (Join-Path $PSScriptRoot "tests\$test") -Runtime $runtime -SourcePath (Join-Path $PSScriptRoot 'src\Focusing.ahk')}
Copy-Item (Join-Path $PSScriptRoot 'src\PairTools.ps1') (Join-Path $PSScriptRoot 'payload\PairTools.ps1') -Force
& (Join-Path $PSScriptRoot 'build.ps1') -Ahk2Exe $compiler -Runtime $runtime -Iscc (Join-Path $innoDir 'ISCC.exe')
$stage=Join-Path $PSScriptRoot 'build\portable'
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'payload\*') $stage -Recurse
New-Item -ItemType File (Join-Path $stage 'portable.flag') | Out-Null
$exe=Join-Path $stage 'Focusing.exe'
$smoke=Start-Process $exe -ArgumentList '--self-test' -Wait -PassThru -RedirectStandardOutput (Join-Path $PSScriptRoot 'build\self-test.txt') -RedirectStandardError (Join-Path $PSScriptRoot 'build\self-test-errors.txt')
Get-Content (Join-Path $PSScriptRoot 'build\self-test.txt')
if($smoke.ExitCode -ne 0){throw 'Compiled executable smoke test failed'}
Remove-Item (Join-Path $stage 'Data') -Recurse -Force
Compress-Archive (Join-Path $stage '*') (Join-Path $PSScriptRoot 'build\Focusing-0.2.0-beta.1-windows-x64-portable.zip')
# Install in a temporary directory and verify the helper is deployed; then uninstall only that test installation.
$installDir=Join-Path $env:RUNNER_TEMP 'Focusing-install-test'
$setup=Join-Path $PSScriptRoot 'build\Focusing-0.2.0-beta.1-windows-x64-setup.exe'
$p=Start-Process $setup -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/DIR="'+$installDir+'"'),'/TASKS=') -Wait -PassThru
if($p.ExitCode -ne 0 -or !(Test-Path (Join-Path $installDir 'PairTools.ps1'))){throw 'Installer helper deployment failed'}
$p=Start-Process (Join-Path $installDir 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -Wait -PassThru
if($p.ExitCode -ne 0){throw 'Test uninstall failed'}
