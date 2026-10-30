; Builds LifePilot-Setup.exe from the Flutter Windows release build.
; Usage (from the project root, after `flutter build windows --release`):
;   ISCC /DAppVersion=1.0.2 windows\installer\LifePilot.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{B6E2F1A4-6C1D-4E8B-9A57-2D3C4F5E6A71}
AppName=LifePilot
AppVersion={#AppVersion}
AppPublisher=IB1203
AppPublisherURL=https://github.com/IB1203/LifePilot
AppSupportURL=https://github.com/IB1203/LifePilot/issues
DefaultDirName={autopf}\LifePilot
DefaultGroupName=LifePilot
DisableProgramGroupPage=yes
; Installs for the current user without admin rights unless the user
; chooses all users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\build\dist
OutputBaseFilename=LifePilot-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\LifePilot.exe
UninstallDisplayName=LifePilot
LicenseFile=..\..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
; The AppUserModelID lets Windows show LifePilot's reminder notifications.
Name: "{group}\LifePilot"; Filename: "{app}\LifePilot.exe"; AppUserModelID: "IB1203.LifePilot"
Name: "{autodesktop}\LifePilot"; Filename: "{app}\LifePilot.exe"; Tasks: desktopicon; AppUserModelID: "IB1203.LifePilot"

[Run]
Filename: "{app}\LifePilot.exe"; Description: "Open LifePilot"; Flags: nowait postinstall skipifsilent

; Records stay in %APPDATA% after uninstalling, so reinstalling keeps them.
; Delete that folder by hand to remove all data.
