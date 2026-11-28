; Inno Setup 6. Версия: iscc /DMyAppVersion=1.0.0 installer\setup.iss
; Запускать из папки проекта (projects/pult-studii). Сначала: flutter build windows --release
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{3F7A9C52-8D14-4B6E-9A31-5C2E7B0D4F68}
AppName=AI Studio
AppVersion={#MyAppVersion}
AppPublisher=AI Studio
DefaultDirName={localappdata}\Programs\AI Studio
DefaultGroupName=AI Studio
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=AI-Studio-setup
SetupIconFile=..\assets\icon\app_icon.ico
UninstallDisplayName=AI Studio
UninstallDisplayIcon={app}\pult_studii.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; AppUserModelID = имя, которое программа передаёт в local_notifier (notifyTitle): тосты привязаны к этому ярлыку
Name: "{userprograms}\AI Studio"; Filename: "{app}\pult_studii.exe"; AppUserModelID: "AI Studio"
Name: "{userdesktop}\AI Studio"; Filename: "{app}\pult_studii.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pult_studii.exe"; Description: "Запустить AI Studio"; Flags: nowait postinstall skipifsilent
; тихая установка (автообновление): запустить программу без вопросов
Filename: "{app}\pult_studii.exe"; Flags: nowait; Check: WizardSilent

[InstallDelete]
; ярлыки старого названия «Рубка» (после обновления поверх старой версии)
Type: files; Name: "{userprograms}\Рубка.lnk"
Type: files; Name: "{userdesktop}\Рубка.lnk"
