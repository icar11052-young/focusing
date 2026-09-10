param([string]$SourcePath = (Join-Path $PSScriptRoot '..\src\Focusing.ahk'), [string]$Runtime = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe')
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText($SourcePath).Replace("`r`n", "`n")
$scope = ''; $toggleScope = $null; $layoutScopes = @()
foreach ($line in $source.Split("`n")) {
    if ($line -match '^#HotIf(?:\s+(.*))?$') { $scope = $Matches[1] }
    if ($line -match '^\^!F12::') { $toggleScope = [string]$scope }
    if ($line -match '^!\+#(?:1|2|s)::') { $layoutScopes += [string]$scope }
}
$scopeOk = ($null -ne $toggleScope -and $toggleScope -eq '' -and $layoutScopes.Count -eq 3 -and @($layoutScopes | Where-Object { $_ -ne 'enabled' }).Count -eq 0)
Write-Output "Hotkey scope: $scopeOk (toggle always available; layout keys conditional)"
$functions = @('ToggleEnabled','SetUserLargeRatio','SaveLargeRatio','LoadLargeRatio','HandleLButtonDblClk','EndHandleDrag','CancelHandleDrag','SnapRightToActualLeft')
$selected = foreach ($name in $functions) {
    $match = [regex]::Match($source, '(?ms)^' + $name + '\([^\n]*\) \{.*?^\}')
    if (!$match.Success) { throw "Missing function $name" }
    $match.Value
}
$body = ($selected -join "`n`n").Replace('SetTimer(', 'TestSetTimer(').Replace('ToolTip(', 'TestToolTip(').Replace('DllCall(', 'TestDllCall(')
$harness = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
OnError((err,mode) => (FileAppend(err.Message "`n","**"),ExitApp(1)))
INI_PATH := A_ScriptDir "\stability-test-settings.ini"
DEFAULT_LARGE_RATIO := 2/3
MIN_LARGE_RATIO := 0.5
MAX_LARGE_RATIO := 0.85
if A_Args.Length && A_Args[1] = "reload" {
    r := LoadLargeRatio()
    FileAppend("Fresh process loaded ratio=" r "`n", "*")
    ExitApp(Abs(r - 0.8) < 0.0001 ? 0 : 1)
}
checks := 0
failures := 0
enabled := true
handleDragging := false
handleDragArmed := false
handleGuiHwnd := 99
HANDLE_EXPAND_GUARD_MS := 500
handleIgnoreExpandUntil := 0
lastDragLeftW := 100
lastPairLeft := 1
lastPairRight := 2
timers := Map()
releaseCount := 0
moveCount := 0
swapCount := 0
swapClean := false
userLargeRatio := 0.67
SaveLargeRatio()
SetUserLargeRatio(0.8, false)
Check(Abs(userLargeRatio-0.8)<0.0001, "drag updates memory")
Check(Abs(IniRead(INI_PATH,"focus","largeRatio")-0.67)<0.0001, "drag does not write on every frame")
SetUserLargeRatio(0.8,true)
Check(Abs(LoadLargeRatio()-0.8)<0.0001, "same-value final persistence writes disk")
SetUserLargeRatio(0.802,true)
Check(Abs(LoadLargeRatio()-0.802)<0.0001, "final small adjustment is persisted exactly")
SetUserLargeRatio(1,true)
Check(LoadLargeRatio()=0.85, "upper ratio bound preserved")
SetUserLargeRatio(0.1,true)
Check(LoadLargeRatio()=0.5, "lower ratio bound preserved")
handleDragging := true
handleDragArmed := true
HandleLButtonDblClk(0,0,0,99)
Check(!handleDragging && !handleDragArmed, "double-click clears shared flags")
Check(swapCount=1 && swapClean, "swap runs once after clean cancellation")
Check(moveCount=0, "double-click cancellation does not commit resize")
Check(lastDragLeftW=-1 && releaseCount=1, "cached width and capture released")
Check(timers.Count=3, "all drag timers stopped")
Check(handleIgnoreExpandUntil>A_TickCount, "post-handle click guard set")
handleDragging := true
handleDragArmed := true
HandleLButtonDblClk(0,0,0,123)
Check(handleDragging && handleDragArmed && swapCount=1, "unrelated window event ignored")
CancelHandleDrag()
Check(!handleDragging && !handleDragArmed && moveCount=0, "explicit cancel clears without resize")
handleDragging := true
handleDragArmed := true
SetUserLargeRatio(0.8,false)
ToggleEnabled()
Check(!enabled && !handleDragging && !handleDragArmed, "disable finalizes active drag")
Check(moveCount=1 && Abs(LoadLargeRatio()-0.8)<0.0001, "disable persists final actual ratio")
ToggleEnabled()
Check(enabled && !handleDragging && !handleDragArmed, "enable restores usable state")
EndHandleDrag()
Check(moveCount=1, "repeated mouse-up does not commit twice")
FileAppend(checks " checks; " failures " failures`n", "*")
ExitApp(failures ? 1 : 0)
Check(ok,label) {
    global checks,failures
    checks += 1
    if !ok
        failures += 1
    FileAppend((ok ? "PASS " : "FAIL ") label "`n","*")
}
TestSetTimer(callback, period) {
    global timers
    if period=0
        timers[callback.Name] := period
}
TestToolTip(*) {
}
TestDllCall(*) {
    global releaseCount
    releaseCount += 1
    return true
}
UpdateTrayTip() {
}
RefreshHandle(*) {
}
DoHandleDrag(*) {
}
WatchHandleArm(*) {
}
WatchHandleDragEnd(*) {
}
SwapPairSides() {
    global swapCount,swapClean,handleDragging,handleDragArmed
    swapCount += 1
    swapClean := !handleDragging && !handleDragArmed
}
WinAlive(hwnd) {
    return true
}
EnsurePairOrder() {
}
GetWorkAreaForWindow(hwnd) {
    return {w:1000}
}
GetRectOuter(hwnd) {
    return {w:800}
}
MovePairFill(*) {
    global moveCount
    moveCount += 1
    return 800
}
'@
$testPath = Join-Path $PSScriptRoot 'stability-test.generated.ahk'
[IO.File]::WriteAllText($testPath, $harness + "`n" + $body, [Text.UTF8Encoding]::new($true))
function Run-Test([string]$extra) {
    $out = Join-Path $PSScriptRoot 'stability-test.stdout.txt'
    $err = Join-Path $PSScriptRoot 'stability-test.stderr.txt'
    $proc = Start-Process -FilePath $Runtime -ArgumentList ('/ErrorStdOut "' + $testPath + '" ' + $extra) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    Get-Content -LiteralPath $out
    Get-Content -LiteralPath $err
    $script:lastTestExit = $proc.ExitCode
}
Run-Test ''
$firstExit = $lastTestExit
Run-Test 'reload'
if (!$scopeOk -or $firstExit -ne 0 -or $lastTestExit -ne 0) { throw 'Stability regression failed.' }
Write-Output 'PASS hotkey scope and fresh-process persistence'
