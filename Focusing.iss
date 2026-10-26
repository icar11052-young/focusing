#define AppVersion "0.2.0-beta.1"
[Setup]
AppId=Focusing.Desktop
AppName=Focusing
AppVersion={#AppVersion}
VersionInfoVersion=0.2.0.0
AppPublisher=Focusing
DefaultDirName={localappdata}\Programs\Focusing
DefaultGroupName=Focusing
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=build
OutputBaseFilename=Focusing-{#AppVersion}-windows-x64-setup
SetupIconFile=src\focusing.ico
UninstallDisplayIcon={app}\Focusing.exe
AppMutex=Local\FocusingApp-v1
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no
Uninstallable=yes
UsePreviousTasks=yes

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "startup"; Description: "Windows 로그인 시 Focusing 실행"; Flags: unchecked
Name: "desktopicon"; Description: "바탕 화면 바로가기 만들기"; Flags: unchecked

[Files]
Source: "payload\Focusing.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "payload\PairTools.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "payload\README.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "payload\licenses\*"; DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Focusing"; Filename: "{app}\Focusing.exe"
Name: "{group}\사용 안내"; Filename: "{app}\README.txt"
Name: "{autodesktop}\Focusing"; Filename: "{app}\Focusing.exe"; Tasks: desktopicon
Name: "{userstartup}\Focusing"; Filename: "{app}\Focusing.exe"; Tasks: startup

[Run]
Filename: "{app}\Focusing.exe"; Description: "Focusing 실행"; Flags: nowait postinstall skipifsilent

[InstallDelete]
Type: files; Name: "{userstartup}\Focusing.lnk"; Tasks: not startup
Type: files; Name: "{autodesktop}\Focusing.lnk"; Tasks: not desktopicon

[UninstallDelete]
; Only this product's empty program folder. User settings are intentionally preserved.
Type: dirifempty; Name: "{app}"
