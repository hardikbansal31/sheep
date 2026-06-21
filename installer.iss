#define MyAppName "Sheep"
#define MyAppExeName "sheep.exe"
#define MyAppExePath "build\windows\x64\runner\Release\" + MyAppExeName
; Dynamically extract the version from the compiled Flutter executable
#define MyAppVersion GetFileVersion(MyAppExePath)

[Setup]
; Application Information
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Hardik Bansal
AppPublisherURL=https://github.com/hardikbansal31/sheep
AppSupportURL=https://github.com/hardikbansal31/sheep/issues
AppUpdatesURL=https://github.com/hardikbansal31/sheep/releases

; Default installation folder (per-user installation)
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}

; Output settings
OutputDir=build\windows\installer
OutputBaseFilename={#MyAppName}_Installer_{#MyAppVersion}
Compression=lzma2
SolidCompression=yes

; Requesting lowest privileges so it can be installed per-user without UAC prompts
PrivilegesRequired=lowest

; Installer Icon (Standard Flutter Windows icon path)
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\sheep.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Sheep"; Filename: "{app}\sheep.exe"
Name: "{group}\{cm:UninstallProgram,Sheep}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Sheep"; Filename: "{app}\sheep.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sheep.exe"; Description: "{cm:LaunchProgram,Sheep}"; Flags: nowait postinstall skipifsilent
