param([string]$SourcePath = (Join-Path $PSScriptRoot '..\src\Focusing.ahk'), [string]$Runtime = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe')
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText($SourcePath).Replace("`r`n", "`n")
$functions = @('IsManagedWindow','FindHorizontalPartner','FindLooseHorizontalPartner','HorizontalGap','VerticalOverlap','IsSplitRecoverState','TryExpandFocused','IsAuxiliaryWindowStyle','HorizontalOverlap')
$selected = foreach ($name in $functions) {
    $match = [regex]::Match($source, '(?ms)^' + $name + '\([^\n]*\) \{.*?^\}')
    if ($match.Success) { $match.Value }
}
$body = $selected -join "`n`n"
foreach ($name in @('WinGetList','WinGetMinMax','WinGetStyle','WinGetExStyle','WinGetTitle','WinGetClass','WinExist')) {
    $body = $body.Replace($name + '(', 'Test' + $name + '(')
}
$harness = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, Off
OnError((err, mode) => (FileAppend(err.Message "`n", "**"), ExitApp(1)))
MIN_HEIGHT_RATIO := 0.45
MAX_GAP := 48
WIDTH_COVERAGE := 0.82
handleGuiHwnd := 0
lastSwapTick := 0
SWAP_COOLDOWN := 0
userLargeRatio := 0.6935
handleDragging := false
lastPairLeft := 1
lastPairRight := 2
mutations := 0
failures := 0
checks := 0
testWork := {x:-540,y:-1800,w:4300,h:1740,r:3760,b:-60}
testWindows := Map(
  1, {rect:R(-540,-1800,1318,1740), style:0x16CF0000, ex:0x100},
  2, {rect:R(778,-1800,2983,1740), style:0x14C70000, ex:0x240100},
  3, {rect:R(3186,-1800,574,1800), style:0x14000000, ex:0x280088})
testOrder := [3,1,2]
Check(!IsManagedWindow(3), "live pet attributes excluded despite same title/class")
Check(IsManagedWindow(1) && IsManagedWindow(2), "Whale and Codex main remain eligible")
Check(FindHorizontalPartner(2) = 1, "Codex selects Whale with pet first in Z-order")
Check(FindHorizontalPartner(1) = 2, "Whale selects Codex main")
TryExpandFocused(3)
Check(mutations = 0, "pet click does not fall back to foreground resize")
testWindows[4] := {rect:R(-540,-1800,4300,1740),style:0x14C70000,ex:0x100}
testOrder := [4,3,1,2]
Check(FindHorizontalPartner(1) = 2, "overlapping background cannot beat adjacent partner")
testOrder := [4,3,2]
Check(FindLooseHorizontalPartner(2) = 0, "contained background/pet excluded from loose recovery")
testWindows[1].rect := R(-540,-1800,2983,1740)
testOrder := [3,1,2]
Check(FindHorizontalPartner(2) = 0, "overlapping main windows require recovery")
Check(FindLooseHorizontalPartner(2) = 1, "partly overlapping main pair remains recoverable")
Check(IsSplitRecoverState(testWindows[1].rect,testWindows[2].rect,testWork), "overlap detected as broken split")
testWindows[1].ex := 0x80008
Check(IsManagedWindow(1), "layered/topmost ordinary work window preserved")
testWindows[1].ex := 0x08000100
Check(!IsManagedWindow(1), "no-activate auxiliary excluded")
testWindows[1].ex := 0x100
testWindows[1].style := 0x54C70000
Check(!IsManagedWindow(1), "child window excluded")
FileAppend(checks " checks; " failures " failures`n", "*")
ExitApp(failures ? 1 : 0)
R(x,y,w,h) {
    return {x:x,y:y,w:w,h:h,r:x+w,b:y+h}
}
Check(ok,label) {
    global checks, failures
    checks += 1
    if !ok
        failures += 1
    FileAppend((ok ? "PASS " : "FAIL ") label "`n", "*")
}
TestId(query) {
    return Integer(StrReplace(query,"ahk_id ",""))
}
TestWinGetList() {
    global testOrder
    return testOrder
}
TestWinGetMinMax(query) {
    return 0
}
TestWinGetStyle(query) {
    global testWindows
    return testWindows[TestId(query)].style
}
TestWinGetExStyle(query) {
    global testWindows
    return testWindows[TestId(query)].ex
}
TestWinGetTitle(query) {
    return "ChatGPT"
}
TestWinGetClass(query) {
    return "Chrome_WidgetWin_1"
}
TestWinExist(query) {
    return 2
}
WinAlive(hwnd) {
    global testWindows
    return testWindows.Has(hwnd)
}
GetRect(hwnd) {
    global testWindows
    return testWindows[hwnd].rect
}
GetWorkAreaForWindow(hwnd) {
    global testWork
    return testWork
}
IsTerminalWindow(hwnd) {
    return false
}
SameMonitor(a,b) {
    return true
}
ResolvePartner(hwnd) {
    return hwnd = 1 ? 2 : 1
}
MaybeLearnRatioFromPair(*) {
}
ApplySplit(*) {
    global mutations
    mutations += 1
    return true
}
RefreshHandle(*) {
}
'@
$testPath = Join-Path $PSScriptRoot 'pet-regression.generated.ahk'
[IO.File]::WriteAllText($testPath, $harness + "`n" + $body, [Text.UTF8Encoding]::new($true))
$stdoutPath = Join-Path $PSScriptRoot 'pet-regression.stdout.txt'
$stderrPath = Join-Path $PSScriptRoot 'pet-regression.stderr.txt'
$testProcess = Start-Process -FilePath $Runtime -ArgumentList ('/ErrorStdOut "' + $testPath + '"') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
Get-Content -LiteralPath $stdoutPath
Get-Content -LiteralPath $stderrPath
if ($testProcess.ExitCode -ne 0) { throw "Regression failed with exit $($testProcess.ExitCode)" }
