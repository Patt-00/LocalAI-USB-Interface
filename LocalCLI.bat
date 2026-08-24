@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "ROOT=%~dp0"
set "LOCALAI_ROOT=%ROOT%"

if /I "%~1"=="--help" goto :HELP
if /I "%~1"=="-h" goto :HELP

set "MODEL=%~1"
if not defined MODEL (
  set "MODEL_SELECTOR=%ROOT%LocalAI\runtime\select-default-model.bat"
  if not exist "%ROOT%LocalAI\runtime\select-default-model.bat" goto :NO_SELECTOR
  for /f "usebackq delims=" %%M in (`call "%ROOT%LocalAI\runtime\select-default-model.bat" "%ROOT%LocalAI\models"`) do set "MODEL=%%M"
)
if not defined MODEL goto :NO_MODEL
if not exist "%MODEL%" goto :NO_MODEL

if /I "%PROCESSOR_ARCHITECTURE%"=="x86" if "%PROCESSOR_ARCHITEW6432%"=="" goto :UNSUPPORTED
set "RUNTIME=%ROOT%LocalAI\windows-x64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "RUNTIME=%ROOT%LocalAI\windows-arm64"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "RUNTIME=%ROOT%LocalAI\windows-arm64"
set "CLI=%RUNTIME%\llama-cli.exe"
if not exist "%CLI%" goto :NO_CLI

set "CTX_SIZE=4096"
for /f "usebackq delims=" %%C in (`powershell.exe -NoLogo -NoProfile -Command "$n=0;$p=Join-Path $env:USERPROFILE '.localai-usb-context-size';if((Test-Path -LiteralPath $p)-and[int]::TryParse(([IO.File]::ReadAllText($p).Trim()),[ref]$n)-and$n-ge512-and$n-le131072){$n}else{4096}"`) do set "CTX_SIZE=%%C"

set "GPU_BACKEND=CPU"
set "GPU_DEVICE="
if exist "%ROOT%LocalAI\runtime\select-windows-gpu.ps1" (
  for /f "tokens=1,2 delims=|" %%A in ('powershell.exe -NoLogo -NoProfile -File "%ROOT%LocalAI\runtime\select-windows-gpu.ps1" -Root "%ROOT%" 2^>nul') do (
    set "GPU_BACKEND=%%A"
    set "GPU_DEVICE=%%B"
  )
)
set "GPU_ARGS=--gpu-layers 0"
set "ACCELERATION=CPU"
if /I not "%GPU_BACKEND%"=="CPU" (
  set "GPU_ARGS=--gpu-layers auto --fit on --fit-target 512"
  set "ACCELERATION=%GPU_BACKEND% GPU offload"
  if defined GPU_DEVICE set "GPU_ARGS=--device %GPU_DEVICE% --gpu-layers auto --fit on --fit-target 512"
)

for /f "usebackq delims=" %%H in (`powershell.exe -NoLogo -NoProfile -Command "$sha=[Security.Cryptography.SHA256]::Create();try{$data=[Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($env:LOCALAI_ROOT).ToUpperInvariant());[Console]::Write(([BitConverter]::ToString($sha.ComputeHash($data))).Replace('-','').Substring(0,12))}finally{$sha.Dispose()}"`) do set "ROOT_ID=%%H"
if not defined ROOT_ID goto :HASH_FAILED
set "WEB_PIDFILE=%TEMP%\LocalAI-USB-%ROOT_ID%\server.pid"
if exist "%WEB_PIDFILE%" (
  echo Stopping this USB's website server before loading CLI mode...
  call "%ROOT%STOP AI.bat" <nul
  if errorlevel 1 goto :STOP_FAILED
)

echo.
echo LOCAL AI TERMINAL CHAT
echo Model: %MODEL%
echo Context: %CTX_SIZE% tokens
echo Acceleration: %ACCELERATION%
echo Press Ctrl+C to exit.
echo.

set "PATH=%RUNTIME%;%PATH%"
"%CLI%" --model "%MODEL%" --ctx-size %CTX_SIZE% --conversation --jinja --reasoning auto %GPU_ARGS%
set "LOCALAI_CLI_EXIT=%ERRORLEVEL%"
echo.
if "%LOCALAI_CLI_EXIT%"=="0" (
  echo LocalCLI finished.
) else (
  echo LocalCLI exited with an error.
)
pause
exit /b %LOCALAI_CLI_EXIT%

:HELP
echo Usage: LocalCLI.bat [MODEL.gguf]
echo Starts terminal chat with the shared model. Press Ctrl+C to exit.
exit /b 0

:NO_MODEL
echo ERROR: No readable primary GGUF model was selected.
goto :ERROR_END
:NO_SELECTOR
echo ERROR: The automatic model selector is missing.
goto :ERROR_END
:NO_CLI
echo ERROR: llama-cli was not found for this Windows architecture.
goto :ERROR_END
:UNSUPPORTED
echo ERROR: 32-bit Windows is unsupported.
goto :ERROR_END
:HASH_FAILED
echo ERROR: Could not identify this USB's private runtime state.
goto :ERROR_END
:STOP_FAILED
echo ERROR: The tracked website server could not be safely stopped.
goto :ERROR_END

:ERROR_END
pause
exit /b 1
