; NSIS Installer Script for CLAN-AI
; Generates a traditional .exe installer that wraps the MSIX package
; Requires NSIS: https://nsis.sourceforge.io/Download
; Usage: makensis /DMSIX_SOURCE="path\to\package.msix" /DDIST_DIR="dist" nsis_installer.nsi

; --- Configuration ---
!define APP_NAME "CLAN-AI"
!define APP_DISPLAY_NAME "CLAN-AI"
!define APP_PUBLISHER "CLAN-AI Organization"
!define APP_URL "https://github.com/clan-ai/clan_ai"

; Defaults (can be overridden via /D on command line)
!ifndef MSIX_SOURCE
  !define MSIX_SOURCE "dist\clan_ai_1.0.0.msix"
!endif

!ifndef DIST_DIR
  !define DIST_DIR "..\dist"
!endif

!define INSTALLER_OUTPUT "${DIST_DIR}\CLAN-AI_Setup.exe"

; App version
!define APP_VERSION "1.0.0"

; Install paths
!define INSTALL_DIR "C:\Users\%CURRENT_USER%\AppData\Local\Programs\CLAN-AI"

; --- Include Modern UI ---
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

; --- Installer Settings ---
Name "${APP_DISPLAY_NAME}"
OutFile "${INSTALLER_OUTPUT}"
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel user
CRCCheck on
SetCompressor /SOLID lzma

; --- Version Info ---
VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${APP_DISPLAY_NAME}"
VIAddVersionKey /LANG=1033 "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright (C) 2026 ${APP_PUBLISHER}. All rights reserved."
VIAddVersionKey /LANG=1033 "FileDescription" "${APP_DISPLAY_NAME} Installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${APP_VERSION}"

; --- Modern UI Settings ---
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_ICON "icon.png"
!define MUI_UNICON "icon.png"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_NOAUTOSTART

; --- UI Pages ---
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

; Finish page - show launcher checkbox
Var LaunchApp
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; --- Language ---
!insertmacro MUI_LANGUAGE "English"

; --- Install Section ---
Section "Install"
    SetOutPath "$INSTDIR"

    ; Check if already installed
    ReadRegStr $R0 HKCU "SOFTWARE\CLAN-AI" "Installed"
    ${If} $R0 != ""
        MessageBox MB_YESNO "CLAN-AI is already installed. Do you want to reinstall?" /SD IDYES IDNO AlreadyInstalled
        Goto ProceedInstall
    ${EndIf}

    AlreadyInstalled:
        ; App is already installed, just mark as reinstalled
        Goto PostInstall

    ProceedInstall:
        ; Ensure MSIX file exists
        IfFileExists "${MSIX_SOURCE}" 0 NoMsix
        Goto InstallMsix

        NoMsix:
            MessageBox MB_ICONSTOP "CLAN-AI package not found.`nPlease build the MSIX package first using: flutter build msix --release`nExpected at: ${MSIX_SOURCE}"
            Quit

        InstallMsix:
            CopyFiles /SILENT "${MSIX_SOURCE}" "$INSTDIR\"
            Push "$INSTDIR\clan_ai.msix"
            Pop $R1
            ; Check if running on Windows 10+
            System::Call 'kernel32::GetVersion() i.r0'
            IntOp $0 $R0 & 0xFFFF
            IntCmp $0 10 Win10ok Win98ok Win98ok
            Win10ok:
                Goto AfterWinCheck
            Win98ok:
                MessageBox MB_ICONSTOP "CLAN-AI requires Windows 10 or later."
                Quit
            AfterWinCheck:

            ; Install MSIX package silently
            ; First, ensure sideloading is enabled
            ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowDevelopmentWithoutDevLicense"
            ${If} $R0 == ""
                WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowDevelopmentWithoutDevLicense" "1"
                WriteRegStr HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowAllTrustedApps" "1"
            ${EndIf}

            ; Install the MSIX package
            ; Using Add-AppxPackage which handles registration
            nsExec::ExecToStack '"$ENV:SystemRoot\system32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Add-AppxPackage -Path $\"$R1$\" -ForceApplicationShutdown -ForceShieldUIClosing -Verbose"'
            Pop $R0
            
            ; Check exit code (0 = success)
            IntCmp $R0 0 InstallSuccess InstallFailed
        
        InstallSuccess:
            ; Create Start Menu shortcut
            CreateShortCut "$SMPROGRAMS\CLAN-AI.lnk" "$INSTDIR\clan_ai.exe"
            
            ; Register in uninstall registry
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "InstallDate" "$LOCALAPPDATA\CLAN-AI"
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "Installed" "1"
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "DisplayVersion" "${APP_VERSION}"
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "Publisher" "${APP_PUBLISHER}"
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "InstallLocation" "$INSTDIR"
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "DisplayIcon" '"$INSTDIR\clan_ai.exe"'
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "UninstallString" '"$INSTDIR\Uninstall.exe"'
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "EstimatedSize" "102400"
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "HelpLink" "${APP_URL}"
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "URLInfoAbout" "${APP_URL}"
            WriteRegStr HKCU "SOFTWARE\CLAN-AI" "Contact" "support@clan-ai.org"

            ; Create uninstaller
            WriteUninstaller "$INSTDIR\Uninstall.exe"
            
            Goto PostInstall

        InstallFailed:
            MessageBox MB_ICONSTOP "Failed to install CLAN-AI. The MSIX package may require a trusted certificate.`n`nYou can still launch the app from the Start Menu.`n`nError code: $R0" /SD IDOK
            Goto PostInstall

    PostInstall:
        ; Clean up - remove copied MSIX after install (it's already registered)
        Delete "$INSTDIR\clan_ai.msix"
SectionEnd

; --- Optional: Quick Launch link on finish page (handled by finish page text) ---
Section "Quick Launch"
    ; This section is not used; the checkbox on finish page controls launch
SectionEnd

; --- Uninstall Section ---
Section "Uninstall"
    ; Uninstall MSIX package
    nsExec::ExecToStack '"$ENV:SystemRoot\system32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "Get-AppxPackage *clan_ai* | Remove-AppxPackage"'
    
    ; Remove Start Menu shortcut
    Delete "$SMPROGRAMS\CLAN-AI.lnk"
    
    ; Remove registry entries
    DeleteRegKey HKCU "SOFTWARE\CLAN-AI"
    
    ; Remove install directory (MSIX files are in LocalAppData, but keep this for any extras)
    RMDir /R "$INSTDIR"
    
    ; Clean AppModelUnlock settings if we set them
    DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowDevelopmentWithoutDevLicense"
    DeleteRegValue HKLM "SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowAllTrustedApps"
SectionEnd
