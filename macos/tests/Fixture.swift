// 포커싱 배치·탭 제외·반복 유지 검사를 위한 독립된 두 시험 창.
import AppKit
class Fixture:NSObject,NSApplicationDelegate {
 var windows:[NSWindow]=[];var timer:Timer?
 func applicationDidFinishLaunching(_ n:Notification){
  let screen=NSScreen.main!.visibleFrame
  let width=min(screen.width-80,1200.0);let height=min(screen.height-100,600.0)
  let x=screen.midX-width/2;let y=screen.midY-height/2
  for i in 0..<2 {
   let frame=NSRect(x:x+(i==0 ? 0:width*2/3),y:y,width:i==0 ? width*2/3:width/3,height:height)
   let w=NSWindow(contentRect:.zero,styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
   w.title="포커싱 시험 \(i==0 ? "왼쪽":"오른쪽")";w.setFrame(frame,display:true);w.isReleasedWhenClosed=false;w.minSize=NSSize(width:200,height:180)
   let text=NSTextField(labelWithString:"개인 문서가 없는 배치 시험용 창입니다.");text.frame=NSRect(x:20,y:100,width:350,height:30);w.contentView?.addSubview(text)
   let opaque=NSView(frame:NSRect(x:20,y:140,width:100,height:25));opaque.setAccessibilityElement(true);opaque.setAccessibilityRole(.group);opaque.setAccessibilityLabel("불투명 사용자 탭");w.contentView?.addSubview(opaque)
   let tabs=NSTabView(frame:NSRect(x:20,y:180,width:320,height:120))
   for name in ["시험 탭 1","시험 탭 2"] {let item=NSTabViewItem(identifier:name);item.label=name;tabs.addTabViewItem(item)}
   w.contentView?.addSubview(tabs)
   w.makeKeyAndOrderFront(nil);windows.append(w)
  }
  NSApp.activate(ignoringOtherApps:true)
  timer=Timer.scheduledTimer(withTimeInterval:0.3,repeats:true){[weak self] _ in
   guard let s=self else{return}
   let values=s.windows.map{["x":$0.frame.minX,"y":$0.frame.minY,"width":$0.frame.width,"height":$0.frame.height]}
   if let data=try? JSONSerialization.data(withJSONObject:values){try? data.write(to:URL(fileURLWithPath:"/tmp/young-focusing-fixture.json"),options:.atomic)}
  }
 }
 func applicationShouldTerminateAfterLastWindowClosed(_ app:NSApplication)->Bool{true}
}
let app=NSApplication.shared;let d=Fixture();app.delegate=d;app.run()
