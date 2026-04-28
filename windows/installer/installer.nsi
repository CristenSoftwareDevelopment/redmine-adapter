; Redmine Monitor — NSIS installer script
; Called by the GitHub Actions release workflow.
; Expected defines (passed via /D on the command line):
;   APP_VERSION  — e.g. 1.0.0
;   BUILD_DIR    — absolute path to the Flutter release bundle directory

!define APP_NAME    "Redmine Monitor"
!define APP_EXE     "RedmineMonitor.exe"
!define PUBLISHER   "Redmine Monitor"
!define REG_KEY     "Software\Microsoft\Windows\CurrentVersion\Uninstall\RedmineMonitor"

Name "${APP_NAME}"
OutFile "RedmineMonitor-${APP_VERSION}-windows-setup.exe"
InstallDir "$PROGRAMFILES64\${APP_NAME}"
InstallDirRegKey HKLM "${REG_KEY}" "InstallLocation"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
Unicode true

;--- Pages ---
!include "MUI2.nsh"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Portuguese"

;--- Install ---
Section "Main" SecMain
  SetOutPath "$INSTDIR"
  File /r "${BUILD_DIR}\*.*"

  ; Start Menu shortcut
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Desinstalar.lnk" "$INSTDIR\uninstall.exe"

  ; Desktop shortcut
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  ; Uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; Add/Remove Programs entry
  WriteRegStr   HKLM "${REG_KEY}" "DisplayName"      "${APP_NAME}"
  WriteRegStr   HKLM "${REG_KEY}" "DisplayVersion"   "${APP_VERSION}"
  WriteRegStr   HKLM "${REG_KEY}" "Publisher"        "${PUBLISHER}"
  WriteRegStr   HKLM "${REG_KEY}" "InstallLocation"  "$INSTDIR"
  WriteRegStr   HKLM "${REG_KEY}" "UninstallString"  "$INSTDIR\uninstall.exe"
  WriteRegDWORD HKLM "${REG_KEY}" "NoModify"         1
  WriteRegDWORD HKLM "${REG_KEY}" "NoRepair"         1
SectionEnd

;--- Uninstall ---
Section "Uninstall"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Desinstalar.lnk"
  RMDir  "$SMPROGRAMS\${APP_NAME}"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "${REG_KEY}"
SectionEnd
