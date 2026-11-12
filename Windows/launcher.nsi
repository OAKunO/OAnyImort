Unicode true
Name "OAnyImort"
OutFile "build/payload/OAnyImort.exe"
RequestExecutionLevel user
SilentInstall silent
AutoCloseWindow true
Icon "app.ico"
VIProductVersion "1.1.0.0"
VIAddVersionKey /LANG=1033 "ProductName" "OAnyImort"
VIAddVersionKey /LANG=1033 "FileDescription" "OAnyImort media importer"
VIAddVersionKey /LANG=1033 "FileVersion" "1.1.0"
VIAddVersionKey /LANG=1033 "LegalCopyright" "OAnyImort"
Section
    SetOutPath "$EXEDIR"
    ClearErrors
    ExecWait '"$EXEDIR\runtime\pythonw.exe" -E -s -B "$EXEDIR\bootstrap.py"' $0
    IfErrors launch_failed
    Goto done
launch_failed:
    MessageBox MB_OK|MB_ICONSTOP "OAnyImort could not start. Please reinstall the app."
done:
SectionEnd
