// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 icar11052-young
// 두 창 배치와 지정 앱의 첫 클릭 보정을 제공하는 개인용 포커싱 앱.
import AppKit
import ApplicationServices
import ServiceManagement

// 지정한 네 앱의 비활성 창을 첫 클릭 직전에 활성화하고 원래 이벤트를 한 번 전달한다.

final class ClickThrough {
    static let targets: Set<String> = ["com.naver.Whale", "com.google.Chrome", "com.openai.codex", "com.openai.chat", "com.google.antigravity", "com.google.antigravity-ide"]
    var enabled = UserDefaults.standard.bool(forKey: "clickThroughEnabled")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var log: (String) -> Void = { _ in }
    func start() {
        guard AXIsProcessTrusted() else { log("clickthrough permission-missing"); return }
        let mask = CGEventMask(1) << CGEventType.leftMouseDown.rawValue
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<ClickThrough>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                owner.log("clickthrough tap-reenabled")
            } else if type == .leftMouseDown { owner.prepare(event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap = tap else { log("clickthrough tap-unavailable"); return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        log("clickthrough ready enabled=\(enabled) targets=\(Self.targets.sorted().joined(separator: ","))")
    }
    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil; tap = nil
    }
    deinit { stop() }
    func toggle() {
        enabled.toggle(); UserDefaults.standard.set(enabled, forKey: "clickThroughEnabled")
        log("clickthrough enabled=\(enabled)")
    }
    private func prepare(_ event: CGEvent) {
        guard enabled, event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else { return }
        let began = ProcessInfo.processInfo.systemUptime
        // Accessibility hit-testing ignores transparent Dock/Notification Center surfaces.
        let pt = event.location
        var hit: AXUIElement?
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.025)
        guard AXUIElementCopyElementAtPosition(system, Float(pt.x), Float(pt.y), &hit) == .success, let hit = hit else { return }
        var pid: pid_t = 0; AXUIElementGetPid(hit, &pid)
        guard let app = NSRunningApplication(processIdentifier: pid), let bid = app.bundleIdentifier,
              Self.targets.contains(bid) else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.025)
        AXUIElementSetMessagingTimeout(hit, 0.025)
        let window: AXUIElement
        if readAX(hit, kAXRoleAttribute) as? String == kAXWindowRole { window = hit }
        else if let value = readAX(hit, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() { window = value as! AXUIElement }
        else { return }
        AXUIElementSetMessagingTimeout(window, 0.025)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           let focused = readAX(axApp, kAXFocusedWindowAttribute), CFEqual(focused, window) { return }
        guard ProcessInfo.processInfo.systemUptime - began < 0.075 else { return }
        // No click is generated or swallowed. Focus is established before the held original down continues.
        app.activate(options: [])
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        var focused = false
        while ProcessInfo.processInfo.systemUptime - began < 0.16 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
               let current = readAX(axApp, kAXFocusedWindowAttribute), CFEqual(current, window) {
                focused = true; Thread.sleep(forTimeInterval: 0.012); break
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        let ms = Int((ProcessInfo.processInfo.systemUptime - began) * 1000)
        log("clickthrough focus=\(focused) app=\(bid) elapsedMs=\(ms)")
    }
}

func readAX(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success ? v : nil
}
func rectAX(_ e: AXUIElement) -> CGRect? {
    guard let p = readAX(e,kAXPositionAttribute), let s = readAX(e,kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue,.cgPoint,&point), AXValueGetValue(s as! AXValue,.cgSize,&size) else { return nil }
    return CGRect(origin:point,size:size)
}
func setRect(_ e: AXUIElement, _ r: CGRect) -> Bool {
    var pid:pid_t=0;AXUIElementGetPid(e,&pid)
    let app=AXUIElementCreateApplication(pid)
    let enhanced=(readAX(app,"AXEnhancedUserInterface") as? Bool)==true
    if enhanced {_=AXUIElementSetAttributeValue(app,"AXEnhancedUserInterface" as CFString,kCFBooleanFalse)}
    defer {if enhanced{_=AXUIElementSetAttributeValue(app,"AXEnhancedUserInterface" as CFString,kCFBooleanTrue)}}
    func write(_ key:String,_ value:inout CGSize)->Bool {
        guard let v=AXValueCreate(.cgSize,&value) else{return false}
        return AXUIElementSetAttributeValue(e,key as CFString,v) == .success
    }
    var p=r.origin;var size=r.size
    guard let position=AXValueCreate(.cgPoint,&p) else{return false}
    // Shrink before moving right so the old wide frame cannot be clamped off-screen.
    if let old=rectAX(e) {
        var intermediate=CGSize(width:min(old.width,r.width),height:min(old.height,r.height))
        if intermediate != old.size {_=write(kAXSizeAttribute,&intermediate);Thread.sleep(forTimeInterval:0.025)}
    }
    var last=CGRect.zero;var stable=0
    for attempt in 0..<24 {
        if attempt==0 || (stable==0 && attempt%4==0) {
            _=AXUIElementSetAttributeValue(e,kAXPositionAttribute as CFString,position)
            _=write(kAXSizeAttribute,&size)
            Thread.sleep(forTimeInterval:0.025)
            // Chromium may adjust position while applying a size. Set the final position again.
            _=AXUIElementSetAttributeValue(e,kAXPositionAttribute as CFString,position)
        }
        Thread.sleep(forTimeInterval:0.025)
        if let actual=rectAX(e) {
            last=actual
            if abs(actual.width-r.width)<3 && abs(actual.height-r.height)<3 && abs(actual.minX-r.minX)<3 && abs(actual.minY-r.minY)<3 {stable+=1;if stable>=4{return true}}
            else{stable=0}
        }
    }
    print("Focusing geometry rejected target=\(r) actual=\(last)")
    return false
}
func split(_ r:CGRect,_ f:Double)->(CGRect,CGRect) {
    let w=(r.width * min(0.85,max(0.15,f))).rounded()
    return (CGRect(x:r.minX,y:r.minY,width:w,height:r.height),CGRect(x:r.minX+w,y:r.minY,width:r.width-w,height:r.height))
}
func cocoa(_ r:CGRect)->CGRect { CGRect(x:r.minX,y:(NSScreen.screens.first?.frame.maxY ?? 0)-r.maxY,width:r.width,height:r.height) }
struct Win { let ax:AXUIElement; let pid:pid_t; let rect:CGRect }
class Handle: NSView {
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool {true}
    weak var owner:FocusApp?
    var startX:CGFloat=0;var dragging=false
    override func draw(_ r:NSRect) { NSColor.systemTeal.setFill(); NSBezierPath(roundedRect:bounds,xRadius:4,yRadius:4).fill() }
    override func mouseDown(with e:NSEvent) {startX=NSEvent.mouseLocation.x;dragging=false;if e.clickCount==2 {owner?.swapPair(nil)}}
    override func mouseDragged(with e:NSEvent) {if abs(NSEvent.mouseLocation.x-startX)>6{dragging=true};if dragging{owner?.drag(NSEvent.mouseLocation.x)}}
    override func mouseUp(with e:NSEvent) {if dragging{owner?.saveRatio()};dragging=false}
}
class FocusApp:NSObject,NSApplicationDelegate {
    let clickThrough = ClickThrough()
    var clickThroughMenu: NSMenuItem?
    var loginMenu: NSMenuItem?
    var status:NSStatusItem!; var panel:NSPanel!; var info:NSWindow?; var label:NSTextField?
    var pair:(Win,Win)?; var original:(CGRect,CGRect)?; var area:CGRect = .zero
    var ratio=2.0/3.0; var leftFraction=2.0/3.0; var enabled=true; var busy=false; var monitors:[Any]=[]; var timer:Timer?
    func trace(_ text:String) {
        let p=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Focusing.log")
        let data=(Date().description+" "+text+"\n").data(using:.utf8)!
        if !FileManager.default.fileExists(atPath:p.path) || ((try? FileManager.default.attributesOfItem(atPath:p.path)[.size] as? Int) ?? 0)>1_000_000 {try? data.write(to:p)}else if let f=try? FileHandle(forWritingTo:p){defer{try? f.close()};_=try? f.seekToEnd();try? f.write(contentsOf:data)}
    }
    var pendingClick:(AXUIElement,CGPoint)?;var lastAction=Date.distantPast;var learnedPair=false
    var mode=UserDefaults.standard.string(forKey:"trigger") ?? "ctrl_or_titlebar"
    func applicationDidFinishLaunching(_ n:Notification) {
        NSApp.setActivationPolicy(.accessory)
        if mode=="any" {mode="ctrl_or_titlebar";UserDefaults.standard.set(mode,forKey:"trigger")}
        trace("launch trusted=\(AXIsProcessTrusted())");let stored=UserDefaults.standard.double(forKey:"ratio"); if stored>=0.5 && stored<=0.85 {ratio=stored}
        clickThrough.log = { [weak self] text in self?.trace(text) }
        if !CommandLine.arguments.contains("--integration-test"){clickThrough.start()}
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);status.button?.title="◧"
        let menu=NSMenu()
        add(menu,"포커싱 · 사용 안내",#selector(showInfo),"")
        add(menu,"왼쪽 크게",#selector(left),"1");add(menu,"오른쪽 크게",#selector(right),"2");add(menu,"좌우 바꾸기",#selector(swapPair),"s")
        add(menu,"원래 배치로 복원",#selector(restore),""); menu.addItem(.separator())
        add(menu,"일시정지 / 재개",#selector(toggle),"");add(menu,"클릭 방식 변경",#selector(cycle),"")
        add(menu,"비율 2:1로 초기화",#selector(resetRatio),"");add(menu,"손쉬운 사용 권한 요청",#selector(permission),"")
        menu.addItem(.separator())
        let ct=NSMenuItem(title:"첫 클릭 바로 동작 (지원 앱)",action:#selector(toggleClickThrough),keyEquivalent:"");ct.target=self;ct.state=clickThrough.enabled ? .on:.off;menu.addItem(ct);clickThroughMenu=ct
        let login=NSMenuItem(title:"로그인 시 자동 실행",action:#selector(toggleLogin),keyEquivalent:"");login.target=self;login.state=SMAppService.mainApp.status == .enabled ? .on:.off;menu.addItem(login);loginMenu=login
        menu.addItem(.separator());add(menu,"종료",#selector(quit),"q");status.menu=menu
        panel=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .floating;panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.hidesOnDeactivate=false
        let h=Handle(frame:.zero);h.owner=self;panel.contentView=h
        if let m=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseUp],handler:{[weak self] e in self?.clicked(e)}) {monitors.append(m)}
        if let m=NSEvent.addGlobalMonitorForEvents(matching:[.keyDown],handler:{[weak self] e in
            if e.keyCode==111 && e.modifierFlags.contains([.control,.option]){self?.toggle(nil);return}
            guard e.modifierFlags.intersection(.deviceIndependentFlagsMask).contains([.command,.option,.shift]) else{return}
            switch e.keyCode{case 18:self?.left(nil);case 19:self?.right(nil);case 1:self?.swapPair(nil);case 17:self?.cycle(nil);default:break}
        }) {monitors.append(m)}
        timer=Timer.scheduledTimer(withTimeInterval:0.7,repeats:true){[weak self] _ in self?.refresh()}
        if CommandLine.arguments.contains("--integration-test") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.integrationTest()}
        } else if !AXIsProcessTrusted(){showInfo(nil)}
    }
    func add(_ m:NSMenu,_ title:String,_ action:Selector,_ key:String){let i=NSMenuItem(title:title,action:action,keyEquivalent:key);i.target=self;i.keyEquivalentModifierMask=[.command,.option,.shift];m.addItem(i)}
    func windows()->[Win] {
        let visible=(CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []).filter{($0[kCGWindowLayer as String] as? Int)==0}
        var result:[Win]=[];var done=Set<pid_t>()
        for d in visible {
            guard let pid=d[kCGWindowOwnerPID as String] as? pid_t,pid != getpid(), !done.contains(pid) else{continue};done.insert(pid)
            let app=AXUIElementCreateApplication(pid);AXUIElementSetMessagingTimeout(app,0.15)
            guard let ws=readAX(app,kAXWindowsAttribute) as? [AXUIElement] else{continue}
            for e in ws {
                guard (readAX(e,kAXSubroleAttribute) as? String)==kAXStandardWindowSubrole,
                      (readAX(e,kAXMinimizedAttribute) as? Bool) != true,
                      (readAX(e,"AXFullScreen") as? Bool) != true,
                      let r=rectAX(e),r.width>=240,r.height>=160 else{continue}
                var settable:DarwinBoolean=false
                guard AXUIElementIsAttributeSettable(e,kAXSizeAttribute as CFString,&settable) == .success,settable.boolValue else{continue}
                let onScreen=visible.contains{v in guard (v[kCGWindowOwnerPID as String] as? pid_t)==pid,let b=v[kCGWindowBounds as String] as? NSDictionary,let cr=CGRect(dictionaryRepresentation:b) else{return false};return abs(cr.minX-r.minX)<6 && abs(cr.minY-r.minY)<6 && abs(cr.width-r.width)<6}
                if onScreen {result.append(Win(ax:e,pid:pid,rect:r))}
            }
        }
        return result
    }
    func candidate(_ clicked:AXUIElement?=nil)->(Win,Win)? {
        let ws=windows()
        for a in ws {
            if let c=clicked,!CFEqual(c,a.ax){continue}
            for b in ws where !CFEqual(a.ax,b.ax) {
                let l=a.rect.minX < b.rect.minX ? a:b; let r=a.rect.minX < b.rect.minX ? b:a
                let overlap=min(l.rect.maxY,r.rect.maxY)-max(l.rect.minY,r.rect.minY)
                guard abs(l.rect.maxX-r.rect.minX)<48,overlap>min(l.rect.height,r.rect.height)*0.85,abs(l.rect.height-r.rect.height)<60 else{continue}
                let union=l.rect.union(r.rect)
                guard NSScreen.screens.contains(where:{$0.frame.insetBy(dx:-3,dy:-3).contains(cocoa(union))}) else{continue}
                return(l,r)
            }
        };return nil
    }
    func target(_ pt:CGPoint)->(AXUIElement,AXUIElement)? {
        var hit:AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(pt.x),Float(pt.y),&hit) == .success,let h=hit else{return nil}
        if (readAX(h,kAXRoleAttribute) as? String)==kAXWindowRole{return(h,h)}
        if let v=readAX(h,kAXWindowAttribute),CFGetTypeID(v)==AXUIElementGetTypeID(){return(h,v as! AXUIElement)}
        return nil
    }
    // A custom tab can be exposed only as AXGroup. Never infer a caption
    // from proximity to the top edge or from eventually reaching its window.
    func isCaption(_ hit:AXUIElement,_ w:AXUIElement,_ pt:CGPoint)->Bool {
        guard let r=rectAX(w),pt.y-r.minY>=0,pt.y-r.minY<38 else{return false}
        if CFEqual(hit,w) && (readAX(hit,kAXRoleAttribute) as? String)==kAXWindowRole {return true}
        return whaleBlankCaption(hit,w,pt)
    }
    // Whale hit-tests its entire tab strip as AXGroup, including real tabs.
    // Only the trailing blank space beyond positively identified tab controls is accepted.
    func whaleCaptionRegions(_ w:AXUIElement)->(CGRect,[CGRect],[CGRect])? {
        var pid:pid_t=0;AXUIElementGetPid(w,&pid)
        guard NSRunningApplication(processIdentifier:pid)?.bundleIdentifier=="com.naver.Whale",let frame=rectAX(w) else{return nil}
        var tabs:[CGRect]=[];var controls:[CGRect]=[];var strip:CGRect?;var nodes=0
        let top=CGRect(x:frame.minX,y:frame.minY,width:frame.width,height:44)
        func walk(_ e:AXUIElement,_ depth:Int,_ inTabs:Bool) {
            guard depth<13,nodes<250 else{return};nodes+=1
            let role=readAX(e,kAXRoleAttribute) as? String ?? ""
            if ["AXWebArea","AXScrollArea","AXToolbar"].contains(role){return}
            let box=rectAX(e)
            if let b=box,!b.isEmpty,!b.intersects(top){return}
            let tabGroup=role=="AXTabGroup" && box != nil && box!.height<=50 && box!.minY<frame.minY+15
            if tabGroup{strip=box}
            let isTab=(readAX(e,kAXSubroleAttribute) as? String)=="AXTabButton" || role=="AXTab" || (inTabs && role=="AXRadioButton")
            if let b=box,!b.isEmpty {
                if isTab {tabs.append(b)}
                if isTab || ["AXButton","AXPopUpButton","AXCheckBox","AXRadioButton","AXTextField","AXComboBox"].contains(role){controls.append(b)}
            }
            for c in readAX(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] {walk(c,depth+1,inTabs || tabGroup)}
        }
        walk(w,0,false)
        guard let strip=strip,!tabs.isEmpty else{return nil}
        return(strip,tabs,controls)
    }
    func whaleBlankCaption(_ hit:AXUIElement,_ w:AXUIElement,_ pt:CGPoint)->Bool {
        guard ["AXGroup","AXImage","AXStaticText"].contains(readAX(hit,kAXRoleAttribute) as? String ?? ""),
              let frame=rectAX(w),let (strip,tabs,controls)=whaleCaptionRegions(w) else{return false}
        if controls.contains(where:{$0.insetBy(dx:-3,dy:-3).contains(pt)}){return false}
        // Whale's decorative logo lives beyond the tab strip, at the top-right edge.
        let logo=CGRect(x:max(strip.maxX,frame.maxX-96),y:frame.minY,width:min(96,frame.maxX-strip.maxX),height:38)
        if logo.width>0 && logo.contains(pt){return true}
        guard strip.contains(pt) else{return false}
        let tabsRight=tabs.map{$0.maxX}.max() ?? strip.maxX
        guard pt.x>tabsRight+6 else{return false}
        // Include the adjacent new-tab button in the protected trailing edge.
        let trailing=controls.filter{$0.minX<tabsRight+60 && $0.maxX>tabsRight-6}.map{$0.maxX}.max() ?? tabsRight
        guard pt.x>trailing+6 else{return false}
        return !controls.contains{$0.insetBy(dx:-3,dy:-3).contains(pt)}
    }
    func clicked(_ e:NSEvent) {
        guard enabled,!busy,AXIsProcessTrusted(),let pt=e.cgEvent?.location else{pendingClick=nil;return}
        if e.type == .leftMouseDown {
            pendingClick=nil
            guard Date().timeIntervalSince(lastAction)>0.35,let (h,w)=target(pt) else{return}
            let ctrl=e.modifierFlags.contains(.control);let title=isCaption(h,w,pt)
            let allowed=(mode=="ctrl" && ctrl) || (mode=="titlebar" && title) || (mode=="ctrl_or_titlebar" && (ctrl || title))
            trace("down role=\(readAX(h,kAXRoleAttribute) as? String ?? "?") caption=\(title) allowed=\(allowed)")
            if allowed {pendingClick=(w,pt)};return
        }
        guard let down=pendingClick else{return};pendingClick=nil
        guard abs(pt.x-down.1.x)<=6,abs(pt.y-down.1.y)<=6,let (_,upWindow)=target(pt),CFEqual(down.0,upWindow) else{return}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.08){[weak self] in self?.expand(down.0)}
    }
    func expand(_ w:AXUIElement) {
        guard enabled,!busy,let p=candidate(w) else{return}
        let isNew = pair == nil || !(CFEqual(pair!.0.ax,p.0.ax) && CFEqual(pair!.1.ax,p.1.ax)) || !learnedPair
        bind(p)
        if isNew {ratio=2.0/3.0}
        let clickedLeft=CFEqual(w,p.0.ax);let selected=clickedLeft ? p.0.rect.width:p.1.rect.width;let other=clickedLeft ? p.1.rect.width:p.0.rect.width
        if !isNew && abs(selected-other)>=area.width*0.12 && selected>=other*0.92{return}
        apply(clickedLeft ? ratio:1-ratio);learnedPair=true;lastAction=Date()
    }
    func bind(_ p:(Win,Win)) {
        if pair == nil || !CFEqual(pair!.0.ax,p.0.ax) || !CFEqual(pair!.1.ax,p.1.ax){original=(p.0.rect,p.1.rect);learnedPair=false}
        pair=p
        let union=p.0.rect.union(p.1.rect)
        if let screen=NSScreen.screens.first(where:{$0.frame.insetBy(dx:-3,dy:-3).contains(cocoa(union))}) {area=cocoa(screen.visibleFrame)}else{area=union}
        leftFraction=p.0.rect.width/area.width
    }
    func ensure()->Bool {if let old=pair,let p=candidate(old.0.ax){bind(p);return true};if let p=candidate(){bind(p);return true};note("창 두 개를 같은 화면에 나란히 놓아 주세요.");return false}
    func apply(_ f:Double){guard let p=pair,!busy else{return};busy=true;defer{busy=false}
        let oldL=rectAX(p.0.ax);let oldR=rectAX(p.1.ax);let (l,r)=split(area,f)
        let okL=setRect(p.0.ax,l);let okR=setRect(p.1.ax,r);trace("apply f=\(f) left=\(okL) right=\(okR)")
        if !okL || !okR {trace("layout rollback leftActual=\(String(describing:rectAX(p.0.ax))) rightActual=\(String(describing:rectAX(p.1.ax))) leftTarget=\(l) rightTarget=\(r)");if let a=oldL {_=setRect(p.0.ax,a)};if let b=oldR {_=setRect(p.1.ax,b)};panel.orderOut(nil);note("이 창의 최소 크기 또는 권한 때문에 배치할 수 없어 원래 위치로 복원했어요.");return}
        leftFraction=f;learnedPair=true;saveRatio();trace("pair pids=\(p.0.pid),\(p.1.pid)");updateHandle();note("포커싱 실행 중 · \(mode)")
    }
    func updateHandle(){guard enabled,let p=pair,let l=rectAX(p.0.ax),let r=rectAX(p.1.ax),abs(l.maxX-r.minX)<10 else{panel.orderOut(nil);return}
        let box=cocoa(CGRect(x:l.maxX-4,y:max(l.minY,r.minY)+max(0,min(l.height,r.height)/2-40),width:8,height:80))
        panel.setFrame(box,display:true);panel.orderFrontRegardless()
    }
    func refresh(){if CommandLine.arguments.contains("--integration-test"){return};guard enabled,AXIsProcessTrusted(),!busy else{panel.orderOut(nil);return}
        guard let p=candidate() else{panel.orderOut(nil);return};bind(p);updateHandle()
    }
    func drag(_ x:CGFloat){guard area.width>0 else{return};apply(min(0.85,max(0.15,(x-area.minX)/area.width)))}
    func saveRatio(){ratio=max(leftFraction,1-leftFraction);if CommandLine.arguments.contains("--integration-test"){return};UserDefaults.standard.set(ratio,forKey:"ratio")}
    func note(_ s:String){label?.stringValue=s;status.button?.toolTip=s}
    @objc func left(_ s:Any?){if ensure(){apply(ratio)}}
    @objc func right(_ s:Any?){if ensure(){apply(1-ratio)}}
    @objc func swapPair(_ s:Any?){guard let p=pair,let l=rectAX(p.0.ax),let r=rectAX(p.1.ax) else{return};let a=setRect(p.0.ax,r);let b=setRect(p.1.ax,l);if a && b{pair=(p.1,p.0);if let o=original{original=(o.1,o.0)}}else{_=setRect(p.0.ax,l);_=setRect(p.1.ax,r)};updateHandle()}
    @objc func restore(_ s:Any?){guard let p=pair,let o=original else{return};_=setRect(p.0.ax,o.0);_=setRect(p.1.ax,o.1);panel.orderOut(nil);pair=nil}
    @objc func toggle(_ s:Any?){enabled.toggle();status.button?.title=enabled ? "◧":"◫";refresh()}
    @objc func cycle(_ s:Any?){let modes=["ctrl_or_titlebar","ctrl","titlebar"];mode=modes[((modes.firstIndex(of:mode) ?? 0)+1)%modes.count];UserDefaults.standard.set(mode,forKey:"trigger");note("클릭 방식 · \(mode)");showInfo(nil)}
    @objc func resetRatio(_ s:Any?){ratio=2/3;UserDefaults.standard.set(ratio,forKey:"ratio")}
    @objc func permission(_ s:Any?){let opt=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary;_=AXIsProcessTrustedWithOptions(opt)}
    @objc func showInfo(_ s:Any?){if info==nil {
        let w=NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:300),styleMask:[.titled,.closable],backing:.buffered,defer:false);w.title="포커싱";w.isReleasedWhenClosed=false
        let l=NSTextField(wrappingLabelWithString:"");l.frame=NSRect(x:24,y:120,width:430,height:155);w.contentView?.addSubview(l);label=l
        let b=NSButton(title:"손쉬운 사용 권한 요청",target:self,action:#selector(permission));b.frame=NSRect(x:24,y:20,width:220,height:32);w.contentView?.addSubview(b);for (i,item) in [("왼쪽 크게",#selector(left)),("오른쪽 크게",#selector(right)),("좌우 교환",#selector(swapPair)),("원래 배치",#selector(restore))].enumerated(){
            let b=NSButton(title:item.0,target:self,action:item.1);b.frame=NSRect(x:24+i*110,y:70,width:105,height:32);w.contentView?.addSubview(b)
        };info=w;w.center()
        }
        label?.stringValue="두 창을 같은 화면에 나란히 배치해 주세요.\n작은 창의 제목줄 또는 Control+클릭으로 확대합니다.\n청록 막대 드래그로 비율 조절, 더블클릭으로 좌우 교환.\n⌘⌥⇧1 / 2 / S · 왼쪽 / 오른쪽 / 교환\n권한 \(AXIsProcessTrusted() ? "허용됨":"필요") · 클릭 방식 \(mode)"
        info?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func integrationTest(){
        let fixtures=Set(NSWorkspace.shared.runningApplications.filter{$0.bundleIdentifier=="com.young.focusing.fixture"}.map{$0.processIdentifier})
        let ws=windows().filter{fixtures.contains($0.pid)}.sorted{$0.rect.minX<$1.rect.minX}
        guard AXIsProcessTrusted(),ws.count==2 else{print("FAIL: fixture windows or permission missing");exit(2)}
        bind((ws[0],ws[1]));let before=(ws[0].rect,ws[1].rect)
        func check(_ c:Bool,_ name:String){if !c{print("FAIL: \(name)");_=setRect(ws[0].ax,before.0);_=setRect(ws[1].ax,before.1);exit(3)};print("PASS: \(name)")}
        check(isCaption(ws[0].ax,ws[0].ax,CGPoint(x:before.0.midX,y:before.0.minY+10)),"blank title bar accepted")
        check(!isCaption(ws[0].ax,ws[0].ax,CGPoint(x:before.0.midX,y:before.0.minY+100)),"body click excluded")
        func button(_ e:AXUIElement,_ depth:Int,_ role:String="AXButton")->AXUIElement?{
            if depth>8{return nil}
            if (readAX(e,kAXRoleAttribute) as? String)==role{return e}
            for child in readAX(e,kAXChildrenAttribute) as? [AXUIElement] ?? []{if let b=button(child,depth+1,role){return b}}
            return nil
        }
        if let b=button(ws[0].ax,0){check(!isCaption(b,ws[0].ax,CGPoint(x:before.0.midX,y:before.0.minY+10)),"title-bar button excluded")}
        if let tab=button(ws[0].ax,0,"AXTabGroup"){check(!isCaption(tab,ws[0].ax,CGPoint(x:before.0.midX,y:before.0.minY+10)),"tab group excluded even in title strip")}else{check(false,"fixture tab group exists")}
        if let group=button(ws[0].ax,0,"AXGroup"){check(!isCaption(group,ws[0].ax,CGPoint(x:before.0.midX,y:before.0.minY+10)),"opaque AXGroup custom tab excluded in title strip")}else{check(false,"fixture opaque group exists")}
        apply(2.0/3.0);check(abs((rectAX(ws[0].ax)?.width ?? 0)-area.width*2/3)<2,"left expansion fills work area")
        apply(1.0/3.0);check(abs((rectAX(ws[1].ax)?.width ?? 0)-area.width*2/3)<2,"right expansion fills work area")
        let beforeSwap=rectAX(ws[0].ax)!;swapPair(nil);check(rectAX(ws[1].ax)==beforeSwap,"swap positions")
        for i in 0..<12 {
            let f=i%2==0 ? 2.0/3.0:1.0/3.0
            apply(f);let wanted=split(area,f)
            Thread.sleep(forTimeInterval:0.55)
            let a=rectAX(pair!.0.ax)!;let b=rectAX(pair!.1.ax)!
            check(abs(a.minX-wanted.0.minX)<3 && abs(a.width-wanted.0.width)<3 && abs(b.minX-wanted.1.minX)<3 && abs(b.width-wanted.1.width)<3,"alternating layout remains stable after 550ms #\(i+1)")
        }
        restore(nil);check(rectAX(ws[0].ax)==before.0 && rectAX(ws[1].ax)==before.1,"restore original windows")
        NSApp.terminate(nil)
    }
    @objc func toggleLogin(_ s:Any?){
        do {
            if SMAppService.mainApp.status == .enabled {try SMAppService.mainApp.unregister()}
            else {try SMAppService.mainApp.register()}
            loginMenu?.state=SMAppService.mainApp.status == .enabled ? .on:.off
        } catch {let alert=NSAlert();alert.messageText="자동 실행 설정을 변경하지 못했어요.";alert.informativeText=error.localizedDescription;alert.runModal()}
    }
    @objc func toggleClickThrough(_ s:Any?){clickThrough.toggle();clickThroughMenu?.state=clickThrough.enabled ? .on:.off}
    @objc func quit(_ s:Any?){NSApp.terminate(nil)}
}
if CommandLine.arguments.contains("--self-test") {
    for r in [CGRect(x:0,y:25,width:1920,height:1000),CGRect(x:-2560,y:-300,width:2560,height:1400)] {
        for f in [0.2,0.3333,0.5,0.6666,0.8]{let (l,rr)=split(r,f);precondition(l.maxX==rr.minX && l.union(rr)==r && l.width>0 && rr.width>0)}
    };print("PASS: 10 layout cases, including negative monitor coordinates");exit(0)
}
if CommandLine.arguments.contains("--whale-caption-test") {
    let d=FocusApp();var blanks=0;var tabsChecked=0;var controlsChecked=0;var logos=0
    let apps=NSWorkspace.shared.runningApplications.filter{$0.bundleIdentifier=="com.naver.Whale"}
    for app in apps {
        for w in readAX(AXUIElementCreateApplication(app.processIdentifier),kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            guard let (strip,tabs,controls)=d.whaleCaptionRegions(w),let frame=rectAX(w) else{continue}
            let group=AXUIElementCreateSystemWide()
            for box in tabs+controls {
                let pt=CGPoint(x:box.midX,y:min(frame.minY+25,box.midY));var h:AXUIElement?
                _=AXUIElementCopyElementAtPosition(group,Float(pt.x),Float(pt.y),&h)
                if let h=h {precondition(!d.isCaption(h,w,pt),"tab/control must not expand")}
                if tabs.contains(box){tabsChecked+=1}else{controlsChecked+=1}
            }
            let logoPoint=CGPoint(x:frame.maxX-40,y:frame.minY+20);var logoHit:AXUIElement?
            _=AXUIElementCopyElementAtPosition(group,Float(logoPoint.x),Float(logoPoint.y),&logoHit)
            if let h=logoHit,d.isCaption(h,w,logoPoint){logos+=1}
            for x in stride(from:strip.minX,to:strip.maxX,by:20) {
                let pt=CGPoint(x:x,y:frame.minY+20);var h:AXUIElement?
                _=AXUIElementCopyElementAtPosition(group,Float(pt.x),Float(pt.y),&h)
                if let h=h,d.isCaption(h,w,pt){blanks+=1}
            }
        }
    }
    precondition(tabsChecked>0 && blanks>0 && logos>0,"real Whale tabs and blank caption must be present")
    print("PASS: Whale blank points=\(blanks), tabs excluded=\(tabsChecked), controls excluded=\(controlsChecked), logos accepted=\(logos)");exit(0)
}
let delegate=FocusApp();let app=NSApplication.shared;app.delegate=delegate;app.run()
