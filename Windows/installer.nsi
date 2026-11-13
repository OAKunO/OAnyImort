Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!ifndef PAYLOAD_GLOB
!define PAYLOAD_GLOB "build/payload/*"
!endif
Name "OAnyImport"
OutFile "dist/OAnyImport-Setup-1.1.1-x64.exe"
InstallDir "$LOCALAPPDATA\Programs\OAnyImport"
InstallDirRegKey HKCU "Software\OAnyImport" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 32
BrandingText "OAnyImport"
Icon "app.ico"
UninstallIcon "app.ico"
VIProductVersion "1.1.1.1"
VIAddVersionKey /LANG=1033 "ProductName" "OAnyImport"
VIAddVersionKey /LANG=1033 "FileDescription" "OAnyImport Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "1.1.1"
VIAddVersionKey /LANG=1033 "LegalCopyright" "OAnyImport"
!define MUI_ABORTWARNING
!define MUI_ICON "app.ico"
!define MUI_UNICON "app.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\OAnyImport.exe"
!define MUI_FINISHPAGE_RUN_TEXT "打开 OAnyImport"
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
        MessageBox MB_OK|MB_ICONSTOP "OAnyImport 需要 64 位 Windows。"
        Abort
    ${EndIf}
    ${IfNot} ${AtLeastWin10}
        MessageBox MB_OK|MB_ICONSTOP "OAnyImport 需要 Windows 10 或更新版本。"
        Abort
    ${EndIf}
    SetShellVarContext current
FunctionEnd
Section "OAnyImport"
    SetOutPath "$INSTDIR"
    File /r "${PAYLOAD_GLOB}"
    IfErrors 0 +3
        MessageBox MB_OK|MB_ICONSTOP "文件写入失败。请关闭 OAnyImport 后重新安装。"
        Abort
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateDirectory "$SMPROGRAMS\OAnyImport"
    CreateShortcut "$SMPROGRAMS\OAnyImport\OAnyImport.lnk" "$INSTDIR\OAnyImport.exe" "" "$INSTDIR\app.ico"
    CreateShortcut "$SMPROGRAMS\OAnyImport\卸载 OAnyImport.lnk" "$INSTDIR\Uninstall.exe"
    CreateShortcut "$DESKTOP\OAnyImport.lnk" "$INSTDIR\OAnyImport.exe" "" "$INSTDIR\app.ico"
    WriteRegStr HKCU "Software\OAnyImport" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImport" "DisplayName" "OAnyImport"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImport" "DisplayVersion" "1.1.1"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImport" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImport" "DisplayIcon" "$INSTDIR\app.ico"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImport" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImport" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImport" "NoRepair" 1
SectionEnd
Section "Uninstall"
    SetShellVarContext current
    Delete "$DESKTOP\OAnyImport.lnk"
    RMDir /r "$SMPROGRAMS\OAnyImport"
    ; Delete only application-owned files; imported media belongs outside this folder.
    Delete "$INSTDIR\OAnyImport.exe"
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
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OAnyImport"
    DeleteRegKey HKCU "Software\OAnyImport"
SectionEnd
