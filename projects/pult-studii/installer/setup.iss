; Inno Setup 6. Версия: iscc /DMyAppVersion=1.0.0 installer\setup.iss
; Запускать из папки проекта (projects/pult-studii). Сначала: flutter build windows --release
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

[Setup]
AppId={{3F7A9C52-8D14-4B6E-9A31-5C2E7B0D4F68}
AppName=Рубка
AppVersion={#MyAppVersion}
AppPublisher=Рубка
DefaultDirName={localappdata}\Programs\Rubka
DefaultGroupName=Рубка
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=Rubka-setup
UninstallDisplayName=Рубка
UninstallDisplayIcon={app}\pult_studii.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Рубка"; Filename: "{app}\pult_studii.exe"
Name: "{userdesktop}\Рубка"; Filename: "{app}\pult_studii.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pult_studii.exe"; Description: "Запустить Рубку"; Flags: nowait postinstall skipifsilent
