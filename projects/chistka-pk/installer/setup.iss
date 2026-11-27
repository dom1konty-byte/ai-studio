; Inno Setup 6. Версия: iscc /DMyAppVersion=1.3.0 installer\setup.iss
#ifndef MyAppVersion
  #define MyAppVersion "1.3.0"
#endif

[Setup]
AppId={{6B1E2C0A-6F0D-4C55-9A57-0F9D9A0C1D15}
AppName=ЧистоДиск
AppVersion={#MyAppVersion}
AppPublisher=ЧистоДиск
DefaultDirName={autopf}\ChistoDisk
DefaultGroupName=ЧистоДиск
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=ChistoDisk-setup
SetupIconFile=..\assets\icon\app_icon.ico
UninstallDisplayIcon={app}\chistka_pk.exe
; Закрыть запущенную программу (в трее) при установке/удалении
AppMutex=ChistoDiskSingleInstance
CloseApplications=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\ЧистоДиск"; Filename: "{app}\chistka_pk.exe"
Name: "{userdesktop}\ЧистоДиск"; Filename: "{app}\chistka_pk.exe"; Tasks: desktopicon

[UninstallRun]
; Сначала мягкое закрытие, затем принудительное (запасной вариант)
Filename: "{sys}\taskkill.exe"; Parameters: "/IM chistka_pk.exe"; Flags: runhidden; RunOnceId: "CloseChistoDisk"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM chistka_pk.exe"; Flags: runhidden; RunOnceId: "KillChistoDisk"

[Run]
Filename: "{app}\chistka_pk.exe"; Description: "Запустить ЧистоДиск"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // Только своё значение автозапуска (ValueType у [Registry]-строки нет, поэтому здесь); остальное в Run не трогаем.
  if CurUninstallStep = usUninstall then
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'ChistoDisk');
end;
