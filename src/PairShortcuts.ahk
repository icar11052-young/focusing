; 창 묶음 바로가기를 저장하고 복원하는 Windows 포커싱 보조 기능.
; Saved pairs are local to the current Windows user. Only opaque ids enter the queue.
InitPairShortcuts() {
    global pairRoot, activePair, pairBusy, settingsDir
    pairRoot := settingsDir "\Pairs"
    activePair := 0
    pairBusy := false
    DirCreate(pairRoot)
    hostFile := pairRoot "\host.ini"
    IniWrite(A_ScriptHwnd, hostFile, "host", "hwnd")
    IniWrite(DllCall("GetCurrentProcessId"), hostFile, "host", "pid")
    IniWrite(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, hostFile, "host", "exe")
    IniWrite(A_IsCompiled ? "" : A_ScriptFullPath, hostFile, "host", "script")
    OnMessage(0x205, HandlePairRightClick) ; WM_RBUTTONUP
    SetTimer(PollPairRequests, 250)
}

HandlePairRightClick(wParam, lParam, msg, hwnd) {
    global handleGuiHwnd, handleDragging, handleDragArmed, pairBusy
    if hwnd != handleGuiHwnd || handleDragging || handleDragArmed || pairBusy
        return
    pairMenu := Menu()
    pairMenu.Add("이 두 창 바로가기 만들기", CreatePairShortcut)
    pairMenu.Show()
    return 0
}

PairFile(id) {
    global pairRoot
    if !RegExMatch(id, "^[a-f0-9]{32}$")
        throw Error("잘못된 묶음 ID입니다.")
    return pairRoot "\" id ".ini"
}

PairQuote(value) {
    if InStr(value, Chr(34)) || InStr(value, "`r") || InStr(value, "`n")
        throw Error("경로 또는 주소에 지원하지 않는 문자가 있습니다.")
    return Chr(34) value Chr(34)
}

RunPairTool(mode, id, left := 0, right := 0) {
    global pairRoot
    helper := A_ScriptDir "\PairTools.ps1"
    if !FileExist(helper)
        throw Error("PairTools.ps1 파일을 찾을 수 없습니다.")
    cmd := PairQuote(A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe")
        . " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " PairQuote(helper)
        . " -Mode " mode " -PairId " id " -Root " PairQuote(pairRoot)
    if mode = "Capture"
        cmd .= " -Left " left " -Right " right
    Run(cmd, A_ScriptDir, "Hide", &helperPid)
    if ProcessWaitClose(helperPid, 15) {
        ProcessClose(helperPid)
        throw Error("앱 정보를 읽는 데 시간이 너무 오래 걸렸습니다. 다시 시도해 주세요.")
    }
    ; Capture output and shortcut creation are checked separately by the caller.
}

CreatePairShortcut(*) {
    global lastPairLeft, lastPairRight, pairBusy, pairRoot, activePair
    if pairBusy
        return
    EnsurePairOrder()
    left := lastPairLeft, right := lastPairRight
    if !IsManagedWindow(left) || !IsManagedWindow(right) {
        MsgBox("먼저 사용할 창 두 개를 포커싱으로 배치해 주세요.", "Focusing")
        return
    }
    pairBusy := true
    id := ""
    saved := false
    try {
        guid := Buffer(16)
        DllCall("ole32\CoCreateGuid", "Ptr", guid)
        Loop 16
            id .= Format("{:02x}", NumGet(guid, A_Index-1, "UChar"))
        file := PairFile(id)
        RunPairTool("Capture", id, left, right)
        if !FileExist(file)
            throw Error("앱 정보를 저장하지 못했습니다. 앱 실행 권한을 확인해 주세요.")
        if !WinAlive(left) || !WinAlive(right)
            throw Error("저장하려는 창이 닫혔습니다. 다시 선택해 주세요.")
        leftName := IniRead(file,"left","name","App")
        rightName := IniRead(file,"right","name","App")
        name := SubStr(leftName,1,45) " + " SubStr(rightName,1,45)
        name := Trim(RegExReplace(name,'[<>:"/\\|?*\x00-\x1f]',"_")," .")
        IniWrite(name,file,"pair","name")
        ; Only app identity and layout are saved; browser startup settings apply.
        ratio := PairLeftRatio(GetRectOuter(left),GetRectOuter(right))
        IniWrite(ratio,file,"pair","leftRatio")
        IniWrite("left",file,"pair","leftEndpoint")
        RunPairTool("Shortcut",id)
        marker := pairRoot "\" id ".created"
        if !FileExist(marker)
            throw Error("바로가기를 만들지 못했습니다. 앱 실행 경로를 확인해 주세요.")
        saved := true
        ; A saved shortcut remains valid even if marker cleanup fails.
        try FileDelete(marker)
        activePair := {id:id, first:left, second:right}
        ToolTip("바탕화면에 " name " 바로가기를 만들었습니다.")
        SetTimer(() => ToolTip(),-2000)
    } catch Error as e {
        if id != "" && !saved && !FileExist(pairRoot "\" id ".created") {
            for ext in [".ini",".ico"] {
                try FileDelete(pairRoot "\" id ext)
            }
        }
        MsgBox(e.Message,"Focusing")
    } finally {
        pairBusy := false
    }
}


PairLeftRatio(left,right) {
    if !left || !right || left.w + right.w <= 0
        throw Error("창 크기를 읽을 수 없습니다.")
    return Max(0.15,Min(0.85,left.w/(left.w+right.w)))
}

PersistActivePair() {
    global activePair,lastPairLeft,lastPairRight
    if !IsSet(activePair) || !activePair
        return
    if !((lastPairLeft=activePair.first && lastPairRight=activePair.second)
        || (lastPairLeft=activePair.second && lastPairRight=activePair.first)) {
        activePair := 0
        return
    }
    try {
        file := PairFile(activePair.id)
        IniWrite(PairLeftRatio(GetRectOuter(lastPairLeft),GetRectOuter(lastPairRight)),file,"pair","leftRatio")
        IniWrite(lastPairLeft=activePair.first ? "left" : "right",file,"pair","leftEndpoint")
    }
}

PollPairRequests(*) {
    global pairRoot,pairBusy,handleDragging,handleDragArmed
    if pairBusy || handleDragging || handleDragArmed
        return
    Loop Files pairRoot "\*.request" {
        request := A_LoopFileFullPath
        try {
            id := IniRead(request,"request","id","")
            file := PairFile(id)
            first := Integer(IniRead(request,"request","left",0))
            second := Integer(IniRead(request,"request","right",0))
            if first = second || !WinAlive(first) || !WinAlive(second)
                throw Error("사용할 창 두 개가 열려 있지 않습니다.")
            for endpoint in ["left","right"] {
                hwnd := endpoint="left" ? first : second
                if WinGetPID("ahk_id " hwnd) != Integer(IniRead(request,"request",endpoint "Pid",0))
                    throw Error("창이 변경되어 배치를 취소했습니다.")
                ; Requests can only move ordinary visible top-level windows, never run commands.
                style := WinGetStyle("ahk_id " hwnd), ex := WinGetExStyle("ahk_id " hwnd)
                if !(style & 0x10000000) || IsAuxiliaryWindowStyle(style,ex)
                    throw Error("이 창은 묶음 배치를 지원하지 않습니다.")
            }
            RestoreSavedPair(id,first,second)
            FileAppend("OK",request ".done","UTF-8-RAW")
        } catch Error as e {
            FileAppend(e.Message,request ".done","UTF-8-RAW")
        }
        try FileDelete(request)
        break ; Keep mouse interaction responsive between requests.
    }
}

RestoreSavedPair(id,first,second) {
    global activePair,enabled,lastSwapTick
    file := PairFile(id)
    ratio := Number(IniRead(file,"pair","leftRatio",2/3))
    if ratio < 0.15 || ratio > 0.85
        throw Error("저장된 비율이 올바르지 않습니다.")
    reversed := IniRead(file,"pair","leftEndpoint","left") = "right"
    left := reversed ? second : first
    right := reversed ? first : second
    for hwnd in [left,right] {
        if WinGetMinMax("ahk_id " hwnd) != 0
            WinRestore("ahk_id " hwnd)
    }
    work := GetWorkAreaForWindow(left)
    activePair := 0
    if !ApplySplit(left,right,work.x,work.y,Round(work.w*ratio),work.w-Round(work.w*ratio),work.h)
        throw Error("창 배치를 적용하지 못했습니다. 앱 권한과 최소 창 크기를 확인해 주세요.")
    activePair := {id:id,first:first,second:second}
    enabled := true
    lastSwapTick := A_TickCount
    for endpoint in ["left","right"] {
        hwnd := endpoint="left" ? first : second
        IniWrite(hwnd,file,endpoint,"hwnd")
        IniWrite(WinGetPID("ahk_id " hwnd),file,endpoint,"pid")
    }
    PersistActivePair()
    WinActivate("ahk_id " (ratio>=0.5 ? left : right))
    UpdateTrayTip()
    RefreshHandle()
}
