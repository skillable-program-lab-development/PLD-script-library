@echo off
setlocal
rem Drag one or more CSV files onto this file to create HTML reports next to them.
rem Double-click it with no files to pick CSVs from a file dialog.
rem Keep this file in the same folder as ConvertTo-TranslationReportHtml.ps1.

set "SCRIPT=%~dp0ConvertTo-TranslationReportHtml.ps1"
if not exist "%SCRIPT%" goto noscript

set "PS=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"

if "%~1"=="" goto picker

:next
if "%~1"=="" goto done
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Path "%~1" -Open -NoPause
shift
goto next

:picker
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Open -NoPause
goto done

:noscript
echo Can't find "%SCRIPT%".
echo Keep this .cmd in the same folder as the .ps1.

:done
echo.
pause
