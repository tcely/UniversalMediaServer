!include "MUI.nsh"
!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "TextFunc.nsh"
!include "WordFunc.nsh"
!include "LogicLib.nsh"
!include "nsDialogs.nsh"
!include "x64.nsh"

; Include the project header file generated by the nsis-maven-plugin
!include "..\..\..\..\target\project.nsh"
!include "..\..\..\..\target\extra.nsh"

!define REG_KEY_UNINSTALL "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${PROJECT_NAME}"
!define REG_KEY_SOFTWARE "SOFTWARE\${PROJECT_NAME}"

RequestExecutionLevel admin

Name "${PROJECT_NAME}"
InstallDir "$PROGRAMFILES\${PROJECT_NAME}"

; Get install folder from registry for updates
InstallDirRegKey HKCU "${REG_KEY_SOFTWARE}" ""

SetCompressor /SOLID lzma
SetCompressorDictSize 32

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_FUNCTION RunUMS
!define MUI_WELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\win.bmp"
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE WelcomeLeave

!define MUI_FINISHPAGE_SHOWREADME ""
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED
!define MUI_FINISHPAGE_SHOWREADME_TEXT "Create Desktop Shortcut"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION CreateDesktopShortcut

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
Page Custom LockedListShow LockedListLeave
Page Custom AdvancedSettings AdvancedSettingsAfterwards ; Custom page
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

ShowUninstDetails show

; Offer to install AviSynth 2.6 MT unless installer is in silent mode
Section -Prerequisites

	IfSilent jump_if_silent jump_if_not_silent

	jump_if_not_silent:
		SetRegView 32
		ReadRegStr $0 HKLM Software\Microsoft\Windows\CurrentVersion\Uninstall\AviSynth DisplayVersion

		${If} $0 != "2.6.0 MT"
			SetOutPath $INSTDIR\win32\avisynth
			MessageBox MB_YESNO "AviSynth 2.6 MT is recommended. Install it now?" /SD IDYES IDNO endAviSynthInstall
			File "..\..\..\..\target\bin\win32\avisynth\avisynth.exe"
			ExecWait "$INSTDIR\win32\avisynth\avisynth.exe"
		${EndIf}

	jump_if_silent:

	endAviSynthInstall:

SectionEnd

Function WelcomeLeave
	StrCpy $R1 0
FunctionEnd

Function LockedListShow
	StrCmp $R1 0 +2 ; Skip the page if clicking Back from the next page.
		Abort
	!insertmacro MUI_HEADER_TEXT `UMS must be closed before installation` `Clicking Next will automatically close it.`

	${If} ${RunningX64}
		File /oname=$PLUGINSDIR\LockedList64.dll `${NSISDIR}\Plugins\LockedList64.dll`
		LockedList::AddModule "$INSTDIR\MediaInfo64.dll"
	${Else}
		LockedList::AddModule "$INSTDIR\MediaInfo.dll"
	${EndIf}

	LockedList::Dialog /autonext /autoclosesilent
	Pop $R0
FunctionEnd

Function LockedListLeave
	StrCpy $R1 1
FunctionEnd

Var Dialog
Var Text
Var LabelMemoryLimit
Var DescMemoryLimit
Var CheckboxCleanInstall
Var CheckboxCleanInstallState
Var DescCleanInstall
Var MaximumMemoryJava

Function AdvancedSettings
	!insertmacro MUI_HEADER_TEXT "Advanced Settings" "If you don't understand them, don't change them."
	nsDialogs::Create 1018
	Pop $Dialog

	${If} $Dialog == error
		Abort
	${EndIf}

	; Choose maximum memory limit based on java type installed
	ClearErrors
	${If} ${RunningX64}
		SetRegView 64
	${EndIf}
	ReadRegStr $0 HKLM "SOFTWARE\JavaSoft\Java Runtime Environment" "CurrentVersion"
	IfErrors SetMinMem
	IfErrors 0 CheckMemAmnt

	; Get the amount of RAM on the computer
	CheckMemAmnt:
	System::Alloc 64
	Pop $1
	System::Call "*$1(i64)"
	System::Call "Kernel32::GlobalMemoryStatusEx(i r1)"
	System::Call "*$1(i.r2, i.r3, l.r4, l.r5, l.r6, l.r7, l.r8, l.r9, l.r10)"
	System::Free $1
	System::Int64Op $4 / 1048576
	Pop $4

	; Choose the maximum amount of RAM we want to use based on installed ram
	${If} $4 > 4000 
		StrCpy $MaximumMemoryJava "1280"
		Goto NSDContinue
	${Else}
		StrCpy $MaximumMemoryJava "768"
		Goto NSDContinue
	${EndIf}

	SetMinMem:
	StrCpy $MaximumMemoryJava "768" 

	NSDContinue:
	${NSD_CreateLabel} 0 0 100% 20u "This allows you to set the Java Heap size limit. The default value is recommended." 
	Pop $DescMemoryLimit

	${NSD_CreateLabel} 2% 20% 37% 12u "Maximum memory in megabytes"
	Pop $LabelMemoryLimit

	${NSD_CreateText} 3% 30% 10% 12u $MaximumMemoryJava
	Pop $Text

	${NSD_CreateLabel} 0 50% 100% 20u "This allows you to take advantage of improved defaults. It deletes the UMS configuration directory, the UMS program directory and font cache."
	Pop $DescCleanInstall

	${NSD_CreateCheckbox} 3% 65% 100% 12u "Clean install"
	Pop $CheckboxCleanInstall

	nsDialogs::Show
FunctionEnd

Function AdvancedSettingsAfterwards
	${NSD_GetText} $Text $0
	WriteRegStr HKCU "${REG_KEY_SOFTWARE}" "HeapMem" "$0"

	${NSD_GetState} $CheckboxCleanInstall $CheckboxCleanInstallState
	${If} $CheckboxCleanInstallState == ${BST_CHECKED}
		ReadENVStr $R1 ALLUSERSPROFILE
		RMDir /r $R1\UMS
		RMDir /r $TEMP\fontconfig
		RMDir /r $LOCALAPPDATA\fontconfig
		RMDir /r $INSTDIR
	${EndIf}
FunctionEnd

;Run program through explorer.exe to de-evaluate user from admin to regular one.
;http://mdb-blog.blogspot.ru/2013/01/nsis-lunch-program-as-user-from-uac.html
Function RunUMS
	Exec '"$WINDIR\explorer.exe" "$INSTDIR\UMS.exe"'
FunctionEnd 

Function CreateDesktopShortcut
	CreateShortCut "$DESKTOP\${PROJECT_NAME}.lnk" "$INSTDIR\UMS.exe"
FunctionEnd

Section "Program Files"
	SetOutPath "$INSTDIR"
	SetOverwrite on
	
	CreateDirectory "$INSTDIR\plugins"
	AccessControl::GrantOnFile "$INSTDIR\plugins" "(S-1-5-32-545)" "FullAccess"
		
	File /r /x "*.conf" /x "*.zip" /x "*.dll" /x "third-party" "${PROJECT_BASEDIR}\src\main\external-resources\plugins"
	File /r "${PROJECT_BASEDIR}\src\main\external-resources\documentation"
	File /r "${PROJECT_BASEDIR}\src\main\external-resources\renderers"
	File /r "${PROJECT_BASEDIR}\target\bin\win32"
	File "${PROJECT_BUILD_DIR}\UMS.exe"
	File "${PROJECT_BASEDIR}\src\main\external-resources\UMS.bat"
	File /r "${PROJECT_BASEDIR}\src\main\external-resources\web"
	File "${PROJECT_BUILD_DIR}\ums.jar"
	File "${PROJECT_BASEDIR}\MediaInfo.dll"
	File "${PROJECT_BASEDIR}\MediaInfo64.dll"
	File "${PROJECT_BASEDIR}\MediaInfo-License.html"
	File "${PROJECT_BASEDIR}\CHANGELOG.txt"
	File "${PROJECT_BASEDIR}\README.md"
	File "${PROJECT_BASEDIR}\LICENSE.txt"
	File "${PROJECT_BASEDIR}\src\main\external-resources\logback.xml"
	File "${PROJECT_BASEDIR}\src\main\external-resources\logback.headless.xml"
	File "${PROJECT_BASEDIR}\src\main\external-resources\icon.ico"
	File "${PROJECT_BASEDIR}\src\main\external-resources\DummyInput.ass"
	File "${PROJECT_BASEDIR}\src\main\external-resources\DummyInput.jpg"

	; The user may have set the installation dir as the profile dir, so we can't clobber this
	SetOverwrite off
	File "${PROJECT_BASEDIR}\src\main\external-resources\UMS.conf"
	File "${PROJECT_BASEDIR}\src\main\external-resources\WEB.conf"
	File "${PROJECT_BASEDIR}\src\main\external-resources\ffmpeg.webfilters"
	File "${PROJECT_BASEDIR}\src\main\external-resources\VirtualFolders.conf"

	; Remove old renderer files to prevent conflicts
	Delete /REBOOTOK "$INSTDIR\renderers\AirPlayer.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Android.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\AndroidChromecast.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BlackBerryPlayBook-KalemSoftMP.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Bravia4500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Bravia5500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaBX305.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaEX.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaEX620.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaHX.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaW.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaXBR.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\CambridgeAudioAzur752BD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\DirecTVHR.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Dlink510.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\DLinkDSM510.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\FreeboxHD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\FreecomMusicPal.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\iPad-iPhone.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Kuro.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-42LA644V.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LGST600.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\N900.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\NetgearNeoTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\OnkyoTX-NR717.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\OPPOBDP83.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\OPPOBDP93.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-SC-BTT.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-TH-P-U30Z.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\PanasonicTX-L32V10E.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VT60.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Philips.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\PhilipsPFL.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\PS3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Roku-Roku3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungAllShare.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungAllShare-CD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungAllShare-D7000.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungMobile.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-HT-E3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-SMT-G7400.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-UE-ES6575.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungWiseLink.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SharpAquos.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SMP-N100.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SonyBluray.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SonyHomeTheatreSystem.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SonySTR-5800ES.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SonyXperia.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Streamium.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\TelstraTbox.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\VideoWebTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\VizioSmartTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\WDTVLive.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\WMP.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\XBOX360.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\XboxOne.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\YamahaRXA1010.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\YamahaRXV671.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\YamahaRXV3900.conf"

	; Store install folder
	WriteRegStr HKCU "${REG_KEY_SOFTWARE}" "" $INSTDIR

	; Create uninstaller
	WriteUninstaller "$INSTDIR\uninst.exe"

	WriteRegStr HKEY_LOCAL_MACHINE "${REG_KEY_UNINSTALL}" "DisplayName" "${PROJECT_NAME}"
	WriteRegStr HKEY_LOCAL_MACHINE "${REG_KEY_UNINSTALL}" "DisplayIcon" "$INSTDIR\icon.ico"
	WriteRegStr HKEY_LOCAL_MACHINE "${REG_KEY_UNINSTALL}" "DisplayVersion" "${PROJECT_VERSION}"
	WriteRegStr HKEY_LOCAL_MACHINE "${REG_KEY_UNINSTALL}" "Publisher" "${PROJECT_ORGANIZATION_NAME}"
	WriteRegStr HKEY_LOCAL_MACHINE "${REG_KEY_UNINSTALL}" "URLInfoAbout" "${PROJECT_ORGANIZATION_URL}"
	WriteRegStr HKEY_LOCAL_MACHINE "${REG_KEY_UNINSTALL}" "UninstallString" '"$INSTDIR\uninst.exe"'

	${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
	IntFmt $0 "0x%08X" $0
	WriteRegDWORD HKLM "${REG_KEY_UNINSTALL}" "EstimatedSize" "$0"

	WriteUnInstaller "uninst.exe"

	ReadENVStr $R0 ALLUSERSPROFILE
	SetOutPath "$R0\UMS"

	CreateDirectory "$R0\UMS\data"

	AccessControl::GrantOnFile "$R0\UMS" "(S-1-5-32-545)" "FullAccess"
; 	AccessControl::GrantOnFile "$R0\UMS\data" "(BU)" "FullAccess"
	File "${PROJECT_BASEDIR}\src\main\external-resources\UMS.conf"
	File "${PROJECT_BASEDIR}\src\main\external-resources\WEB.conf"
	File "${PROJECT_BASEDIR}\src\main\external-resources\ffmpeg.webfilters"
	File "${PROJECT_BASEDIR}\src\main\external-resources\VirtualFolders.conf"
SectionEnd

Section "Start Menu Shortcuts"
	SetShellVarContext all
	CreateDirectory "$SMPROGRAMS\${PROJECT_NAME}"
	CreateShortCut "$SMPROGRAMS\${PROJECT_NAME}\${PROJECT_NAME}.lnk" "$INSTDIR\UMS.exe" "" "$INSTDIR\UMS.exe" 0
	CreateShortCut "$SMPROGRAMS\${PROJECT_NAME}\${PROJECT_NAME} (Select Profile).lnk" "$INSTDIR\UMS.exe" "profiles" "$INSTDIR\UMS.exe" 0
	CreateShortCut "$SMPROGRAMS\${PROJECT_NAME}\Uninstall.lnk" "$INSTDIR\uninst.exe" "" "$INSTDIR\uninst.exe" 0

	; Only start UMS with Windows when it is a new install
	IfFileExists "$SMPROGRAMS\${PROJECT_NAME}.lnk" 0 shortcut_file_not_found
		goto end_of_startup_section
	shortcut_file_not_found:
		CreateShortCut "$SMSTARTUP\${PROJECT_NAME}.lnk" "$INSTDIR\UMS.exe" "" "$INSTDIR\UMS.exe" 0
	end_of_startup_section:

	CreateShortCut "$SMPROGRAMS\${PROJECT_NAME}.lnk" "$INSTDIR\UMS.exe" "" "$INSTDIR\UMS.exe" 0
SectionEnd

Section "Uninstall"
	SetShellVarContext all

	Delete /REBOOTOK "$INSTDIR\uninst.exe"
	RMDir /R /REBOOTOK "$INSTDIR\plugins"
	RMDir /R /REBOOTOK "$INSTDIR\documentation"
	RMDir /R /REBOOTOK "$INSTDIR\data"
	RMDir /R /REBOOTOK "$INSTDIR\web"
	RMDir /R /REBOOTOK "$INSTDIR\win32"

	; Current renderer files
	Delete /REBOOTOK "$INSTDIR\renderers\AnyCast.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Apple-TV-VLC.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Apple-iDevice-AirPlayer.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Apple-iDevice-VLC32bit.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Apple-iDevice.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BlackBerry-PlayBook-KalemSoftMP.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\CambridgeAudio-AzurBD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\DefaultRenderer.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\DirecTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\DLink-DSM510.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\FetchTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Free-Freebox.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Freecom-MusicPal.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Google-Android-Chromecast.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Google-Android.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Google-Android-BubbleUPnP-MXPlayer.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Google-ChromecastUltra.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Hama-IR320.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Hisense-K680.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Kodi.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-BP.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-BP550.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-EG910V.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-LA6200.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-LA644V.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-LB.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-LM620.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-LM660.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-LS5700.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-ST600.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-UB820V.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-WebOS.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Logitech-Squeezebox.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Microsoft-WindowsMediaPlayer.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Microsoft-Xbox360.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Microsoft-XboxOne.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Miracast-M806.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Naim-Mu-So.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Netgear-NeoTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Netgem-N7700.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Nokia-N900.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\OPPO-BDP.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\OPPO-BDP83.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Onkyo-TXNR7xx.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Onkyo-TXNR8xx.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-DMPBDT.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-DMPBDT220.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-DMPBDT360.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-DMRBWT740.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-SCBTT.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-Viera.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraAS600E.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraAS650.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraCX680.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraCX700.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraE6.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraET60.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraGT50.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraS60.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraST60.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraTHPU30Z.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraTXL32V10E.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VieraVT60.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Philips-AureaAndNetTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Philips-PFL.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Philips-Streamium.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Pioneer-BDP.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Pioneer-Kuro.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\PopcornHour.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\README.txt"
	Delete /REBOOTOK "$INSTDIR\renderers\Realtek.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Roku-Roku3-3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Roku-Roku3-5.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-9series.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-BDC6800.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-BDH6500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-C6600.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-CD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-D6400.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-D7000.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-EH5300.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-EH6070.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-ES6100.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-ES6575.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-ES8000.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-ES8005.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-F5100.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-F5505.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-F5900.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-GalaxyS5.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-H4500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-H6203.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-H6400.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-HTE3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-HTF4.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-HU7000.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-HU9000.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-JU6400.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-J55xx.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-J6200.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-JU6400.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-Mobile.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-NotCD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-PL51E490.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-SMTG7400.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-WiseLink.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sharp-Aquos.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Showtime3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Showtime4.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-Bluray.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-Bluray2013.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-Bravia4500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-Bravia5500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaBX305.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaEX.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaEX620.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaEX725.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaHX.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaHX75.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaNX70x.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaNX800.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaW.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaX.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaXBR.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-BraviaXD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-HomeTheatreSystem.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-PlayStation3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-PlayStation4.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-PlayStation4Pro.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-PlayStationVita.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-SMPN100.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-STR5800ES.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-Xperia.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Sony-XperiaZ3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Technisat-S1Plus.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Telefunken-TV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Telstra-Tbox.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Thomson-U3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\VLC-for-desktop.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\VideoWeb-VideoWebTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Vizio-SmartTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\WesternDigital-WDTVLive.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\XBMC.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Yamaha-RN500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Yamaha-RXA1010.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Yamaha-RXA2050.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Yamaha-RXV3900.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Yamaha-RXV500D.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Yamaha-RXV671.conf"

	; Old renderer files
	Delete /REBOOTOK "$INSTDIR\renderers\AirPlayer.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Android.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\AndroidChromecast.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BlackBerryPlayBook-KalemSoftMP.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Bravia4500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Bravia5500.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaBX305.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaEX.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaEX620.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaHX.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaW.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\BraviaXBR.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\CambridgeAudioAzur752BD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\DirecTVHR.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Dlink510.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\DLinkDSM510.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\FreeboxHD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\FreecomMusicPal.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\iPad-iPhone.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Kuro.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LG-42LA644V.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\LGST600.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\N900.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\NetgearNeoTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\OnkyoTX-NR717.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\OPPOBDP83.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\OPPOBDP93.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-SC-BTT.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-TH-P-U30Z.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\PanasonicTX-L32V10E.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Panasonic-VT60.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Philips.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\PhilipsPFL.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\PS3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Roku-Roku3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungAllShare.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungAllShare-CD.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungAllShare-D7000.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungMobile.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-HT-E3.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-SMT-G7400.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Samsung-UE-ES6575.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SamsungWiseLink.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SharpAquos.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SMP-N100.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SonyBluray.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SonyHomeTheatreSystem.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SonySTR-5800ES.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\SonyXperia.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\Streamium.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\TelstraTbox.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\VideoWebTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\VizioSmartTV.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\WDTVLive.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\WMP.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\XBOX360.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\XboxOne.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\YamahaRXA1010.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\YamahaRXV671.conf"
	Delete /REBOOTOK "$INSTDIR\renderers\YamahaRXV3900.conf"

	RMDir /REBOOTOK "$INSTDIR\renderers"
	Delete /REBOOTOK "$INSTDIR\UMS.exe"
	Delete /REBOOTOK "$INSTDIR\UMS.bat"
	Delete /REBOOTOK "$INSTDIR\ums.jar"
	Delete /REBOOTOK "$INSTDIR\MediaInfo.dll"
	Delete /REBOOTOK "$INSTDIR\MediaInfo64.dll"
	Delete /REBOOTOK "$INSTDIR\MediaInfo-License.html"
	Delete /REBOOTOK "$INSTDIR\CHANGELOG.txt"
	Delete /REBOOTOK "$INSTDIR\WEB.conf"
	Delete /REBOOTOK "$INSTDIR\README.md"
	Delete /REBOOTOK "$INSTDIR\README.txt"
	Delete /REBOOTOK "$INSTDIR\LICENSE.txt"
	Delete /REBOOTOK "$INSTDIR\debug.log"
	Delete /REBOOTOK "$INSTDIR\debug.log.prev"
	Delete /REBOOTOK "$INSTDIR\ffmpeg.webfilters"
	Delete /REBOOTOK "$INSTDIR\logback.xml"
	Delete /REBOOTOK "$INSTDIR\logback.headless.xml"
	Delete /REBOOTOK "$INSTDIR\icon.ico"
	Delete /REBOOTOK "$INSTDIR\DummyInput.ass"
	Delete /REBOOTOK "$INSTDIR\DummyInput.jpg"
	Delete /REBOOTOK "$INSTDIR\new-version.exe"
	Delete /REBOOTOK "$INSTDIR\pms.pid"
	Delete /REBOOTOK "$INSTDIR\UMS.conf"
	Delete /REBOOTOK "$INSTDIR\VirtualFolders.conf"
	RMDir /REBOOTOK "$INSTDIR"

	Delete /REBOOTOK "$DESKTOP\${PROJECT_NAME}.lnk"
	RMDir /REBOOTOK "$SMPROGRAMS\${PROJECT_NAME}"
	Delete /REBOOTOK "$SMPROGRAMS\${PROJECT_NAME}\${PROJECT_NAME}.lnk"
	Delete /REBOOTOK "$SMPROGRAMS\${PROJECT_NAME}\${PROJECT_NAME} (Select Profile).lnk"
	Delete /REBOOTOK "$SMPROGRAMS\${PROJECT_NAME}\Uninstall.lnk"

	DeleteRegKey HKEY_LOCAL_MACHINE "${REG_KEY_UNINSTALL}"
	DeleteRegKey HKCU "${REG_KEY_SOFTWARE}"

	nsSCM::Stop "${PROJECT_NAME}"
	nsSCM::Remove "${PROJECT_NAME}"
SectionEnd
