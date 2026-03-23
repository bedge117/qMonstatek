; qMonstatek Installer — Inno Setup Script
; Builds a Windows installer from the deploy/ directory.
;
; Requirements:
;   - Inno Setup 6.x (https://jrsoftware.org/isinfo.php)
;   - All runtime files present in ..\deploy\
;
; Build:
;   From Inno Setup IDE: File → Open → this file → Compile
;   Or CLI: iscc.exe qmonstatek.iss

#define MyAppName "qMonstatek"
#define MyAppVersion "2.1.2"
#define MyAppPublisher "MonstaTek"
#define MyAppExeName "qmonstatek.exe"
#define MyAppURL "https://github.com/bedge117/qMonstatek"
#define DeployDir "..\deploy"

[Setup]
AppId={{B8E7D3A1-4F2C-4E8A-9D6B-1A3C5F7E9B2D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\installer_output
OutputBaseFilename=qMonstatek_v{#MyAppVersion}_setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
; Upgrade in place — same AppId means Inno detects previous install
UsePreviousAppDir=yes
; Minimum Windows 10
MinVersion=10.0
UninstallDisplayName={#MyAppName}
SetupIconFile=qmonstatek.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startmenuicon"; Description: "Create a Start Menu shortcut"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Main executable
Source: "{#DeployDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; Qt6 DLLs
Source: "{#DeployDir}\Qt6Core.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6Gui.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6Network.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6OpenGL.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6Qml.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QmlLocalStorage.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QmlModels.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QmlWorkerScript.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QmlXmlListModel.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6Quick.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickControls2.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickControls2Impl.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickDialogs2.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickDialogs2QuickImpl.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickDialogs2Utils.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickLayouts.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickParticles.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickShapes.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6QuickTemplates2.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6SerialPort.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6Sql.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6Svg.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\Qt6Widgets.dll"; DestDir: "{app}"; Flags: ignoreversion

; MinGW runtime
Source: "{#DeployDir}\libgcc_s_seh-1.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\libstdc++-6.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\libwinpthread-1.dll"; DestDir: "{app}"; Flags: ignoreversion

; DirectX / OpenGL
Source: "{#DeployDir}\D3Dcompiler_47.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#DeployDir}\opengl32sw.dll"; DestDir: "{app}"; Flags: ignoreversion

; Qt plugins (recurse subdirectories)
Source: "{#DeployDir}\platforms\*"; DestDir: "{app}\platforms"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}\styles\*"; DestDir: "{app}\styles"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}\imageformats\*"; DestDir: "{app}\imageformats"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}\iconengines\*"; DestDir: "{app}\iconengines"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}\tls\*"; DestDir: "{app}\tls"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}\sqldrivers\*"; DestDir: "{app}\sqldrivers"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}\translations\*"; DestDir: "{app}\translations"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}\qmltooling\*"; DestDir: "{app}\qmltooling"; Flags: ignoreversion recursesubdirs createallsubdirs

; QML modules
Source: "{#DeployDir}\QtQml\*"; DestDir: "{app}\QtQml"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#DeployDir}\QtQuick\*"; DestDir: "{app}\QtQuick"; Flags: ignoreversion recursesubdirs createallsubdirs

; Firmware .bin files are NOT bundled — they are downloaded from GitHub at runtime

; STM32 Programmer support files (DFU flash tool + CubeProgrammer API)
Source: "{#DeployDir}\stm32prog\*"; DestDir: "{app}\stm32prog"; Flags: ignoreversion recursesubdirs createallsubdirs

; Database files
Source: "{#DeployDir}\Data_Base\*"; DestDir: "{app}\Data_Base"; Flags: ignoreversion recursesubdirs createallsubdirs

; NOTE: qmonstatek.log is NOT included — it's generated at runtime

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clean up log file on uninstall
Type: files; Name: "{app}\qmonstatek.log"

[Code]
// Kill running instance before install/upgrade
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  // Attempt to kill any running instance silently
  Exec('taskkill.exe', '/f /im {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
