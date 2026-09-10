; RiftPDF — Windows installer.
;
; Built by packaging/build_installer.py, which compiles this with ISCC.exe
; after qt/build_windows.py has produced dist\RiftPDF.
;
; The installer is not code signed, so Windows SmartScreen will warn on first
; download. That is expected and documented in docs/INSTALL.md rather than
; paid away with a certificate.

#define AppName        "RiftPDF"
#define AppExeName     "RiftPDF.exe"
#define AppPublisher   "RiftPDF"
#define AppURL         "https://github.com/rifatadnan1322/RiftPDF"
#ifndef AppVersion
  #define AppVersion   "1.1.0"
#endif
#ifndef SourceDir
  #define SourceDir    "..\dist\RiftPDF"
#endif

[Setup]
; Never change AppId: it is how Windows recognises an existing install and
; offers to upgrade it in place rather than piling up copies.
AppId={{8B45E02B-3D76-4688-A1A8-6C3E5357C260}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
VersionInfoVersion={#AppVersion}

; Install per-user by default so no administrator prompt is needed, but let
; anyone who wants a machine-wide install choose it. {autopf} follows that
; choice, landing in Program Files or in the user's own Programs folder.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
AllowNoIcons=yes

; PySide6 and the bundled engine are 64-bit only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

OutputDir=..\dist
OutputBaseFilename={#AppName}-{#AppVersion}-Setup
SetupIconFile=..\Resources\AppIcon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName} {#AppVersion}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; Shown only once a licence exists; the project has not chosen one yet.
#if FileExists(AddBackslash(SourcePath) + "..\LICENSE")
  LicenseFile=..\LICENSE
#endif
DisableWelcomePage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; \
  GroupDescription: "Shortcuts:"; Flags: unchecked
; Deliberately unchecked. Silently taking over PDF files is the kind of thing
; that makes people distrust an installer.
Name: "associatepdf"; Description: "Add {#AppName} to the ""Open with"" list for PDF files"; \
  GroupDescription: "File types:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docs\INSTALL.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; Register a document type and offer it under "Open with". Windows 10 and 11
; do not allow an installer to seize the default handler for a file type --
; only the person can, in Settings -- so this adds the choice without pretending
; to make it for them. {autosoftware} keeps per-user installs out of HKLM.
; HKA is Inno's "auto" root: HKCU for a per-user install, HKLM for a
; machine-wide one, matching whichever the person chose on the first page.
Root: HKA; Subkey: "Software\Classes\RiftPDF.Document"; \
  ValueType: string; ValueName: ""; ValueData: "PDF Document"; \
  Flags: uninsdeletekey; Tasks: associatepdf
Root: HKA; Subkey: "Software\Classes\RiftPDF.Document\DefaultIcon"; \
  ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName},0"; \
  Flags: uninsdeletekey; Tasks: associatepdf
Root: HKA; Subkey: "Software\Classes\RiftPDF.Document\shell\open\command"; \
  ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""; \
  Flags: uninsdeletekey; Tasks: associatepdf
Root: HKA; Subkey: "Software\Classes\.pdf\OpenWithProgids"; \
  ValueType: string; ValueName: "RiftPDF.Document"; ValueData: ""; \
  Flags: uninsdeletevalue; Tasks: associatepdf
; Always registered, so RiftPDF appears under "Open with > Choose another app"
; even when the association task was left unticked. The parent key carries
; uninsdeletekey: putting that flag on the deepest key only would remove the
; command and leave the empty Applications\RiftPDF.exe\shell\open shell behind.
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExeName}"; \
  Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExeName}\shell\open\command"; \
  ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Open {#AppName} now"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
; PyInstaller writes nothing outside {app}, but a stale _internal left behind
; would make a later reinstall look corrupted.
Type: filesandordirs; Name: "{app}\_internal"
