; krypton-installer.iss — Inno Setup script for Krypton 2.4
;
; Builds a Windows installer that:
;   - installs the Krypton toolchain to C:\krypton (overwrites prior install)
;   - registers C:\krypton on the system PATH (so `kcc` works in any shell)
;   - associates .k files with kcc.exe (open-with menu)
;   - leaves a Start Menu group with a launcher and an uninstaller
;
; Requires: Inno Setup Compiler 6.x (free, https://jrsoftware.org/isinfo.php)
;
; Build:
;   1. Open this file in Inno Setup Compiler
;   2. Build > Compile
;   3. Output lands at installer\Output\krypton-{#KryptonVersion}-setup.exe
;
; Or from PowerShell:
;   & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\krypton-installer.iss

#define KryptonName     "Krypton"
#define KryptonVersion  "2.4.5"
#define KryptonPublisher "KryptonBytes"
#define KryptonURL      "https://krypton-lang.org/"
#define KryptonExe      "kcc.exe"
#define KryptonRoot     "C:\Users\brian\Documents\GitHub\krypton"

[Setup]
; AppId stays constant across versions so each install upgrades the previous
; one in place (matches the v1.4.0 installer's GUID).
AppId={{334887EF-810D-4AED-87DB-8ABF41559AA0}
AppName={#KryptonName}
AppVersion={#KryptonVersion}
AppVerName={#KryptonName} {#KryptonVersion}
AppPublisher={#KryptonPublisher}
AppPublisherURL={#KryptonURL}
AppSupportURL={#KryptonURL}
AppUpdatesURL={#KryptonURL}

; Force install to C:\krypton — no Program Files, no user choice.
DefaultDirName=C:\krypton
DisableDirPage=yes

; System-wide install (writes to C:\, modifies system PATH) → admin required.
PrivilegesRequired=admin

; 64-bit only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; PATH updates require this so the WM_SETTINGCHANGE broadcast happens.
ChangesEnvironment=yes
ChangesAssociations=yes

; Start Menu group + uninstaller setup.
DefaultGroupName={#KryptonName}
AllowNoIcons=yes
SetupIconFile={#KryptonRoot}\assets\krypton.ico
UninstallDisplayIcon={app}\{#KryptonExe}
UninstallDisplayName={#KryptonName} {#KryptonVersion}

; Output file naming.
OutputBaseFilename=krypton-{#KryptonVersion}-setup
OutputDir=Output
SolidCompression=yes
Compression=lzma2/ultra
WizardStyle=modern

; Replace running kcc.exe if it's open during install.
CloseApplications=yes
RestartApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "addtopath";    Description: "Add C:\krypton to the system PATH";        GroupDescription: "Environment:";       Flags: checkedonce
Name: "associatek";   Description: "Associate .k and .ks files with kcc.exe";  GroupDescription: "File associations:"; Flags: unchecked
Name: "desktopicon";  Description: "{cm:CreateDesktopIcon}";                   GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; --- Toolchain executables (driver/backend split) ---
; kcc.exe is the Krypton-native driver (compiled from kcc.ks). It dispatches
; to kcc-bin.exe (the compile.k-built backend) for the actual compile work.
; Flags: ignoreversion forces the installer to overwrite on upgrade (Inno
; Setup's default skips replace when target file version >= source, which
; fails for these since they don't carry a Win32 version resource).
Source: "{#KryptonRoot}\kcc.exe";                                         DestDir: "{app}";                          Flags: ignoreversion
Source: "{#KryptonRoot}\kcc-bin.exe";                                     DestDir: "{app}";                          Flags: ignoreversion

; --- Runtime DLLs ---
; krypton_rt.dll ships alongside kcc.exe in {app} so EXEs the user builds
; resolve it via their PATH lookup (C:\krypton is on PATH). A second copy
; under {app}\runtime keeps the layout matching the dev tree.
; krypton_rt_legacy.dll is load-bearing during bootstrap rebuilds of rt.dll
; itself (avoids circular self-import) — copy is small and harmless to bundle.
Source: "{#KryptonRoot}\runtime\krypton_rt.dll";                          DestDir: "{app}";                          Flags: ignoreversion
Source: "{#KryptonRoot}\runtime\krypton_rt.dll";                          DestDir: "{app}\runtime";                  Flags: ignoreversion
Source: "{#KryptonRoot}\runtime\krypton_rt_legacy.dll";                   DestDir: "{app}\runtime";                  Flags: ignoreversion
Source: "{#KryptonRoot}\runtime\krypton_rt.k";                            DestDir: "{app}\runtime";                  Flags: ignoreversion

; --- Compiler host binaries ---
; x64_host.exe and optimize_host.exe live under compiler/windows_x86 to
; match the driver's lookup. Mirrors under bin/ are the canonical names the
; install copy of kcc.exe consults (per project_kryofetch_2_0_port memory).
Source: "{#KryptonRoot}\compiler\windows_x86\x64_host.exe";               DestDir: "{app}\compiler\windows_x86";     Flags: ignoreversion
Source: "{#KryptonRoot}\compiler\windows_x86\optimize_host.exe";          DestDir: "{app}\compiler\windows_x86";     Flags: ignoreversion
Source: "{#KryptonRoot}\compiler\windows_x86\x64_host.exe";               DestDir: "{app}\bin"; DestName: "x64_host_new.exe";       Flags: ignoreversion
Source: "{#KryptonRoot}\compiler\windows_x86\optimize_host.exe";          DestDir: "{app}\bin"; DestName: "optimize_host_new.exe";  Flags: ignoreversion
Source: "{#KryptonRoot}\compiler\windows_x86\optimize_host.exe";          DestDir: "{app}\bin"; DestName: "optimize_host.exe";      Flags: ignoreversion

; --- kr.exe (KryptScript runner — the `.bat` equivalent for .ks) ---
; Tiny native PE that compiles a .ks/.k script to %TEMP%, runs it
; inheriting stdio, propagates the exit code, then cleans up. Pairs
; with the .ks file association below: double-click on a .ks file or
; `myscript.ks foo bar` from any shell reaches kr.exe.
;
; Rebuild before packaging:
;   kcc -o tools\kr\kr.exe tools\kr\run.k
Source: "{#KryptonRoot}\tools\kr\kr.exe";                                 DestDir: "{app}";                          Flags: ignoreversion
Source: "{#KryptonRoot}\tools\kr\run.k";                                  DestDir: "{app}\tools\kr";                 Flags: ignoreversion

; --- Web framework (khtk build tool) ---
Source: "{#KryptonRoot}\web\khtk";                                        DestDir: "{app}";                          Flags: ignoreversion
Source: "{#KryptonRoot}\web\khtk.bat";                                    DestDir: "{app}";                          Flags: ignoreversion

; --- Web framework CLI (kweb: init / build / serve / deploy) ---
; kweb.exe is a build artifact — rebuild before packaging a release:
;   kcc web\kweb.htk -o web\kweb.exe
Source: "{#KryptonRoot}\web\kweb.exe";                                    DestDir: "{app}";                          Flags: ignoreversion
Source: "{#KryptonRoot}\web\kweb_gui.exe";                                DestDir: "{app}";                          Flags: ignoreversion skipifsourcedoesntexist
Source: "{#KryptonRoot}\web\kweb";                                        DestDir: "{app}";                          Flags: ignoreversion
Source: "{#KryptonRoot}\web\kweb_gui.ks";                                DestDir: "{app}\web";                      Flags: ignoreversion
Source: "{#KryptonRoot}\web\kweb_gui_win.ks";                            DestDir: "{app}\web";                      Flags: ignoreversion
Source: "{#KryptonRoot}\web\kweb.htk";                                   DestDir: "{app}\web";                      Flags: ignoreversion
Source: "{#KryptonRoot}\web\README.md";                                  DestDir: "{app}\web";                      Flags: ignoreversion

; --- WASM backend (current 2.3) ---
; First-class Krypton-to-WebAssembly emitter. compiler/wasm32/wasm_self.exe
; consumes a .kir IR and writes a .wasm. scripts/run_wasm.js is the V8 host
; that loads + executes the emitted module; pair with `node`. RUN.sh is the
; lessons scorecard.
Source: "{#KryptonRoot}\compiler\wasm32\wasm_self.exe";                   DestDir: "{app}\compiler\wasm32";          Flags: ignoreversion
Source: "{#KryptonRoot}\compiler\wasm32\wasm_self.k";                     DestDir: "{app}\compiler\wasm32";          Flags: ignoreversion
Source: "{#KryptonRoot}\scripts\run_wasm.js";                             DestDir: "{app}\scripts";                  Flags: ignoreversion
Source: "{#KryptonRoot}\scripts\run_wasm.sh";                             DestDir: "{app}\scripts";                  Flags: ignoreversion
Source: "{#KryptonRoot}\docs\wasm_backend_design.md";                     DestDir: "{app}\docs";                     Flags: ignoreversion
Source: "{#KryptonRoot}\docs\claude\WASM_HOST_ABI.md";                    DestDir: "{app}\docs";                     Flags: ignoreversion skipifsourcedoesntexist

; --- Krypton standard library (k: prefix imports) ---
Source: "{#KryptonRoot}\stdlib\*.k";                                      DestDir: "{app}\stdlib";                   Flags: ignoreversion recursesubdirs

; --- Header bindings (head: prefix imports — Win32 + POSIX + C stdlib) ---
Source: "{#KryptonRoot}\headers\*.krh";                                   DestDir: "{app}\headers";                  Flags: ignoreversion


; --- Examples + language server sources (mirrors current macOS payload) ---
Source: "{#KryptonRoot}\examples\*";                                      DestDir: "{app}\examples";                 Flags: ignoreversion recursesubdirs
Source: "{#KryptonRoot}\lsp\*";                                           DestDir: "{app}\lsp";                      Flags: ignoreversion recursesubdirs

; --- Bootstrap seeds (source checkout parity + repair/debug support) ---
Source: "{#KryptonRoot}\bootstrap\*";                                     DestDir: "{app}\bootstrap";                Flags: ignoreversion recursesubdirs

; --- Documentation ---
Source: "{#KryptonRoot}\README.md";                                       DestDir: "{app}";                          Flags: ignoreversion
Source: "{#KryptonRoot}\LICENSE";                                         DestDir: "{app}";                          Flags: ignoreversion
Source: "{#KryptonRoot}\CHANGELOG.md";                                    DestDir: "{app}";                          Flags: ignoreversion

[Dirs]
; Pre-create dirs so PATH-touching code below can rely on them.
Name: "{app}\compiler\windows_x86"
Name: "{app}\compiler\wasm32"
Name: "{app}\runtime"
Name: "{app}\headers"
Name: "{app}\stdlib"
Name: "{app}\bin"
Name: "{app}\scripts"
Name: "{app}\docs"
Name: "{app}\examples"
Name: "{app}\lsp"
Name: "{app}\bootstrap"
Name: "{app}\web"

[Registry]
; --- Add C:\krypton to system PATH (only if it isn't already there). ---
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; \
    Tasks: addtopath; Check: NeedsAddPath('{app}')
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "KRYPTON_ROOT"; ValueData: "{app}"; \
    Flags: uninsdeletevalue

; --- .k file association (optional task) ---
Root: HKCR; Subkey: ".k";                            ValueType: string; ValueName: ""; ValueData: "Krypton.Source"; Flags: uninsdeletevalue; Tasks: associatek
Root: HKCR; Subkey: "Krypton.Source";                ValueType: string; ValueName: ""; ValueData: "Krypton Source File"; Flags: uninsdeletekey; Tasks: associatek
Root: HKCR; Subkey: "Krypton.Source\DefaultIcon";    ValueType: string; ValueName: ""; ValueData: "{app}\{#KryptonExe},0"; Tasks: associatek
Root: HKCR; Subkey: "Krypton.Source\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#KryptonExe}"" ""%1"""; Tasks: associatek

; --- .ks (KryptScript) file association (2.2) ---
; KryptScript is the run-as-script extension. Unlike .k (which opens in
; the compiler), double-click on a .ks file (and `myscript.ks` from any
; shell) runs the script via kr.exe — the Windows-native equivalent of
; the POSIX `kr` bash wrapper. Args after the script are forwarded.
Root: HKCR; Subkey: ".ks";                           ValueType: string; ValueName: ""; ValueData: "KryptonScript.Run"; Flags: uninsdeletevalue; Tasks: associatek
Root: HKCR; Subkey: "KryptonScript.Run";             ValueType: string; ValueName: ""; ValueData: "KryptScript"; Flags: uninsdeletekey; Tasks: associatek
Root: HKCR; Subkey: "KryptonScript.Run\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#KryptonExe},0"; Tasks: associatek
Root: HKCR; Subkey: "KryptonScript.Run\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\kr.exe"" ""%1"" %*"; Tasks: associatek

[Icons]
Name: "{group}\{#KryptonName} {#KryptonVersion}";  Filename: "{app}\{#KryptonExe}"; WorkingDir: "{app}"
Name: "{group}\Krypton Documentation";             Filename: "{app}\README.md"
Name: "{group}\{cm:UninstallProgram,{#KryptonName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#KryptonName}";              Filename: "{app}\{#KryptonExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; Smoke-test the install at the end (silent — fails if kcc.exe isn't a valid PE).
Filename: "{app}\{#KryptonExe}"; Parameters: "--version"; \
    Description: "Verify install (kcc --version)"; Flags: postinstall runascurrentuser nowait skipifsilent

[UninstallDelete]
; Clean up anything we might have generated under the install root.
Type: filesandordirs; Name: "{app}\__pycache__"
Type: dirifempty;    Name: "{app}\compiler\windows_x86"
Type: dirifempty;    Name: "{app}\compiler"
Type: dirifempty;    Name: "{app}\runtime"
Type: dirifempty;    Name: "{app}\headers"
Type: dirifempty;    Name: "{app}\stdlib"
Type: dirifempty;    Name: "{app}\bin"
Type: dirifempty;    Name: "{app}\examples"
Type: dirifempty;    Name: "{app}\lsp"
Type: dirifempty;    Name: "{app}\bootstrap"
Type: dirifempty;    Name: "{app}\web"
Type: dirifempty;    Name: "{app}"

[Code]
//
// PATH-manipulation helpers.
//
// Inno Setup doesn't ship a built-in "append-to-PATH-only-if-missing" so we
// roll our own. We modify HKLM\Environment\Path (system-wide) since the
// installer requires admin anyway. WM_SETTINGCHANGE is broadcast automatically
// because Setup has ChangesEnvironment=yes.
//

const
  EnvKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

function NeedsAddPath(Param: string): boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvKey, 'Path', OrigPath) then
  begin
    Result := True;
    exit;
  end;
  // Look for the directory bracketed by ';' on both sides so a partial-name
  // match can't fool us (e.g. "C:\krypton" inside "C:\kryptonbytes").
  Result := Pos(';' + UpperCase(Param) + ';', ';' + UpperCase(OrigPath) + ';') = 0;
end;

procedure RemoveFromPath(Param: string);
var
  OrigPath, NewPath, Lower, ParamLower: string;
  P: Integer;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvKey, 'Path', OrigPath) then exit;
  Lower := ';' + LowerCase(OrigPath) + ';';
  ParamLower := ';' + LowerCase(Param) + ';';
  P := Pos(ParamLower, Lower);
  if P = 0 then exit;
  // Remove "(;){Param}" from the original (case-insensitive search, original case kept elsewhere).
  NewPath := Copy(OrigPath, 1, P - 1);
  if (Length(NewPath) > 0) and (NewPath[Length(NewPath)] = ';') then
    NewPath := Copy(NewPath, 1, Length(NewPath) - 1);
  if Length(OrigPath) > P + Length(ParamLower) - 2 then
    NewPath := NewPath + ';' + Copy(OrigPath, P + Length(ParamLower) - 1, MaxInt);
  RegWriteExpandStringValue(HKEY_LOCAL_MACHINE, EnvKey, 'Path', NewPath);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RemoveFromPath(ExpandConstant('{app}'));
end;

