Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!ifndef PAYLOAD_GLOB
!define PAYLOAD_GLOB "build/payload/*"
!endif
Name "OAnyImort"
OutFile "dist/OAnyImort-Setup-1.1.0-x64.exe"
InstallDir "$LOCALAPPDATA\Programs\OAnyImort"
InstallDirRegKey HKCU "Software\OAnyImort" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 32
BrandingText "OAnyImort"
Icon "app.ico"
UninstallIcon "app.ico"
VIProductVersion "1.1.0.0"
VIAddVersionKey /LANG=1033 "ProductName" "OAnyImort"
VIAddVersionKey /LANG=1033 "FileDescription" "OAnyImort Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "1.1.0"
VIAddVersionKey /LANG=1033 "LegalCopyright" "OAnyImort"
!define MUI_ABORTWARNING
!define MUI_ICON "app.ico"
!define MUI_UNICON "app.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\OAnyImort.exe"
!define MUI_FINISHPAGE_RUN_TEXT "打开 OAnyImort"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"
Function .onInit
    ${IfNot} ${RunningX64}
        MessageBox MB_OK|MB_ICONSTOP "OAnyImort 需要 64 位 Windows。"
        Abort
    ${EndIf}
    ${IfNot} ${AtLeastWin10}
        MessageBox MB_OK|MB_ICONSTOP "OAnyImort 需要 Windows 10 或更新版本。"
        Abort
    ${EndIf}
    SetShellVarContext current
FunctionEnd
Section "OAnyImort"
    SetOutPath "$INSTDIR"
    File /r "${PAYLOAD_GLOB}"
    IfErrors 0 +3
        MessageBox MB_OK|MB_ICONSTOP "文件写入失败。请关闭 OAnyImort 后重新安装。"
        Abort
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateDirectory "$SMPROGRAMS\OAnyImort"
    CreateShortcut "$SMPROGRAMS\OAnyImort\OAnyImort.lnk" "$INSTDIR\OAnyImort.exe" "" "$INSTDIR\app.ico"
    CreateShortcut "$SMPROGRAMS\OAnyImort\卸载 OAnyImort.lnk" "$INSTDIR\Uninstall.exe"
    CreateShortcut "$DESKTOP\OAnyImort.lnk" "$INSTDIR\OAnyImort.exe" "" "$INSTDIR\app.ico"
    WriteRegStr HKCU "Software\OAnyImort" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImort" "DisplayName" "OAnyImort"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImort" "DisplayVersion" "1.1.0"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImort" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImort" "DisplayIcon" "$INSTDIR\app.ico"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImort" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImort" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImort" "NoRepair" 1
SectionEnd
Section "Uninstall"
    SetShellVarContext current
    Delete "$DESKTOP\OAnyImort.lnk"
    RMDir /r "$SMPROGRAMS\OAnyImort"
    ; Delete only application-owned files; imported media belongs outside this folder.
    Delete "$INSTDIR\OAnyImort.exe"
    Delete "$INSTDIR\app.py"
    Delete "$INSTDIR\core.py"
    Delete "$INSTDIR\media_browser.py"
    Delete "$INSTDIR\checkmark.svg"
    RMDir /r "$INSTDIR\licenses"
    Delete "$INSTDIR\bootstrap.py"
    Delete "$INSTDIR\app.ico"
    Delete "$INSTDIR\使用说明.txt"
    Delete "$INSTDIR\runtime-source.json"
    Delete "$INSTDIR\THIRD_PARTY_NOTICES.txt"
    Delete "$INSTDIR\LICENSE.txt"
    RMDir /r "$INSTDIR\runtime"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImort"
    DeleteRegKey HKCU "Software\OAnyImort"
SectionEnd
