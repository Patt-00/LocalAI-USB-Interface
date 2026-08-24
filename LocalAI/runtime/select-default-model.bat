@echo off
setlocal EnableExtensions
set "MODEL_DIR=%~f1"
set "SELECTED_MODEL="

if not exist "%MODEL_DIR%\" exit /b 1

if exist "%MODEL_DIR%\default-model.txt" call :READ_SELECTOR

if defined SELECTED_MODEL goto :FOUND
for /r "%MODEL_DIR%" %%F in (*.gguf) do (
  call :TRY_MODEL "%%~fF"
  if defined SELECTED_MODEL goto :FOUND
)
exit /b 1

:READ_SELECTOR
set "MODEL_ENTRY="
set /p "MODEL_ENTRY="<"%MODEL_DIR%\default-model.txt"
if defined MODEL_ENTRY call :TRY_MODEL "%MODEL_DIR%\%MODEL_ENTRY%"
if not defined SELECTED_MODEL if defined MODEL_ENTRY call :TRY_MODEL "%MODEL_ENTRY%"
exit /b 0

:TRY_MODEL
if defined SELECTED_MODEL exit /b 0
if not exist "%~f1" exit /b 0
set "MODEL_NAME=%~nx1"
if /I "%MODEL_NAME:~0,6%"=="mmproj" exit /b 0
echo(%MODEL_NAME%| findstr /R /I /C:"-0000[2-9]-of-" /C:"-000[1-9][0-9]-of-" >nul && exit /b 0
set "SELECTED_MODEL=%~f1"
exit /b 0

:FOUND
echo(%SELECTED_MODEL%
exit /b 0
