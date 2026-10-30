@echo off
setlocal DisableDelayedExpansion
title Windows 11 Core Software Configurator
color f0

fltmc >nul 2>&1
if errorlevel 1 (
  set "SCRIPT_PATH=%~f0"
  powershell -NoProfile -Command "Start-Process -FilePath $env:ComSpec -ArgumentList ('/c ' + [char]34 + [char]34 + $env:SCRIPT_PATH + [char]34 + [char]34) -Verb RunAs"
  exit /b
)

cls
echo Please close all applications before continuing.
echo.
pause

set /a errors=0
set "failures="

cls
echo Setting configuration files...
call :CopyFile "%~dp0bin\JPEGView.ini" "%AppData%\JPEGView\JPEGView.ini"

cls
echo Setting configuration files...
call :CopyFile "%~dp0bin\SumatraPDF-settings.txt" "%LocalAppData%\SumatraPDF\SumatraPDF-settings.txt"

cls
echo Setting configuration files...
set "BravePath=%LocalAppData%\BraveSoftware\Brave-Browser\User Data\Default"
call :CopyFile "%~dp0bin\Preferences" "%BravePath%\Preferences"
call :CopyFile "%~dp0bin\Secure Preferences" "%BravePath%\Secure Preferences"

cls
echo Checking Windows App Runtime 1.3...
set "RUNTIME_PATH=%TEMP%\WindowsAppRuntimeInstall.exe"
set "RUNTIME_READY="
set "RUNTIME_URL=https://aka.ms/windowsappsdk/1.3/1.3.230724000/windowsappruntimeinstall-x64.exe"
set "RUNTIME_HASH=A722EE97261E01E8DD6165A8EFAE67CEFDB21B3EE5D9122C662324A0B11DAF38"

call :CheckRuntime
if not errorlevel 1 (
  set "RUNTIME_READY=1"
  echo Windows App Runtime 1.3 is already installed.
) else (
  echo Downloading Windows App Runtime 1.3 from Microsoft...

  if exist "%RUNTIME_PATH%" del /q "%RUNTIME_PATH%" >nul 2>&1

  powershell -NoProfile -Command "$ErrorActionPreference='Stop'; Invoke-WebRequest -Uri $env:RUNTIME_URL -OutFile $env:RUNTIME_PATH; $hash=(Get-FileHash -LiteralPath $env:RUNTIME_PATH -Algorithm SHA256).Hash; if ($hash -ne $env:RUNTIME_HASH) { throw 'Installer SHA256 verification failed' }"

  if errorlevel 1 (
    set /a errors+=1
    call :RecordFailure "Windows App Runtime download or verification failed"
  ) else (
    echo Installing Windows App Runtime 1.3...

    "%RUNTIME_PATH%" --quiet

    if errorlevel 1 (
      set /a errors+=1
      call :RecordFailure "Windows App Runtime installation failed"
    ) else (
      call :CheckRuntime
      if errorlevel 1 (
        set /a errors+=1
        call :RecordFailure "Windows App Runtime dependency missing"
      ) else (
        set "RUNTIME_READY=1"
        echo Windows App Runtime installed successfully.
      )
    )
  )

  if exist "%RUNTIME_PATH%" del /q "%RUNTIME_PATH%" >nul 2>&1
)

cls
echo Checking Microsoft VCLibs x64...
set "VCLIBS_PATH=%~dp0bin\Microsoft.VCLibs.x64.14.00.Desktop.appx"
set "VCLIBS_READY="

call :CheckVCLibs
if not errorlevel 1 (
  set "VCLIBS_READY=1"
  echo Microsoft VCLibs is already installed.
) else (
  echo Installing Microsoft VCLibs...

  if exist "%VCLIBS_PATH%" (
    powershell -NoProfile -Command "Add-AppxPackage -Path $env:VCLIBS_PATH -ErrorAction Stop" >nul 2>&1

    if errorlevel 1 (
      set /a errors+=1
      call :RecordFailure "Microsoft VCLibs installation failed"
    ) else (
      call :CheckVCLibs
      if errorlevel 1 (
        set /a errors+=1
        call :RecordFailure "Microsoft VCLibs dependency missing"
      ) else (
        set "VCLIBS_READY=1"
        echo Microsoft VCLibs installed successfully.
      )
    )
  ) else (
    set /a errors+=1
    call :RecordFailure "Microsoft VCLibs installer not found"
  )
)

cls
echo Installing Snipping Tool...
set "SNIPPING_PATH=%~dp0bin\snipping-tool-2022-2307-48-0.msixbundle"

if not defined RUNTIME_READY goto SnippingDependencyFailed
if not defined VCLIBS_READY goto SnippingDependencyFailed

if exist "%SNIPPING_PATH%" (
  powershell -NoProfile -Command "Add-AppxPackage -Path $env:SNIPPING_PATH -ErrorAction Stop" >nul 2>&1

  if errorlevel 1 (
    set /a errors+=1
    call :RecordFailure "Snipping Tool installation failed"
  ) else (
    echo Snipping Tool installed successfully.
  )
) else (
  set /a errors+=1
  call :RecordFailure "Snipping Tool installer not found"
)

goto SnippingDone

:SnippingDependencyFailed
set /a errors+=1
call :RecordFailure "Snipping Tool skipped - dependency missing"

:SnippingDone
cls
echo Setting registry files...
set "RegFound="

for %%F in ("%~dp0bin\*.reg") do if exist "%%~fF" call :ImportReg "%%~fF"

if not defined RegFound (
  set /a errors+=1
  call :RecordFailure "No registry files found"
)

cls
if %errors% NEQ 0 goto Failed
echo All software has now been configured.
goto Finished

:Failed
color 4f
cls
echo Configuration completed with %errors% error(s).
echo.
echo Failed operations:
echo %failures%

:Finished
echo.
echo Visit https://sysconf16.github.io/ for more resources.
pause
exit /b %errors%

:CheckRuntime
powershell -NoProfile -Command "$p = Get-AppxPackage -Name 'Microsoft.WindowsAppRuntime.1.3' -ErrorAction SilentlyContinue | Where-Object { $_.Architecture -eq 'X64' -and $_.Version -ge [version]'3000.882.2207.0' }; if ($p) { exit 0 } else { exit 1 }" >nul 2>&1
exit /b %errorlevel%

:CheckVCLibs
powershell -NoProfile -Command "$p = Get-AppxPackage -Name 'Microsoft.VCLibs.140.00.UWPDesktop' -ErrorAction SilentlyContinue | Where-Object { $_.Architecture -eq 'X64' -and $_.Version -ge [version]'14.0.30704.0' }; if ($p) { exit 0 } else { exit 1 }" >nul 2>&1
exit /b %errorlevel%

:CopyFile
if not exist "%~1" goto CopyFailed
if not exist "%~dp2" mkdir "%~dp2" >nul 2>&1
copy /Y "%~1" "%~2" >nul 2>&1
if errorlevel 1 goto CopyFailed
exit /b

:CopyFailed
set /a errors+=1
call :RecordFailure "Copy: %~nx1"
exit /b

:ImportReg
set "RegFound=1"
reg import "%~1" >nul 2>&1
if errorlevel 1 (
  set /a errors+=1
  call :RecordFailure "Registry: %~nx1"
)
exit /b

:RecordFailure
if defined failures (
  set "failures=%failures% - %~1;"
) else (
  set "failures=- %~1;"
)
exit /b