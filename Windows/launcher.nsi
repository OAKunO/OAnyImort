Unicode true
Name "OAnyImport"
OutFile "build/payload/OAnyImport.exe"
RequestExecutionLevel user
SilentInstall silent
AutoCloseWindow true
Icon "app.ico"
VIProductVersion "1.1.1.1"
VIAddVersionKey /LANG=1033 "ProductName" "OAnyImport"
VIAddVersionKey /LANG=1033 "FileDescription" "OAnyImport media importer"
VIAddVersionKey /LANG=1033 "FileVersion" "1.1.1"
VIAddVersionKey /LANG=1033 "LegalCopyright" "OAnyImport"
Section
    SetOutPath "$EXEDIR"
    ClearErrors
    ExecWait '"$EXEDIR\runtime\pythonw.exe" -E -s -B "$EXEDIR\bootstrap.py"' $0
    IfErrors launch_failed
    Goto done
launch_failed:
    MessageBox MB_OK|MB_ICONSTOP "OAnyImport could not start. Please reinstall the app."
done:
SectionEnd
