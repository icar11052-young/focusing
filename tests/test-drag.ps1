param([string]$SourcePath = (Join-Path $PSScriptRoot '..\src\Focusing.ahk'), [string]$Runtime = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe')
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText($SourcePath).Replace("`r`n", "`n")
$selected = foreach ($name in @('EnsurePhysicalCoordinates','IsTargetInWorkArea','ReadDragPointer','HandleLButtonDown','WatchHandleArm','DoHandleDrag','MovePairFill','MoveHandleTo','ForceMove','VisualTargetToOuter')) {
    $m = [regex]::Match($source, '(?ms)^' + $name + '\([^\n]*\) \{.*?^\}')
    if ($m.Success) { $m.Value }
}
$body = $selected -join "`n`n"
foreach ($name in @('MouseGetPos','CoordMode','GetKeyState','SetTimer','DllCall','WinMove')) { $body = $body.Replace($name+'(', 'Test'+$name+'(') }
$harness = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
#Warn All, Off
OnError((err,mode) => (FileAppend(err.Message " line=" err.Line " what=" err.What " extra=" err.Extra "`n","**"),ExitApp(1)))
checks := 0
failures := 0
handleGuiHwnd := 99
enabled := true
HANDLE_EXPAND_GUARD_MS := 500
HANDLE_DRAG_THRESHOLD := 6
HANDLE_W := 14
MIN_SIDE_RATIO := 0.15
lastPairLeft := 1
lastPairRight := 2
handleDragging := false
handleDragArmed := false
handleDownX := 0
handleDownY := 0
lastDragLeftW := -1
handleIgnoreExpandUntil := 0
handleDragStartMX := 0
handleDragStartLeftW := 0
dragLeftHwnd := 0
dragRightHwnd := 0
dragWork := 0
dragMinLeftW := 0
dragMaxLeftW := 0
deferFail := false
pending := []
allFlags := []
handleFlags := 0
fallbackMoves := 0
buttonDown := true
screenY := -800
for activeSide in ["left", "right"] {
    for offsetX in [0, -540] {
        work := {x:offsetX,y:-1800,w:1000,h:1740,r:offsetX+1000,b:-60}
        rects := Map(1,R(offsetX,500),2,R(offsetX+500,500))
        handleDragging := false
        handleDragArmed := false
        screenX := offsetX+500
        mouseMode := "Client"
        HandleLButtonDown(0,0,0,99)
        Step(offsetX+503)
        Check(!handleDragging && rects[1].w=500, activeSide " small motion remains a click")
        Step(offsetX+510)
        Check(rects[1].w=510, activeSide " first 10px motion follows 10px at offset " offsetX)
        Step(offsetX+520)
        Step(offsetX+530)
        Step(offsetX+540)
        Check(rects[1].w=540, activeSide " repeated rightward motion remains 1:1")
        Step(offsetX+510)
        Check(rects[1].w=510, activeSide " direction reversal follows 1:1")
        Step(offsetX+510)
        Check(rects[1].w=510, activeSide " stationary cursor does not oscillate")
        Step(offsetX+400)
        Check(rects[1].w=400 && rects[2].x=offsetX+400 && rects[2].w=600, activeSide " pair remains adjoining")
        Step(offsetX+980)
        Check(rects[1].w=850, activeSide " right limit preserved")
        Step(offsetX+20)
        Check(rects[1].w=150, activeSide " left limit preserved")
    }
}
flagsOk := true
for flags in allFlags {
    if !(flags & 0x4) || !(flags & 0x10)
        flagsOk := false
}
Check(flagsOk, "every resize preserves Z-order and activation")
Check((handleFlags & 0x4) && (handleFlags & 0x40) && !(handleFlags & 0x20), "handle shows without forced frame redraw or Z-order change")
deferFail := true
beforeFallback := fallbackMoves
MovePairFill(1,2,work,500)
Check(fallbackMoves=beforeFallback+2, "failed deferred commit falls back to moving both windows")
FileAppend(checks " checks; " failures " failures`n","*")
ExitApp(failures ? 1 : 0)
R(x,w) {
    return {x:x,y:-1800,w:w,h:1740,r:x+w,b:-60}
}
Step(x) {
    global screenX,mouseMode,handleDragArmed
    screenX := x
    mouseMode := "Client" ; each timer/message is a new AHK thread
    if handleDragArmed
        WatchHandleArm()
    else
        DoHandleDrag()
}
Check(ok,label) {
    global checks,failures
    checks += 1
    if !ok
        failures += 1
    FileAppend((ok ? "PASS " : "FAIL ") label "`n","*")
}
TestCoordMode(kind,mode) {
    global mouseMode
    mouseMode := mode
}
TestMouseGetPos(&x,&y := 0) {
    global screenX,screenY,mouseMode,activeSide,rects
    origin := rects[activeSide="right" ? 2 : 1]
    x := mouseMode="Screen" ? screenX : screenX-origin.x-8
    y := mouseMode="Screen" ? screenY : screenY-origin.y-30
}
TestGetKeyState(*) {
    global buttonDown
    return buttonDown
}
TestSetTimer(*) {
}
WatchHandleDragEnd(*) {
}
EndHandleDrag(*) {
}
EnsurePairOrder() {
}
WinAlive(hwnd) {
    return true
}
GetWorkAreaForWindow(hwnd) {
    global work
    return work
}
GetRectOuter(hwnd) {
    global rects
    return rects[hwnd]
}
GetRect(hwnd) {
    global rects
    return rects[hwnd]
}
CanMovePair(*) {
    return true
}
SetUserLargeRatio(*) {
}
TestWinMove(*) {
    throw Error("Unexpected WinMove fallback")
}
TestDllCall(name,args*) {
    global pending,rects,allFlags,handleFlags,fallbackMoves,deferFail
    if InStr(name,"BeginDeferWindowPos") {
        pending := []
        return 123
    }
    if InStr(name,"EndDeferWindowPos") {
        if deferFail
            return 0
        for move in pending
            rects[move.hwnd] := R(move.x,move.w)
        return 1
    }
    if InStr(name,"DeferWindowPos") {
        pending.Push({hwnd:args[4],x:args[8],w:args[12]})
        allFlags.Push(args[16])
        return 123
    }
    if InStr(name,"SetWindowPos") {
        flags := args[14]
        allFlags.Push(flags)
        if args[2]=99
            handleFlags := flags
        else {
            rects[args[2]] := R(args[6],args[10])
            fallbackMoves += 1
        }
        return 1
    }
    return 1
}
'@
$testPath = Join-Path $PSScriptRoot 'drag-test.generated.ahk'
[IO.File]::WriteAllText($testPath,$harness+"`n"+$body,[Text.UTF8Encoding]::new($true))
$out=Join-Path $PSScriptRoot 'drag-test.stdout.txt'
$err=Join-Path $PSScriptRoot 'drag-test.stderr.txt'
$proc=Start-Process -FilePath $Runtime -ArgumentList ('/ErrorStdOut "'+$testPath+'"') -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
Get-Content -LiteralPath $out
Get-Content -LiteralPath $err
if($proc.ExitCode -ne 0){throw 'Drag regression failed.'}




