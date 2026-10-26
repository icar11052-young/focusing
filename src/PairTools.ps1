# 창 묶음의 앱 식별 정보를 저장하고 바로가기를 생성하는 도구.
param(
    [ValidateSet('Capture','Shortcut','Launch','Library')] [string]$Mode = 'Launch',
    [string]$PairId,
    [string]$Root = (Join-Path $env:APPDATA 'Focusing\Pairs'),
    [long]$Left = 0, [long]$Right = 0,
    [string]$Desktop = [Environment]::GetFolderPath('Desktop')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FocusingPairNative {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr data);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr data);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,StringBuilder b,int n);
  [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h,int i);
  [DllImport("user32.dll")] static extern IntPtr GetClassLongPtr(IntPtr h,int i);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h,int flags,StringBuilder b,ref int n);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern int GetApplicationUserModelId(IntPtr h,ref uint n,StringBuilder b);
  [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint ms,out IntPtr result);
  public static string[] Identity(IntPtr hwnd) {
    uint pid; GetWindowThreadProcessId(hwnd,out pid);
    var h=OpenProcess(0x1000,false,pid); string exe="",app="";
    if(h!=IntPtr.Zero) try {
      int n=32768; var b=new StringBuilder(n); if(QueryFullProcessImageName(h,0,b,ref n))exe=b.ToString();
      uint size=1024; b=new StringBuilder((int)size); if(GetApplicationUserModelId(h,ref size,b)==0)app=b.ToString();
    } finally { CloseHandle(h); }
    var title=new StringBuilder(2048); GetWindowText(hwnd,title,title.Capacity);
    var cls=new StringBuilder(256); GetClassName(hwnd,cls,cls.Capacity);
    return new[]{exe,app,title.ToString(),cls.ToString(),pid.ToString()};
  }
  public static IntPtr Icon(IntPtr hwnd) {
    IntPtr icon; SendMessageTimeout(hwnd,0x7f,new IntPtr(1),IntPtr.Zero,2,100,out icon);
    if(icon==IntPtr.Zero)icon=GetClassLongPtr(hwnd,-14);
    return icon;
  }
}
'@
function Get-PairFile([string]$Id) {
    if ($Id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid pair identifier.' }
    Join-Path $Root ($Id + '.ini')
}
function Read-PairIni([string]$Path) {
    $data = @{}; $section = ''
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\[([^\]]+)\]$') { $section=$Matches[1]; $data[$section]=@{} }
        elseif ($section -and $line -match '^([^=]+)=(.*)$') { $data[$section][$Matches[1]]=$Matches[2] }
    }
    return $data
}
function Write-PairIni([string]$Path, [hashtable]$Data) {
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($section in $Data.Keys) {
        $lines.Add('['+$section+']')
        foreach($key in $Data[$section].Keys) {
            $value = [string]$Data[$section][$key]
            if ($value -match '[\r\n]') { throw 'Multiline settings are not supported.' }
            $lines.Add($key+'='+$value)
        }
    }
    [IO.File]::WriteAllLines($Path,$lines,[Text.Encoding]::Unicode)
}
function Test-BrowserEndpoint($Endpoint) {
    return [IO.Path]::GetFileName($Endpoint.exe) -match '^(whale|chrome|msedge|firefox)\.exe$'
}
function Get-ProgramName([string]$Exe) {
    # Use application metadata, never the changing page/document window title.
    $base = [IO.Path]::GetFileNameWithoutExtension($Exe)
    $known = @{whale='Whale';chrome='Google Chrome';msedge='Microsoft Edge';firefox='Firefox';codex='Codex'}
    if ($known.ContainsKey($base)) { return $known[$base] }
    try {
        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Exe)
        foreach ($value in @($info.ProductName, $info.FileDescription)) {
            if (![string]::IsNullOrWhiteSpace($value)) { return ($value -replace '[\r\n]', ' ').Trim() }
        }
    } catch {}
    if ($base) { return $base }
    return 'App'
}
function Get-Endpoint([long]$Handle) {
    $id=[FocusingPairNative]::Identity([IntPtr]$Handle)
    if(!$id[0] -and !$id[1]) { throw '앱 실행 정보를 읽을 수 없습니다.' }
    return @{exe=$id[0]; appId=$id[1]; name=(Get-ProgramName $id[0]); title=($id[2] -replace '[\r\n]',' '); class=$id[3]; pid=$id[4]; hwnd=[string]$Handle; url=''}
}
function Get-EndpointBitmap([long]$Handle,[string]$Exe) {
    $icon=$null
    try {
        $h=[FocusingPairNative]::Icon([IntPtr]$Handle)
        if($h -ne [IntPtr]::Zero) { $icon=[Drawing.Icon]::FromHandle($h).Clone() }
        elseif(Test-Path -LiteralPath $Exe) { $icon=[Drawing.Icon]::ExtractAssociatedIcon($Exe) }
        if(!$icon) { $icon=[Drawing.SystemIcons]::Application.Clone() }
        return $icon.ToBitmap()
    } finally { if($icon){$icon.Dispose()} }
}
function Save-CombinedIcon([string]$Path,$A,$B) {
    $canvas=[Drawing.Bitmap]::new(64,64); $g=[Drawing.Graphics]::FromImage($canvas)
    try {
        $g.Clear([Drawing.Color]::FromArgb(255,24,35,42))
        $g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($A,2,4,40,40); $g.DrawImage($B,24,22,38,38)
        $h=$canvas.GetHicon()
        try {
            $icon=[Drawing.Icon]::FromHandle($h)
            $stream=[IO.File]::Create($Path)
            try { $icon.Save($stream) } finally { $stream.Dispose(); $icon.Dispose() }
        } finally { [void][FocusingPairNative]::DestroyIcon($h) }
    } finally { $g.Dispose();$canvas.Dispose() }
}
function Quote-Argument([string]$Value) {
    if($Value -match '["\r\n]') { throw 'Unsupported quote/newline in argument.' }
    return '"'+$Value.TrimEnd('\')+'"'
}
function Test-Endpoint($Endpoint) {
    # Legacy URL fields are intentionally ignored: pairs launch applications.
    if(!$Endpoint.appId -and !(Test-Path -LiteralPath $Endpoint.exe -PathType Leaf)) { throw ('앱을 찾을 수 없습니다: '+$Endpoint.exe) }
    if($Endpoint.appId -and $Endpoint.appId -notmatch '^[A-Za-z0-9._!-]+$') { throw 'Invalid app identifier.' }
}
function Get-Candidates($Endpoint,[long]$Exclude=0) {
    $items=[Collections.Generic.List[object]]::new()
    $callback=[FocusingPairNative+EnumProc]{ param($h,$unused)
        if($h.ToInt64() -eq $Exclude -or ![FocusingPairNative]::IsWindowVisible($h)) { return $true }
        $ex=[FocusingPairNative]::GetWindowLongPtr($h,-20).ToInt64()
        if(($ex -band 0x80) -or ($ex -band 0x8000000)) { return $true }
        $id=[FocusingPairNative]::Identity($h)
        $match=($Endpoint.appId -and $id[1] -eq $Endpoint.appId) -or ($Endpoint.exe -and $id[0] -eq $Endpoint.exe)
        if($match -and $id[2] -and $id[3] -eq $Endpoint.class) { $items.Add(@{hwnd=$h.ToInt64();pid=$id[4];title=$id[2]}) }
        return $true
    }.GetNewClosure()
    [void][FocusingPairNative]::EnumWindows($callback,[IntPtr]::Zero)
    return $items.ToArray()
}
function Select-Existing($Endpoint,$Candidates) {
    $cached=@($Candidates|Where-Object { $_.hwnd -eq [long]$Endpoint.hwnd -and $_.pid -eq $Endpoint.pid })
    if($cached.Count -eq 1) { return $cached[0] }
    $exact=@($Candidates|Where-Object {$_.title -eq $Endpoint.title})
    if($exact.Count -eq 1) { return $exact[0] }
    if(@($Candidates).Count -eq 1) { return @($Candidates)[0] }
    return $null
}
function Start-Endpoint($Endpoint) {
    Test-Endpoint $Endpoint
    if(Test-BrowserEndpoint $Endpoint) {
        # No URL or startup switches; the browser owns home/session restoration.
        Start-Process -FilePath $Endpoint.exe -WindowStyle Normal | Out-Null
    } elseif($Endpoint.appId) {
        Start-Process -FilePath explorer.exe -ArgumentList ('shell:AppsFolder\'+$Endpoint.appId) | Out-Null
    } else { Start-Process -FilePath $Endpoint.exe -WindowStyle Normal | Out-Null }
}
function Invoke-PairLaunch([string]$Id) {
    $file=Get-PairFile $Id; $pair=Read-PairIni $file
    $ends=@($pair.left,$pair.right); $chosen=@($null,$null);$before=@(@(),@())
    for($i=0;$i -lt 2;$i++) {
        Test-Endpoint $ends[$i]
        $before[$i]=@(Get-Candidates $ends[$i])
        $available=@($before[$i]|Where-Object { $i -eq 0 -or !$chosen[0] -or $_.hwnd -ne $chosen[0].hwnd })
        $chosen[$i]=Select-Existing $ends[$i] $available
        if(!$chosen[$i] -and $available.Count -gt 1) { throw '같은 앱 창이 여러 개입니다. 사용할 창을 남겨 두고 다시 실행해 주세요.' }
    }
    for($i=0;$i -lt 2;$i++) { if(!$chosen[$i]) { Start-Endpoint $ends[$i] } }
    $deadline=[DateTime]::UtcNow.AddSeconds(35)
    do {
        for($i=0;$i -lt 2;$i++) {
            if($chosen[$i]) { continue }
            $exclude=if($chosen[1-$i]){$chosen[1-$i].hwnd}else{0}
            $found=@(Get-Candidates $ends[$i] $exclude)
            $fresh=@($found|Where-Object { $_.hwnd -notin @($before[$i]|ForEach-Object {$_.hwnd}) })
            # Session restore can reopen several windows. Pair the topmost new
            # browser window, leaving the other restored windows untouched.
            if($fresh.Count -eq 1 -or ($fresh.Count -gt 1 -and (Test-BrowserEndpoint $ends[$i]))) { $chosen[$i]=$fresh[0] }
            elseif($found.Count -eq 1) { $chosen[$i]=$found[0] }
        }
        if($chosen[0] -and $chosen[1]) { break }
        Start-Sleep -Milliseconds 250
    } while([DateTime]::UtcNow -lt $deadline)
    if(!$chosen[0] -or !$chosen[1] -or $chosen[0].hwnd -eq $chosen[1].hwnd) { throw '서로 다른 앱 창 두 개를 찾지 못했습니다. 앱이 열린 뒤 다시 실행해 주세요.' }
    $hostInfo=(Read-PairIni (Join-Path $Root 'host.ini')).host
    $identity=[FocusingPairNative]::Identity([IntPtr][long]$hostInfo.hwnd)
    if(![FocusingPairNative]::IsWindow([IntPtr][long]$hostInfo.hwnd) -or $identity[4] -ne $hostInfo.pid) {
        if($hostInfo.script) {
            Start-Process -FilePath $hostInfo.exe -ArgumentList (Quote-Argument $hostInfo.script) -WindowStyle Hidden | Out-Null
        } else {
            Start-Process -FilePath $hostInfo.exe -WindowStyle Hidden | Out-Null
        }
    }
    $nonce=[Guid]::NewGuid().ToString('N')
    $request=Join-Path $Root ($nonce+'.request')
    $temp=$request+'.tmp'
    Write-PairIni $temp @{request=@{id=$Id;left=$chosen[0].hwnd;leftPid=$chosen[0].pid;right=$chosen[1].hwnd;rightPid=$chosen[1].pid}}
    Move-Item -LiteralPath $temp -Destination $request
    $deadline=[DateTime]::UtcNow.AddSeconds(20)
    while(!(Test-Path -LiteralPath ($request+'.done')) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if(!(Test-Path -LiteralPath ($request+'.done'))) { Remove-Item -LiteralPath $request -ErrorAction SilentlyContinue; throw '포커싱 앱이 응답하지 않습니다. 포커싱을 실행한 뒤 다시 시도해 주세요.' }
    $result=[IO.File]::ReadAllText($request+'.done')
    Remove-Item -LiteralPath ($request+'.done')
    if($result -ne 'OK') { throw $result }
}
if($Mode -eq 'Library') { return }
try {
    $file=Get-PairFile $PairId
    if($Mode -eq 'Capture') {
        $data=@{left=(Get-Endpoint $Left);right=(Get-Endpoint $Right)}
        Write-PairIni $file $data
        $a=Get-EndpointBitmap $Left $data.left.exe; $b=Get-EndpointBitmap $Right $data.right.exe
        try { Save-CombinedIcon (Join-Path $Root ($PairId+'.ico')) $a $b } finally { $a.Dispose();$b.Dispose() }
    } elseif($Mode -eq 'Shortcut') {
        $pair=Read-PairIni $file;Test-Endpoint $pair.left;Test-Endpoint $pair.right
        $name=$pair.pair.name -replace '[<>:"/\\|?*\x00-\x1f]','_'
        $name=$name.Trim().TrimEnd('.')
        if(!$name){$name='Focusing pair'}
        $shortcut=Join-Path $Desktop ($name+'.lnk');$n=2
        while(Test-Path -LiteralPath $shortcut){$shortcut=Join-Path $Desktop ($name+' ('+$n+').lnk');$n++}
        $shell=New-Object -ComObject WScript.Shell
        $link=$shell.CreateShortcut($shortcut)
        $link.TargetPath=Join-Path $PSHOME 'powershell.exe'
        $link.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File '+(Quote-Argument $PSCommandPath)+' -Mode Launch -PairId '+$PairId+' -Root '+(Quote-Argument $Root)
        $link.WorkingDirectory=$PSScriptRoot;$link.WindowStyle=7
        $link.IconLocation=(Join-Path $Root ($PairId+'.ico'))+',0'
        $link.Description='Focusing: '+$name;$link.Save()
        [IO.File]::WriteAllText((Join-Path $Root ($PairId+'.created')),$shortcut)
    } else { Invoke-PairLaunch $PairId }
} catch {
    if($Mode -eq 'Launch') { Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Focusing 묶음 바로가기') }
    else { [Console]::Error.WriteLine($_.Exception.Message) }
    exit 1
}
