param(
    [string]$Ahk2Exe = (Join-Path $PSScriptRoot '..\release-tools\Ahk2Exe\Ahk2Exe.exe'),
    [string]$Runtime = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
    [string]$Iscc = (Join-Path $PSScriptRoot '..\release-tools\Inno\ISCC.exe')
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'build'),(Join-Path $PSScriptRoot 'payload') -Force | Out-Null
foreach($file in @($Ahk2Exe,$Runtime,$Iscc)){if(!(Test-Path -LiteralPath $file)){throw "Missing build tool: $file"}}
$source=Join-Path $PSScriptRoot 'src\Focusing.ahk'
$exe=Join-Path $PSScriptRoot 'payload\Focusing.exe'
$icon=Join-Path $PSScriptRoot 'src\focusing.ico'
$compile=Start-Process -FilePath $Ahk2Exe -ArgumentList ('/in "'+$source+'" /out "'+$exe+'" /base "'+$Runtime+'" /icon "'+$icon+'" /compress 0 /silent verbose') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $PSScriptRoot 'build\compile.stdout.txt') -RedirectStandardError (Join-Path $PSScriptRoot 'build\compile.stderr.txt')
Get-Content -LiteralPath (Join-Path $PSScriptRoot 'build\compile.stdout.txt'),(Join-Path $PSScriptRoot 'build\compile.stderr.txt')
if($compile.ExitCode -ne 0 -or !(Test-Path -LiteralPath $exe)){throw 'Focusing executable compilation failed.'}
& $Iscc (Join-Path $PSScriptRoot 'Focusing.iss')
if($LASTEXITCODE -ne 0){throw 'Installer compilation failed.'}
