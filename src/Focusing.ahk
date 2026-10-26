; SPDX-License-Identifier: GPL-2.0-only
; Copyright (c) 2026 icar11052-young
;@Ahk2Exe-SetName Focusing
;@Ahk2Exe-SetDescription Focusing window focus utility
;@Ahk2Exe-SetVersion 0.2.0.0
;@Ahk2Exe-SetProductVersion 0.2.0-beta.1
#Requires AutoHotkey v2.0
#SingleInstance Force

; 닫힌 창/일시 hwnd 에러는 조용히 무시 (에러 팝업 방지)
OnError(SafeWindowError)
EnsurePhysicalCoordinates()

EnsurePhysicalCoordinates() {
    ; DWM rectangles are physical pixels. Every entry from a timer/window
    ; callback must use that same coordinate space, including GetWindowRect.
    if !DllCall("User32\SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
        throw Error("Cannot enable per-monitor physical coordinates; layout cancelled")
}

IsTargetInWorkArea(hwnd, x, y, w, h) {
    EnsurePhysicalCoordinates()
    if !WinAlive(hwnd) || w <= 0 || h <= 0
        return false
    area := GetWorkAreaForWindow(hwnd)
    return x >= area.x - 1 && y >= area.y - 1
        && x + w <= area.r + 1 && y + h <= area.b + 1
}

WriteRuntimeState(*) {
    global settingsDir, enabled
    EnsurePhysicalCoordinates()
    ctx := DllCall("User32\GetThreadDpiAwarenessContext", "Ptr")
    awareness := DllCall("User32\GetAwarenessFromDpiAwarenessContext", "Ptr", ctx, "Int")
    file := settingsDir "\runtime-status.ini"
    IniWrite(DllCall("GetCurrentProcessId"), file, "runtime", "pid")
    IniWrite(awareness, file, "runtime", "dpiAwareness")
    IniWrite(enabled ? 1 : 0, file, "runtime", "enabled")
    IniWrite(A_Now, file, "runtime", "updated")
    IniWrite("2026-10-02-physical-dpi", file, "runtime", "revision")
}

SafeWindowError(e, *) {
    if InStr(e.Message, "Target window not found")
        return true
    return false
}

; ── 포커싱: 클릭 확대 + 가변 비율 핸들 + 좌우스왑 ───────────────
; 작은 창 클릭 → 저장된 largeRatio로 확대. 핸들로 비율 조절.
; Win+Alt+Shift+S → 좌우 창 자리 교환.

DEFAULT_LARGE_RATIO := 2 / 3
MIN_LARGE_RATIO := 0.50       ; 큰 쪽 최소 비율 (50:50~)
MAX_LARGE_RATIO := 0.85
MIN_SIDE_RATIO := 0.15        ; 한쪽 최소 너비 비율
MIN_HEIGHT_RATIO := 0.45
WIDTH_COVERAGE := 0.82
MAX_GAP := 48
SWAP_COOLDOWN := 350
HANDLE_W := 14
HANDLE_REFRESH_MS := 250
APP_VERSION := "0.2.0-beta.1"
portableMode := A_IsCompiled && FileExist(A_ScriptDir "\portable.flag")
settingsDir := A_IsCompiled ? (portableMode ? A_ScriptDir "\Data" : A_AppData "\Focusing") : A_ScriptDir
DirCreate(settingsDir)
INI_PATH := settingsDir "\focusing.ini"
ICON_PATH := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\focusing.ico"

focusClick := 0
enabled := true
lastSwapTick := 0
elevHintShown := false
lastPairLeft := 0
lastPairRight := 0
userLargeRatio := LoadLargeRatio()
handleDragging := false
handleDragArmed := false   ; 클릭만 한 상태 (아직 드래그 아님)
handleGui := 0
handleGuiHwnd := 0
lastFocusSide := "left"
triggerMode := LoadTriggerMode()   ; "any" | "ctrl" | "titlebar" | "ctrl_or_titlebar"
lastHandleClickTick := 0
handleDownX := 0
handleDownY := 0
handleDragStartMX := 0
handleDragStartLeftW := 0
handleDragMinLeftW := 0
handleDragMaxLeftW := 0
lastDragLeftW := -1
dragLeftHwnd := 0
dragRightHwnd := 0
dragWork := 0
dragMinLeftW := 0
dragMaxLeftW := 0
handleIgnoreExpandUntil := 0  ; 핸들 조작 직후 클릭확대 금지
HANDLE_DBLCLICK_MS := 450
HANDLE_DRAG_THRESHOLD := 6
HANDLE_EXPAND_GUARD_MS := 500

; Packaging diagnostic exits before the UI, timers, and mouse hook start.
if A_Args.Length && A_Args[1] = "--self-test" {
    FileAppend("Focusing " APP_VERSION "`ncompiled=" A_IsCompiled "`nportable=" (portableMode ? 1 : 0) "`nsettings=" INI_PATH "`nratio=" userLargeRatio "`ntrigger=" triggerMode "`n", "*")
    ExitApp(0)
}

if A_IsCompiled {
    appMutex := DllCall("Kernel32\CreateMutex", "Ptr", 0, "Int", 0, "Str", "Local\FocusingApp-v1", "Ptr")
    if !appMutex || A_LastError = 183 {
        MsgBox("포커싱이 이미 실행 중입니다. 작업 표시줄의 트레이 아이콘에서 확인해 주세요.", "Focusing")
        ExitApp()
    }
}

; ── 트레이 ──
try
    TraySetIcon(ICON_PATH)
catch
    TraySetIcon("Shell32.dll", 238)
UpdateTrayTip()
Tray := A_TrayMenu
Tray.Delete()
Tray.Add("켜기/끄기", ToggleEnabled)
Tray.Add("지금 두 창 — 왼쪽 크게 (Win+Alt+Shift+1)", (*) => SnapTwoWindows(true))
Tray.Add("지금 두 창 — 오른쪽 크게 (Win+Alt+Shift+2)", (*) => SnapTwoWindows(false))
Tray.Add("좌우 창 스왑 (Win+Alt+Shift+S)", (*) => SwapPairSides())
Tray.Add("비율 2:1로 리셋", ResetRatioToDefault)
Tray.Add()
triggerMenu := Menu()
triggerMenu.Add("아무 데나 클릭", (*) => SetTriggerMode("any"))
triggerMenu.Add("Ctrl+클릭만", (*) => SetTriggerMode("ctrl"))
triggerMenu.Add("타이틀바 클릭만", (*) => SetTriggerMode("titlebar"))
triggerMenu.Add("Ctrl+클릭 또는 타이틀바 클릭", (*) => SetTriggerMode("ctrl_or_titlebar"))
Tray.Add("트리거 방식", triggerMenu)
UpdateTriggerMenuChecks()
if !IsScriptElevated()
    Tray.Add("관리자 권한으로 재시작 (PowerShell용)", RestartAsAdmin)
Tray.Add()
if A_IsCompiled {
    Tray.Add("사용 방법", ShowUsage)
    Tray.Add("정보", (*) => MsgBox("Focusing " APP_VERSION "`nWindows 창 확대·축소 도구", "Focusing"))
}
Tray.Add("종료", (*) => ExitApp())

InitHandleGui()
SetTimer(RefreshHandle, HANDLE_REFRESH_MS)
OnExit(CleanupHandle)
InitPairShortcuts()
WriteRuntimeState()
SetTimer(WriteRuntimeState, 5000)

ToggleEnabled(*) {
    global enabled
    ; Finish an active drag before disabling, so no armed state survives re-enable.
    if enabled
        EndHandleDrag()
    enabled := !enabled
    UpdateTrayTip()
    tip := enabled ? "포커싱 켜짐" : "포커싱 꺼짐"
    ToolTip(tip)
    SetTimer(() => ToolTip(), -1200)
    RefreshHandle()
}

ResetRatioToDefault(*) {
    global userLargeRatio, DEFAULT_LARGE_RATIO
    userLargeRatio := DEFAULT_LARGE_RATIO
    SaveLargeRatio()
    UpdateTrayTip()
    ; 현재 pair가 있으면 바로 적용 (활성 창 기준 왼쪽 크게)
    SnapTwoWindows(true)
    ToolTip("비율 리셋: " RatioLabel(userLargeRatio))
    SetTimer(() => ToolTip(), -1500)
}

UpdateTrayTip() {
    global enabled, userLargeRatio, triggerMode
    A_IconTip := "포커싱 " (enabled ? "켜짐" : "꺼짐")
        . " · " RatioLabel(userLargeRatio)
        . " · " TriggerModeLabel(triggerMode)
        . (IsScriptElevated() ? " · 관리자" : "")
}

LoadTriggerMode() {
    global INI_PATH
    m := IniRead(INI_PATH, "focus", "triggerMode", A_IsCompiled ? "ctrl_or_titlebar" : "any")
    if m != "any" && m != "ctrl" && m != "titlebar" && m != "ctrl_or_titlebar"
        m := "any"
    return m
}

SaveTriggerMode() {
    global INI_PATH, triggerMode
    IniWrite(triggerMode, INI_PATH, "focus", "triggerMode")
}

SetTriggerMode(mode) {
    global triggerMode
    triggerMode := mode
    SaveTriggerMode()
    UpdateTriggerMenuChecks()
    UpdateTrayTip()
    ToolTip("트리거 방식: " TriggerModeLabel(mode))
    SetTimer(() => ToolTip(), -1200)
}

TriggerModeLabel(mode) {
    if mode = "ctrl_or_titlebar"
        return "Ctrl+클릭 또는 타이틀바 클릭"
    if mode = "ctrl"
        return "Ctrl+클릭만"
    if mode = "titlebar"
        return "타이틀바 클릭만"
    return "아무 데나 클릭"
}

UpdateTriggerMenuChecks() {
    global triggerMenu, triggerMode
    labels := Map("any", "아무 데나 클릭", "ctrl", "Ctrl+클릭만", "titlebar", "타이틀바 클릭만", "ctrl_or_titlebar", "Ctrl+클릭 또는 타이틀바 클릭")
    for mode, label in labels {
        if mode = triggerMode
            triggerMenu.Check(label)
        else
            triggerMenu.Uncheck(label)
    }
}

RatioLabel(r) {
    a := Round(r * 10)
    b := 10 - a
    if a < 1
        a := 1
    if b < 1
        b := 1
    return a ":" b
}

LoadLargeRatio() {
    global INI_PATH, DEFAULT_LARGE_RATIO, MIN_LARGE_RATIO, MAX_LARGE_RATIO
    r := IniRead(INI_PATH, "focus", "largeRatio", DEFAULT_LARGE_RATIO)
    try r := Number(r)
    catch
        r := DEFAULT_LARGE_RATIO
    if r < MIN_LARGE_RATIO
        r := MIN_LARGE_RATIO
    if r > MAX_LARGE_RATIO
        r := MAX_LARGE_RATIO
    return r
}

SaveLargeRatio() {
    global INI_PATH, userLargeRatio
    IniWrite(Format("{:.4f}", userLargeRatio), INI_PATH, "focus", "largeRatio")
}

SetUserLargeRatio(r, persist := true) {
    global userLargeRatio, MIN_LARGE_RATIO, MAX_LARGE_RATIO
    if r < MIN_LARGE_RATIO
        r := MIN_LARGE_RATIO
    if r > MAX_LARGE_RATIO
        r := MAX_LARGE_RATIO
    ; Suppress drag jitter only; explicit persistence must save the final ratio.
    if !persist && Abs(userLargeRatio - r) < 0.005
        return
    userLargeRatio := r
    if persist {
        SaveLargeRatio()
        UpdateTrayTip()
    }
}

; 클릭 후 포커스가 잡히면 실행 (마우스가 핵심)
; Decide on mouse-down, before tab close/selection can change the hit target.
~*LButton:: CaptureFocusClick()
~*LButton Up:: FinishFocusClick()

CaptureFocusClick() {
    EnsurePhysicalCoordinates()
    global focusClick, enabled, handleDragging, handleDragArmed, handleGuiHwnd, handleIgnoreExpandUntil
    focusClick := 0
    if !enabled || handleDragging || handleDragArmed || A_TickCount < handleIgnoreExpandUntil
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my, &winUnder)
    if handleGuiHwnd && winUnder = handleGuiHwnd
        return
    clicked := ResolveTopLevel(winUnder)
    if clicked && IsManagedWindow(clicked) && PassesTriggerGate(clicked, mx, my)
        focusClick := {hwnd: clicked, x: mx, y: my}
}

FinishFocusClick() {
    EnsurePhysicalCoordinates()
    global focusClick, enabled, handleDragging, handleDragArmed, handleIgnoreExpandUntil
    down := focusClick
    focusClick := 0
    if !down || !enabled || handleDragging || handleDragArmed || A_TickCount < handleIgnoreExpandUntil
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my, &winUnder)
    ; A title-bar drag is a move gesture, not a request to expand the pair.
    if ResolveTopLevel(winUnder) != down.hwnd || Abs(mx - down.x) > 6 || Abs(my - down.y) > 6
        return
    Sleep(80)
    if enabled && WinAlive(down.hwnd) && !handleDragging && !handleDragArmed
        TryExpandFocused(down.hwnd)
}

; 트리거 방식(아무 데나/Ctrl+클릭/타이틀바)에 따라 이번 클릭이 포커싱을 발동시킬지 판정
PassesTriggerGate(hwnd, mx, my) {
    global triggerMode
    if triggerMode = "ctrl_or_titlebar"
        return GetKeyState("Ctrl", "P") || IsInTitleBar(hwnd, mx, my)
    if triggerMode = "ctrl"
        return GetKeyState("Ctrl", "P")
    if triggerMode = "titlebar"
        return IsInTitleBar(hwnd, mx, my)
    return true
}

IsInTitleBar(hwnd, mx, my) {
    EnsurePhysicalCoordinates()
    if !WinAlive(hwnd)
        return false
    ; Ask the window itself: tabs/buttons are HTCLIENT, draggable caption is HTCAPTION.
    ; A bounded query avoids hanging the input hook on an unresponsive application.
    hit := 0
    try {
        ok := DllCall("User32\SendMessageTimeoutW", "Ptr", hwnd, "UInt", 0x84,
            "Ptr", 0, "Ptr", PackHitTestPoint(mx, my), "UInt", 0x0002,
            "UInt", 100, "Ptr*", &hit, "Ptr")
        return ok && hit = 2
    } catch {
        return false
    }
}

PackHitTestPoint(x, y) {
    packed := (Round(x) & 0xFFFF) | ((Round(y) & 0xFFFF) << 16)
    return packed >= 0x80000000 ? packed - 0x100000000 : packed
}

TryExpandFocused(clickedRoot := 0) {
    global lastSwapTick, SWAP_COOLDOWN, userLargeRatio, handleDragging
    global lastPairLeft, lastPairRight, DEFAULT_LARGE_RATIO
    if handleDragging
        return
    if (A_TickCount - lastSwapTick < SWAP_COOLDOWN)
        return

    fg := clickedRoot ? clickedRoot : WinExist("A")
    if !fg || !IsManagedWindow(fg)
        return

    partner := ResolvePartner(fg)
    if !partner
        return

    fgRect := GetRect(fg)
    partnerRect := GetRect(partner)
    if !fgRect || !partnerRect
        return

    work := GetWorkAreaForWindow(fg)
    totalW := work.w
    recovering := IsSplitRecoverState(fgRect, partnerRect, work)

    newPair := !((fg = lastPairLeft && partner = lastPairRight)
        || (fg = lastPairRight && partner = lastPairLeft))
    ; The first focus of a new pair always starts at 2:1. Later drags stay intact.
    if !newPair && !recovering
        MaybeLearnRatioFromPair(fgRect, partnerRect, work)

    isBalanced := (Abs(fgRect.w - partnerRect.w) < totalW * 0.12)
    if (!newPair && !recovering && !isBalanced && fgRect.w >= partnerRect.w * 0.92)
        return

    largeW := Round(totalW * (newPair ? DEFAULT_LARGE_RATIO : userLargeRatio))
    smallW := totalW - largeW

    if (fgRect.x <= partnerRect.x) {
        if !ApplySplit(fg, partner, work.x, work.y, largeW, smallW, work.h)
            return
        lastFocusSide := "left"
    } else {
        if !ApplySplit(partner, fg, work.x, work.y, smallW, largeW, work.h)
            return
        lastFocusSide := "right"
    }

    lastSwapTick := A_TickCount
    RefreshHandle()
}

MaybeLearnRatioFromPair(a, b, work) {
    gap := HorizontalGap(a, b)
    if gap > MAX_GAP
        return
    combined := Max(a.r, b.r) - Min(a.x, b.x)
    if combined < work.w * WIDTH_COVERAGE
        return
    larger := Max(a.w, b.w) / work.w
    SetUserLargeRatio(larger)
}

ApplySplit(leftHwnd, rightHwnd, x, y, leftW, rightW, h) {
    global lastPairLeft, lastPairRight
    if !SameMonitor(leftHwnd, rightHwnd)
        return false
    if !CanMovePair(leftHwnd, rightHwnd)
        return false
    ; 항상 작업영역 전체를 채움 (DWM/실측 너비 합이 화면보다 작아져 공터·왼쪽 밀림 방지)
    work := GetWorkAreaForWindow(leftHwnd)
    total := leftW + rightW
    if total < 1
        total := work.w
    leftW := Round(work.w * leftW / total)
    minW := Round(work.w * MIN_SIDE_RATIO)
    if leftW < minW
        leftW := minW
    if leftW > work.w - minW
        leftW := work.w - minW
    rightW := work.w - leftW
    if !IsTargetInWorkArea(leftHwnd, work.x, work.y, leftW, work.h)
        || !IsTargetInWorkArea(rightHwnd, work.x + leftW, work.y, rightW, work.h)
        return false
    okL := ForceMove(leftHwnd, work.x, work.y, leftW, work.h)
    okR := ForceMove(rightHwnd, work.x + leftW, work.y, rightW, work.h)
    if !(okL && okR) {
        MaybeShowMoveFailedHint(leftHwnd, rightHwnd)
        return false
    }
    lastPairLeft := leftHwnd
    lastPairRight := rightHwnd
    SetUserLargeRatio(Max(leftW, rightW) / work.w)
    PersistActivePair()
    return true
}

ResolvePartner(fg) {
    partner := FindHorizontalPartner(fg)
    if !partner
        partner := FindLooseHorizontalPartner(fg)
    if !partner
        partner := FindRememberedPartner(fg)
    return partner
}

; 현재 창 + 짝을 largeRatio로 배치
SnapTwoWindows(leftIsLarge := true) {
    global userLargeRatio
    fg := WinExist("A")
    if !fg || !IsManagedWindow(fg)
        return
    partner := ResolvePartner(fg)
    if !partner {
        ToolTip("옆에 짝이 되는 창을 못 찾음. 창 2개를 나란히 둔 뒤 다시.")
        SetTimer(() => ToolTip(), -2000)
        return
    }

    work := GetWorkAreaForWindow(fg)
    totalW := work.w
    largeW := Round(totalW * userLargeRatio)
    smallW := totalW - largeW

    fgRect := GetRect(fg)
    partnerRect := GetRect(partner)
    if !fgRect || !partnerRect
        return
    left := fgRect.x <= partnerRect.x ? fg : partner
    right := left = fg ? partner : fg

    if leftIsLarge {
        if !ApplySplit(left, right, work.x, work.y, largeW, smallW, work.h)
            return
        lastFocusSide := "left"
    } else {
        if !ApplySplit(left, right, work.x, work.y, smallW, largeW, work.h)
            return
        lastFocusSide := "right"
    }
    RefreshHandle()
}

; 좌↔우 창만 자리 교환 (슬롯 비율 유지 + 화면 전체 채움)
SwapPairSides(*) {
    global lastPairLeft, lastPairRight, lastSwapTick, handleIgnoreExpandUntil, HANDLE_EXPAND_GUARD_MS
    handleIgnoreExpandUntil := A_TickCount + HANDLE_EXPAND_GUARD_MS
    left := 0
    right := 0
    if WinAlive(lastPairLeft) && WinAlive(lastPairRight) && IsManagedWindow(lastPairLeft) && IsManagedWindow(lastPairRight) {
        EnsurePairOrder()
        left := lastPairLeft
        right := lastPairRight
    } else {
        fg := WinExist("A")
        if !fg || !IsManagedWindow(fg)
            return
        partner := ResolvePartner(fg)
        if !partner
            return
        fgRect := GetRectOuter(fg)
        pRect := GetRectOuter(partner)
        if !fgRect || !pRect
            return
        left := fgRect.x <= pRect.x ? fg : partner
        right := left = fg ? partner : fg
    }

    lRect := GetRectOuter(left)
    rRect := GetRectOuter(right)
    if !lRect || !rRect
        return
    work := GetWorkAreaForWindow(left)
    ; 비율만 가져오고, 실제 배치는 ApplySplit이 화면 전체로 정규화
    sum := Max(lRect.w + rRect.w, 1)
    leftW := Round(work.w * (lRect.w / sum))
    rightW := work.w - leftW

    if !ApplySplit(right, left, work.x, work.y, leftW, rightW, work.h)
        return
    lastSwapTick := A_TickCount
    RefreshHandle()
    ToolTip("좌우 스왑")
    SetTimer(() => ToolTip(), -800)
}

#HotIf enabled
!+#1:: SnapTwoWindows(true)    ; Win+Alt+Shift+1 → 왼쪽 크게
!+#2:: SnapTwoWindows(false)   ; Win+Alt+Shift+2 → 오른쪽 크게
!+#s:: SwapPairSides()         ; Win+Alt+Shift+S → 좌우 스왑
!+#t:: CycleTriggerMode()      ; Win+Alt+Shift+T → 트리거 방식 순환 (트레이 안 보일 때용)
#HotIf
; The toggle must remain available while focusing is disabled.
^!F12:: ToggleEnabled()

; 트레이 아이콘이 안 보이는 환경(관리자 스케줄러 실행 등)을 위한 단축키 순환
CycleTriggerMode(*) {
    global triggerMode
    order := ["any", "ctrl", "titlebar", "ctrl_or_titlebar"]
    idx := 1
    for i, m in order {
        if m = triggerMode {
            idx := i
            break
        }
    }
    next := order[Mod(idx, order.Length) + 1]
    SetTriggerMode(next)
}

; ── 사이 핸들 ──

InitHandleGui() {
    EnsurePhysicalCoordinates()
    global handleGui, handleGuiHwnd, HANDLE_W
    handleGui := Gui("+AlwaysOnTop -Caption +ToolWindow -SysMenu +E0x08000000")
    handleGui.BackColor := "0x0D9488"
    handleGui.MarginX := 0
    handleGui.MarginY := 0
    handleGui.OnEvent("Close", (*) => 0)
    handleGui.Show("x-32000 y-32000 w" HANDLE_W " h200 Hide NoActivate")
    handleGuiHwnd := handleGui.Hwnd
    OnMessage(0x201, HandleLButtonDown)   ; WM_LBUTTONDOWN
    OnMessage(0x202, HandleLButtonUp)     ; WM_LBUTTONUP
    OnMessage(0x203, HandleLButtonDblClk) ; WM_LBUTTONDBLCLK
}

CleanupHandle(*) {
    global handleGui
    try {
        if handleGui
            handleGui.Destroy()
    }
}

MoveHandleTo(hx, hy, hh) {
    EnsurePhysicalCoordinates()
    global handleGuiHwnd, HANDLE_W
    if !handleGuiHwnd || hh < 40
        return
    ; Gui.Show 는 드래그 중 마우스 캡처를 깨뜨림 → SetWindowPos 만 사용
    flags := 0x0010 | 0x0004 | 0x0040  ; NOACTIVATE | NOZORDER | SHOWWINDOW
    DllCall("User32\SetWindowPos", "Ptr", handleGuiHwnd, "Ptr", 0,
        "Int", hx, "Int", hy, "Int", HANDLE_W, "Int", hh, "UInt", flags)
}

; 두 창 경계(seam)에 핸들 배치
PlaceHandleVisual(l, r, work) {
    global HANDLE_W, handleDragging, handleDragArmed
    if !l || !r
        return

    if !handleDragging && !handleDragArmed
        UpdateFocusSideFromForeground()

    hy := Max(l.y, r.y)
    hh := Min(l.b, r.b) - hy
    if hh < 80
        return

    gap := r.x - l.r
    if gap > 0
        hx := l.r + Floor(gap / 2) - Floor(HANDLE_W / 2)
    else
        hx := l.r - Floor(HANDLE_W / 2)

    if hx < work.x
        hx := work.x
    if hx + HANDLE_W > work.r
        hx := work.r - HANDLE_W
    MoveHandleTo(hx, hy, hh)
}

UpdateFocusSideFromForeground() {
    global lastPairLeft, lastPairRight, lastFocusSide, handleGuiHwnd
    fg := WinExist("A")
    if !fg || (handleGuiHwnd && fg = handleGuiHwnd)
        return
    fg := ResolveTopLevel(fg)
    if !fg
        return
    if fg = lastPairLeft
        lastFocusSide := "left"
    else if fg = lastPairRight
        lastFocusSide := "right"
}

; 포커스가 짝 창(또는 핸들)일 때만 녹색바 표시.
; 3번째 창이 앞에 있으면 AlwaysOnTop 핸들이 그 위를 뚫고 나오지 않게 숨긴다.
IsPairForeground() {
    global lastPairLeft, lastPairRight, handleGuiHwnd
    fg := WinExist("A")
    if !fg
        return false
    if handleGuiHwnd && Integer(fg) = Integer(handleGuiHwnd)
        return true
    fg := ResolveTopLevel(fg)
    if !fg
        return false
    return Integer(fg) = Integer(lastPairLeft) || Integer(fg) = Integer(lastPairRight)
}

RefreshHandle(*) {
    global enabled, handleGui, handleGuiHwnd, lastPairLeft, lastPairRight, handleDragging, handleDragArmed
    if !handleGui || !handleGuiHwnd
        return
    if handleDragging || handleDragArmed
        return
    if !enabled || !WinAlive(lastPairLeft) || !WinAlive(lastPairRight) {
        handleGui.Hide()
        return
    }
    if !IsManagedWindow(lastPairLeft) || !IsManagedWindow(lastPairRight) || !SameMonitor(lastPairLeft, lastPairRight) {
        handleGui.Hide()
        return
    }
    ; 3번째 창이 활성 → 핸들 숨김 (AlwaysOnTop이어도 덮지 않음)
    if !IsPairForeground() {
        handleGui.Hide()
        return
    }
    EnsurePairOrder()
    l := GetRect(lastPairLeft)
    r := GetRect(lastPairRight)
    if !l || !r {
        handleGui.Hide()
        return
    }
    gap := r.x - l.r
    if gap < -4 || gap > 80 {
        handleGui.Hide()
        return
    }
    work := GetWorkAreaForWindow(lastPairLeft)
    PlaceHandleVisual(l, r, work)
}

; Timer/message callbacks default to client coordinates. The right window's origin
; moves with the seam, which feeds our own resize back into the next pointer delta.
ReadDragPointer(&x, &y) {
    EnsurePhysicalCoordinates()
    CoordMode("Mouse", "Screen")
    MouseGetPos(&x, &y)
}

HandleLButtonDown(wParam, lParam, msg, hwnd) {
    global handleGuiHwnd, enabled, handleDragArmed, handleDragging
    global handleDownX, handleDownY, lastDragLeftW
    global handleIgnoreExpandUntil, HANDLE_EXPAND_GUARD_MS
    global handleDragStartMX, handleDragStartLeftW, lastPairLeft
    if !enabled || Integer(hwnd) != Integer(handleGuiHwnd)
        return

    handleIgnoreExpandUntil := A_TickCount + HANDLE_EXPAND_GUARD_MS
    ReadDragPointer(&handleDownX, &handleDownY)
    lastDragLeftW := -1
    handleDragging := false
    handleDragArmed := true

    ; 클릭 시점의 왼쪽 너비 기억 — 절대좌표로 바로 리사이즈하지 않음 (틱 이동 방지)
    EnsurePairOrder()
    work := GetWorkAreaForWindow(lastPairLeft)
    l := GetRect(lastPairLeft)
    handleDragStartMX := handleDownX
    handleDragStartLeftW := l ? l.w : Round(work.w / 2)

    SetTimer(WatchHandleArm, 16)
    return 0
}

HandleLButtonUp(wParam, lParam, msg, hwnd) {
    global handleGuiHwnd, handleDragging, handleDragArmed, handleIgnoreExpandUntil, HANDLE_EXPAND_GUARD_MS
    if Integer(hwnd) != Integer(handleGuiHwnd)
        return
    ; 단순 클릭(이동 없음): 레이아웃 건드리지 않음
    if handleDragArmed && !handleDragging {
        handleDragArmed := false
        SetTimer(WatchHandleArm, 0)
        handleIgnoreExpandUntil := A_TickCount + HANDLE_EXPAND_GUARD_MS
        return 0
    }
    if handleDragging
        EndHandleDrag()
    return 0
}

HandleLButtonDblClk(wParam, lParam, msg, hwnd) {
    global handleGuiHwnd, enabled, handleIgnoreExpandUntil, HANDLE_EXPAND_GUARD_MS
    if !enabled || Integer(hwnd) != Integer(handleGuiHwnd)
        return
    ; Clear shared state without committing a resize before the side swap.
    CancelHandleDrag()
    SwapPairSides()
    return 0
}

EndHandleDrag(commit := true) {
    global handleDragging, handleDragArmed, lastDragLeftW, handleIgnoreExpandUntil, HANDLE_EXPAND_GUARD_MS
    SetTimer(DoHandleDrag, 0)
    SetTimer(WatchHandleArm, 0)
    SetTimer(WatchHandleDragEnd, 0)
    wasDrag := handleDragging
    handleDragging := false
    handleDragArmed := false
    lastDragLeftW := -1
    DllCall("User32\ReleaseCapture")
    if wasDrag && commit {
        SnapRightToActualLeft()
        RefreshHandle()
    }
    handleIgnoreExpandUntil := A_TickCount + HANDLE_EXPAND_GUARD_MS
}

CancelHandleDrag() {
    EndHandleDrag(false)
}

WatchHandleArm(*) {
    global handleDragArmed, handleDragging, handleDownX, handleDownY, HANDLE_DRAG_THRESHOLD
    global handleGuiHwnd, lastDragLeftW, handleDragStartMX, handleDragStartLeftW, lastPairLeft
    if !handleDragArmed
        return
    if !GetKeyState("LButton", "P") {
        handleDragArmed := false
        SetTimer(WatchHandleArm, 0)
        return
    }
    ReadDragPointer(&mx, &my)
    if Abs(mx - handleDownX) < HANDLE_DRAG_THRESHOLD && Abs(my - handleDownY) < HANDLE_DRAG_THRESHOLD
        return

    ; Keep the mouse-down origin so crossing the threshold does not discard movement.
    handleDragArmed := false
    handleDragging := true
    lastDragLeftW := -1
    SetTimer(WatchHandleArm, 0)
    EnsurePairOrder()

    ; 드래그 중에는 짝·작업영역·한계를 고정한다.
    ; (매 프레임 재판정하면 리사이즈가 늦은 앱 때문에 좌우가 뒤바뀌며 떨린다)
    global dragLeftHwnd, dragRightHwnd, dragWork, dragMinLeftW, dragMaxLeftW
    dragLeftHwnd := lastPairLeft
    dragRightHwnd := lastPairRight
    dragWork := GetWorkAreaForWindow(lastPairLeft)
    minW := Round(dragWork.w * MIN_SIDE_RATIO)
    dragMinLeftW := minW
    dragMaxLeftW := dragWork.w - minW

    ; handleDragStartMX/LeftW were captured at mouse-down and remain fixed.
    DllCall("User32\SetCapture", "Ptr", handleGuiHwnd)
    SetTimer(DoHandleDrag, 25)
    DoHandleDrag()
}

WatchHandleDragEnd(*) {
}

EnsurePairOrder() {
    global lastPairLeft, lastPairRight
    if !WinAlive(lastPairLeft) || !WinAlive(lastPairRight)
        return
    l := GetRectOuter(lastPairLeft)
    r := GetRectOuter(lastPairRight)
    if l && r && l.x > r.x {
        tmp := lastPairLeft
        lastPairLeft := lastPairRight
        lastPairRight := tmp
    }
}

GetRectOuter(hwnd) {
    EnsurePhysicalCoordinates()
    if !WinAlive(hwnd)
        return 0
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return { x: x, y: y, w: w, h: h, r: x + w, b: y + h }
    } catch {
        return 0
    }
}

SnapRightToActualLeft() {
    global lastPairLeft, lastPairRight
    if !WinAlive(lastPairLeft) || !WinAlive(lastPairRight)
        return
    EnsurePairOrder()
    work := GetWorkAreaForWindow(lastPairLeft)
    l := GetRect(lastPairLeft)
    if !l
        return
    leftW := MovePairFill(lastPairLeft, lastPairRight, work, l.w)
    SetUserLargeRatio(Max(leftW, work.w - leftW) / work.w, true)
    PersistActivePair()
}

; 두 창을 한 번에 배치 (왼쪽만 먼저 움직이며 생기는 떨림 방지)
MovePairFill(leftHwnd, rightHwnd, work, leftW) {
    EnsurePhysicalCoordinates()
    if !WinAlive(leftHwnd) || !WinAlive(rightHwnd)
        return leftW
    minW := Round(work.w * MIN_SIDE_RATIO)
    if leftW < minW
        leftW := minW
    if leftW > work.w - minW
        leftW := work.w - minW
    rightW := work.w - leftW
    if !IsTargetInWorkArea(leftHwnd, work.x, work.y, leftW, work.h)
        || !IsTargetInWorkArea(rightHwnd, work.x + leftW, work.y, rightW, work.h)
        return leftW
    flags := 0x0010 | 0x0004 | 0x0400  ; NOACTIVATE | NOZORDER | NOSENDCHANGING
    leftTarget := VisualTargetToOuter(leftHwnd, work.x, work.y, leftW, work.h)
    rightTarget := VisualTargetToOuter(rightHwnd, work.x + leftW, work.y, rightW, work.h)
    hdwp := DllCall("User32\BeginDeferWindowPos", "Int", 2, "Ptr")
    if hdwp {
        hdwp := DllCall("User32\DeferWindowPos", "Ptr", hdwp, "Ptr", leftHwnd, "Ptr", 0,
            "Int", leftTarget.x, "Int", leftTarget.y, "Int", leftTarget.w, "Int", leftTarget.h, "UInt", flags, "Ptr")
        if hdwp
            hdwp := DllCall("User32\DeferWindowPos", "Ptr", hdwp, "Ptr", rightHwnd, "Ptr", 0,
                "Int", rightTarget.x, "Int", rightTarget.y, "Int", rightTarget.w, "Int", rightTarget.h, "UInt", flags, "Ptr")
        if hdwp && DllCall("User32\EndDeferWindowPos", "Ptr", hdwp)
            return leftW
    }
    ForceMove(leftHwnd, work.x, work.y, leftW, work.h)
    ForceMove(rightHwnd, work.x + leftW, work.y, rightW, work.h)
    return leftW
}

DoHandleDrag(*) {
    global handleDragging, lastDragLeftW, HANDLE_W
    global handleDragStartMX, handleDragStartLeftW
    global dragLeftHwnd, dragRightHwnd, dragWork, dragMinLeftW, dragMaxLeftW
    if !handleDragging
        return
    if !GetKeyState("LButton", "P") {
        EndHandleDrag()
        return
    }
    if !WinAlive(dragLeftHwnd) || !WinAlive(dragRightHwnd)
        return

    work := dragWork
    ReadDragPointer(&mx, &my)
    leftW := Round(handleDragStartLeftW + (mx - handleDragStartMX))
    if leftW < dragMinLeftW
        leftW := dragMinLeftW
    if leftW > dragMaxLeftW
        leftW := dragMaxLeftW

    ; 3px 미만 변화는 무시 (앱 리페인트로 인한 미세 떨림 방지)
    if lastDragLeftW >= 0 && Abs(leftW - lastDragLeftW) < 3
        return
    if !CanMovePair(dragLeftHwnd, dragRightHwnd)
        return

    MovePairFill(dragLeftHwnd, dragRightHwnd, work, leftW)

    ; 앱 최소너비에 막혔으면 그 지점을 한계로 기억해 계속 밀어붙이지 않는다
    l := GetRect(dragLeftHwnd)
    if l && Abs(l.w - leftW) > 4 {
        if leftW < l.w
            dragMinLeftW := l.w
        else
            dragMaxLeftW := l.w
        leftW := l.w
    }

    lastDragLeftW := leftW
    SetUserLargeRatio(Max(leftW, work.w - leftW) / work.w, false)

    hx := work.x + leftW - Floor(HANDLE_W / 2)
    if hx < work.x
        hx := work.x
    if hx + HANDLE_W > work.r
        hx := work.r - HANDLE_W
    MoveHandleTo(hx, work.y, work.h)
}

; ── helpers ──

WinAlive(hwnd) {
    return hwnd && WinExist("ahk_id " hwnd)
}

ResolveTopLevel(hwnd) {
    if !hwnd
        return 0
    try {
        root := DllCall("User32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        hwnd := root ? root : hwnd
        return WinAlive(hwnd) ? hwnd : 0
    } catch {
        return 0
    }
}

IsTerminalWindow(hwnd) {
    if !WinAlive(hwnd)
        return false
    try {
        cls := WinGetClass("ahk_id " hwnd)
        if cls = "ConsoleWindowClass" || cls = "CascadiaWindow"
            return true
        proc := WinGetProcessName("ahk_id " hwnd)
        for p in ["WindowsTerminal.exe", "powershell.exe", "pwsh.exe", "cmd.exe", "OpenConsole.exe"] {
            if proc = p
                return true
        }
    } catch {
        return false
    }
    return false
}

; Use window roles, not process/title: a pet and the main app may share both.
IsAuxiliaryWindowStyle(style, exStyle) {
    ; WS_CHILD, WS_EX_TOOLWINDOW, WS_EX_NOACTIVATE.
    ; TOPMOST/LAYERED alone also occur on ordinary work windows: keep those eligible.
    return (style & 0x40000000) || (exStyle & (0x80 | 0x08000000))
}

IsManagedWindow(hwnd) {
    global handleGuiHwnd
    if !WinAlive(hwnd)
        return false
    if handleGuiHwnd && hwnd = handleGuiHwnd
        return false
    try {
        if WinGetMinMax("ahk_id " hwnd) != 0
            return false
        style := WinGetStyle("ahk_id " hwnd)
        exStyle := WinGetExStyle("ahk_id " hwnd)
        if !(style & 0x10000000) || IsAuxiliaryWindowStyle(style, exStyle)
            return false
        title := WinGetTitle("ahk_id " hwnd)
        if title = "" && !IsTerminalWindow(hwnd)
            return false
        cls := WinGetClass("ahk_id " hwnd)
        skip := ["Shell_TrayWnd", "Progman", "WorkerW", "ForegroundStaging",
            "XamlExplorerHostIslandWindow", "Windows.UI.Core.CoreWindow"]
        for c in skip {
            if cls = c
                return false
        }
        return true
    } catch {
        return false
    }
}

FindHorizontalPartner(hwnd) {
    if !WinAlive(hwnd)
        return 0
    work := GetWorkAreaForWindow(hwnd)
    base := GetRect(hwnd)
    if !base
        return 0
    terminal := IsTerminalWindow(hwnd)
    minH := work.h * (terminal ? 0.35 : MIN_HEIGHT_RATIO)
    maxGap := terminal ? 120 : MAX_GAP
    widthCov := terminal ? 0.70 : WIDTH_COVERAGE

    if (base.h < minH)
        return 0

    best := 0
    bestScore := 0

    for other in WinGetList() {
        if other = hwnd || !IsManagedWindow(other)
            continue

        r := GetRect(other)
        if !r || (r.h < minH)
            continue
        if !SameMonitor(hwnd, other)
            continue

        overlap := VerticalOverlap(base, r)
        if overlap < Min(base.h, r.h) * 0.45
            continue

        ; Overlapping background windows are not adjacent split partners.
        if HorizontalOverlap(base, r) > 16
            continue
        gap := HorizontalGap(base, r)
        if gap > maxGap
            continue

        combined := Max(base.r, r.r) - Min(base.x, r.x)
        if combined < work.w * widthCov
            continue

        score := overlap - gap
        if score > bestScore {
            bestScore := score
            best := other
        }
    }
    return best
}

FindLooseHorizontalPartner(hwnd) {
    if !WinAlive(hwnd)
        return 0
    work := GetWorkAreaForWindow(hwnd)
    base := GetRect(hwnd)
    if !base
        return 0
    terminal := IsTerminalWindow(hwnd)
    minH := work.h * (terminal ? 0.35 : MIN_HEIGHT_RATIO)
    if (base.h < minH)
        return 0

    workMid := work.x + work.w / 2
    baseMid := base.x + base.w / 2
    baseOnLeft := baseMid < workMid

    best := 0
    bestScore := -1.0e9

    for other in WinGetList() {
        if other = hwnd || !IsManagedWindow(other)
            continue
        r := GetRect(other)
        if !r || (r.h < minH)
            continue
        if !SameMonitor(hwnd, other)
            continue

        ; Loose recovery allows partial overlap, but never a contained overlay.
        if HorizontalOverlap(base, r) >= Min(base.w, r.w) - 16
            continue
        otherMid := r.x + r.w / 2
        otherOnLeft := otherMid < workMid
        if (baseOnLeft = otherOnLeft)
            continue

        overlap := VerticalOverlap(base, r)
        if overlap < Min(base.h, r.h) * 0.35
            continue

        gap := HorizontalGap(base, r)
        score := overlap + Min(gap, work.w) * 0.15
        if (base.w < work.w * 0.42)
            score += 80
        if (r.w < work.w * 0.42)
            score += 80
        score -= r.w * 0.05

        if score > bestScore {
            bestScore := score
            best := other
        }
    }
    return best
}

FindRememberedPartner(hwnd) {
    global lastPairLeft, lastPairRight
    if hwnd = lastPairLeft && WinAlive(lastPairRight) && IsManagedWindow(lastPairRight) && SameMonitor(hwnd, lastPairRight)
        return lastPairRight
    if hwnd = lastPairRight && WinAlive(lastPairLeft) && IsManagedWindow(lastPairLeft) && SameMonitor(hwnd, lastPairLeft)
        return lastPairLeft
    return 0
}

IsSplitRecoverState(a, b, work) {
    if HorizontalOverlap(a, b) > 16
        return true
    gap := HorizontalGap(a, b)
    combined := Max(a.r, b.r) - Min(a.x, b.x)
    if gap > MAX_GAP
        return true
    if combined < work.w * WIDTH_COVERAGE
        return true
    if (a.w < work.w * 0.4 && b.w < work.w * 0.4)
        return true
    return false
}

ForceMove(hwnd, x, y, w, h) {
    EnsurePhysicalCoordinates()
    if !IsTargetInWorkArea(hwnd, x, y, w, h)
        return false
    if !WinAlive(hwnd)
        return false
    try {
        flags := 0x0004 | 0x0010  ; SWP_NOZORDER | SWP_NOACTIVATE
        target := VisualTargetToOuter(hwnd, x, y, w, h)
        if DllCall("User32\SetWindowPos", "Ptr", hwnd, "Ptr", 0,
            "Int", target.x, "Int", target.y, "Int", target.w, "Int", target.h, "UInt", flags)
            return true
        WinMove(target.x, target.y, target.w, target.h, "ahk_id " hwnd)
        return true
    } catch {
        return false
    }
}

VisualTargetToOuter(hwnd, x, y, w, h) {
    visual := GetRect(hwnd)
    outer := GetRectOuter(hwnd)
    if !visual || !outer
        return { x: x, y: y, w: w, h: h }

    leftInset := visual.x - outer.x
    topInset := visual.y - outer.y
    rightInset := outer.r - visual.r
    bottomInset := outer.b - visual.b

    return {
        x: x - leftInset,
        y: y - topInset,
        w: w + leftInset + rightInset,
        h: h + topInset + bottomInset
    }
}

IsScriptElevated() {
    return DllCall("Shell32\IsUserAnAdmin")
}

IsWindowElevated(hwnd) {
    try {
        return IsPidElevated(WinGetPID("ahk_id " hwnd))
    } catch {
        return false
    }
}

IsPidElevated(pid) {
    hProc := DllCall("Kernel32\OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
    if !hProc
        return false
    hTok := 0
    if !DllCall("Advapi32\OpenProcessToken", "Ptr", hProc, "UInt", 0x0008, "Ptr*", &hTok) {
        DllCall("Kernel32\CloseHandle", "Ptr", hProc)
        return false
    }
    elev := Buffer(4, 0)
    sz := 0
    ok := DllCall("Advapi32\GetTokenInformation", "Ptr", hTok, "UInt", 20,
        "Ptr", elev, "UInt", 4, "UInt*", &sz)
    DllCall("Kernel32\CloseHandle", "Ptr", hTok)
    DllCall("Kernel32\CloseHandle", "Ptr", hProc)
    return ok && NumGet(elev, 0, "UInt") != 0
}

CanMovePair(a, b) {
    if IsScriptElevated()
        return true
    if IsWindowElevated(a) || IsWindowElevated(b) {
        MaybeShowElevHint()
        return false
    }
    return true
}

MaybeShowElevHint() {
    global elevHintShown
    if elevHintShown
        return
    elevHintShown := true
    ToolTip("관리자 PowerShell/터미널은 이 스크립트도 관리자로 실행해야 움직일 수 있어.")
    SetTimer(() => ToolTip(), -4000)
}

MaybeShowMoveFailedHint(a, b) {
    if IsWindowElevated(a) || IsWindowElevated(b)
        MaybeShowElevHint()
}

RestartAsAdmin(*) {
    if IsScriptElevated()
        return
    try {
        command := A_IsCompiled ? '"' A_ScriptFullPath '"' : '"' A_AhkPath '" "' A_ScriptFullPath '"'
        Run('*RunAs ' command)
        ExitApp()
    } catch {
        ; A cancelled elevation request must leave the current app running.
        return
    }
}

GetRect(hwnd) {
    EnsurePhysicalCoordinates()
    if !WinAlive(hwnd)
        return 0
    try {
        rect := Buffer(16, 0)
        if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9,
            "Ptr", rect, "UInt", 16, "UInt") = 0 {
            x := NumGet(rect, 0, "Int")
            y := NumGet(rect, 4, "Int")
            r := NumGet(rect, 8, "Int")
            b := NumGet(rect, 12, "Int")
            if r > x && b > y
                return { x: x, y: y, w: r - x, h: b - y, r: r, b: b }
        }
        WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        return { x: x, y: y, w: w, h: h, r: x + w, b: y + h }
    } catch {
        return 0
    }
}

GetWorkAreaForWindow(hwnd) {
    EnsurePhysicalCoordinates()
    if !WinAlive(hwnd) {
        MonitorGetWorkArea(, &wl, &wt, &wr, &wb)
        return { x: wl, y: wt, w: wr - wl, h: wb - wt, r: wr, b: wb }
    }
    wl := 0, wt := 0, wr := 0, wb := 0
    if !GetMonitorWorkArea(hwnd, &wl, &wt, &wr, &wb) {
        MonitorGetWorkArea(, &wl, &wt, &wr, &wb)
    }
    return { x: wl, y: wt, w: wr - wl, h: wb - wt, r: wr, b: wb }
}

GetMonitorWorkArea(hwnd, &wl, &wt, &wr, &wb) {
    EnsurePhysicalCoordinates()
    mi := Buffer(40, 0)
    NumPut("UInt", 40, mi)
    hMon := DllCall("User32\MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    if !hMon
        return false
    if !DllCall("User32\GetMonitorInfo", "Ptr", hMon, "Ptr", mi)
        return false
    wl := NumGet(mi, 20, "Int")
    wt := NumGet(mi, 24, "Int")
    wr := NumGet(mi, 28, "Int")
    wb := NumGet(mi, 32, "Int")
    return true
}

MonitorHandle(hwnd) {
    EnsurePhysicalCoordinates()
    return DllCall("User32\MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
}

SameMonitor(a, b) {
    return MonitorHandle(a) = MonitorHandle(b)
}

VerticalOverlap(a, b) {
    top := Max(a.y, b.y)
    bot := Min(a.b, b.b)
    return Max(0, bot - top)
}

HorizontalGap(a, b) {
    if a.r <= b.x
        return b.x - a.r
    if b.r <= a.x
        return a.x - b.r
    return 0
}

HorizontalOverlap(a, b) {
    return Max(0, Min(a.r, b.r) - Max(a.x, b.x))
}

ShowUsage(*) {
    MsgBox("1. 창 두 개를 나란히 놓으세요.`n2. 작은 창의 제목 표시줄을 클릭하거나 Ctrl을 누른 채 클릭하세요.`n3. 청록색 막대를 드래그하면 비율이 바뀝니다.`n4. 막대를 더블클릭하면 좌우 창이 바뀝니다.`n`nCtrl+Alt+F12: 켜기/끄기`n트레이 아이콘: 클릭 방식 변경, 종료`n`n관리자 권한 앱과 함께 사용할 때는 트레이에서 관리자 권한 재시작을 선택하세요.", "Focusing 사용 방법")
}
#Include %A_ScriptDir%\PairShortcuts.ahk
