@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "ROOT=%~dp0"
set "LOCALAI_ROOT=%ROOT%"

for /f "usebackq delims=" %%H in (`powershell.exe -NoLogo -NoProfile -Command "$sha=[Security.Cryptography.SHA256]::Create();try{$data=[Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($env:LOCALAI_ROOT).ToUpperInvariant());[Console]::Write(([BitConverter]::ToString($sha.ComputeHash($data))).Replace('-','').Substring(0,12))}finally{$sha.Dispose()}"`) do set "ROOT_ID=%%H"
if not defined ROOT_ID goto :HASH_FAILED
set "WORK_BASE=%TEMP%\LocalAI-USB-%ROOT_ID%"
if not exist "%WORK_BASE%" mkdir "%WORK_BASE%" >nul 2>&1
if not exist "%WORK_BASE%" goto :WORK_FAILED

set "MODEL_DIR=%ROOT%LocalAI\models"
set "MODEL_SELECTOR=%ROOT%LocalAI\runtime\select-default-model.bat"
set "DEFAULT_MODEL="
if not exist "%MODEL_SELECTOR%" goto :NO_SELECTOR
for /f "usebackq delims=" %%M in (`call "%MODEL_SELECTOR%" "%MODEL_DIR%"`) do set "DEFAULT_MODEL=%%M"
set "WEB=%ROOT%LocalAI\web"
set "QWEN25_TEMPLATE=%ROOT%LocalAI\templates\Qwen-Qwen2.5-Instruct.jinja"
set "PIDFILE=%WORK_BASE%\server.pid"
set "OUTLOG=%WORK_BASE%\server.log"
set "ERRLOG=%WORK_BASE%\server-error.log"
set "PRESETFILE=%WORK_BASE%\device-models.ini"
set "CACHE_DIR=%WORK_BASE%\cache"
set "CTXFILE=%WORK_BASE%\context.txt"
set "URL=http://127.0.0.1:8080"

if not defined DEFAULT_MODEL goto :NO_MODEL
if not exist "%DEFAULT_MODEL%" goto :NO_MODEL
if not exist "%WEB%\index.html" goto :NO_WEB
if not exist "%WEB%\ui-config.json" goto :NO_WEB
if not exist "%QWEN25_TEMPLATE%" goto :NO_WEB
if /I "%PROCESSOR_ARCHITECTURE%"=="x86" if "%PROCESSOR_ARCHITEW6432%"=="" goto :UNSUPPORTED
set "RUNTIME=%ROOT%LocalAI\windows-x64"
set "UI_BUNDLE=Bz3TSVKB"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "RUNTIME=%ROOT%LocalAI\windows-arm64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "UI_BUNDLE=KqEThohO"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "RUNTIME=%ROOT%LocalAI\windows-arm64"
if /I "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "UI_BUNDLE=KqEThohO"
set "SERVER=%RUNTIME%\llama-server.exe"
if not exist "%SERVER%" goto :NO_SERVER

set "GPU_BACKEND=CPU"
set "GPU_DEVICE="
set "ACCELERATION=CPU compatibility mode"
if exist "%ROOT%LocalAI\runtime\select-windows-gpu.ps1" (
  for /f "tokens=1,2 delims=|" %%A in ('powershell.exe -NoLogo -NoProfile -File "%ROOT%LocalAI\runtime\select-windows-gpu.ps1" -Root "%ROOT%"') do (
    set "GPU_BACKEND=%%A"
    set "GPU_DEVICE=%%B"
  )
)
if /I "%GPU_BACKEND%"=="CUDA" set "ACCELERATION=NVIDIA CUDA GPU offload with automatic CPU/RAM fallback"
if /I "%GPU_BACKEND%"=="VULKAN" set "ACCELERATION=Vulkan GPU offload with automatic CPU/RAM fallback"
if /I "%GPU_BACKEND%"=="OPENCL" set "ACCELERATION=Qualcomm Adreno OpenCL GPU offload with automatic CPU/RAM fallback"

set "LOCALAI_SERVER=%SERVER%"
set "LOCALAI_MODEL_DIR=%MODEL_DIR%"
set "LOCALAI_WEB=%WEB%"
set "LOCALAI_UI_CONFIG=%WEB%\ui-config.json"
set "LOCALAI_QWEN25_TEMPLATE=%QWEN25_TEMPLATE%"
set "LOCALAI_USB_ROOT=%ROOT%"
set "LOCALAI_WORK_BASE=%WORK_BASE%"
set "LOCALAI_PIDFILE=%PIDFILE%"
set "LOCALAI_OUTLOG=%OUTLOG%"
set "LOCALAI_ERRLOG=%ERRLOG%"
set "LOCALAI_PRESETFILE=%PRESETFILE%"
set "LOCALAI_CACHE_DIR=%CACHE_DIR%"
set "LOCALAI_CTXFILE=%CTXFILE%"
set "LOCALAI_GPU_BACKEND=%GPU_BACKEND%"
set "LOCALAI_GPU_DEVICE=%GPU_DEVICE%"

powershell.exe -NoLogo -NoProfile -Command "if(Test-Path -LiteralPath $env:LOCALAI_PIDFILE){try{$lines=[IO.File]::ReadAllLines($env:LOCALAI_PIDFILE);if($lines.Count-lt 2){throw 'Incomplete PID record.'};$serverPid=[int]$lines[0];$ticks=[int64]$lines[1];$c=Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId='+$serverPid) -ErrorAction SilentlyContinue;if($null-eq$c){Remove-Item -LiteralPath $env:LOCALAI_PIDFILE -Force -ErrorAction SilentlyContinue;exit 0};$actual=[IO.Path]::GetFullPath($c.ExecutablePath);$x64=[IO.Path]::GetFullPath((Join-Path $env:LOCALAI_ROOT 'LocalAI\windows-x64\llama-server.exe'));$arm=[IO.Path]::GetFullPath((Join-Path $env:LOCALAI_ROOT 'LocalAI\windows-arm64\llama-server.exe'));$modelDir=[IO.Path]::GetFullPath($env:LOCALAI_MODEL_DIR);$sameStart=$c.CreationDate.ToUniversalTime().Ticks-eq$ticks;$sameCommand=$c.CommandLine.Contains('--models-dir')-and$c.CommandLine.Contains($modelDir)-and$c.CommandLine.Contains('--host 127.0.0.1')-and$c.CommandLine.Contains('--port 8080');if((($actual-eq$x64)-or($actual-eq$arm))-and$sameStart-and$sameCommand){exit 10};throw 'Tracked PID belongs to another process.'}catch{Write-Error $_;exit 11}}"
if %errorlevel% EQU 10 goto :ALREADY_RUNNING
if errorlevel 1 goto :PID_CHECK_FAILED

powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';$ctx=4096;$contextPreference=Join-Path $env:USERPROFILE '.localai-usb-context-size';if(Test-Path -LiteralPath $contextPreference -PathType Leaf){$candidate=[IO.File]::ReadAllText($contextPreference).Trim();$parsed=0;if([int]::TryParse($candidate,[ref]$parsed)-and$parsed-ge512-and$parsed-le131072){$ctx=$parsed}};$lines=New-Object 'Collections.Generic.List[string]';$lines.Add('version = 1');$lines.Add('');$lines.Add('[*]');$lines.Add('ctx-size = '+$ctx);if($env:LOCALAI_GPU_BACKEND-eq'CPU'){$lines.Add('gpu-layers = 0')}else{$lines.Add('gpu-layers = auto');if($env:LOCALAI_GPU_DEVICE){$lines.Add('device = '+$env:LOCALAI_GPU_DEVICE)};$lines.Add('fit = on');$lines.Add('fit-target = 512')};function Add-LocalModel([string]$label,[IO.FileInfo]$file,[IO.FileInfo]$projector){$safe=[regex]::Replace($file.BaseName,'[^A-Za-z0-9._-]','-');$lines.Add('');$lines.Add('[Device-'+$label+'-'+$safe+']');$lines.Add('model = '+$file.FullName);if($file.Name-match'(?i)qwen2[._-]?5.*instruct'-and$file.Name-notmatch'(?i)qwen2[._-]?5.*vl'){$lines.Add('chat-template-file = '+$env:LOCALAI_QWEN25_TEMPLATE)};if($null-ne$projector){$lines.Add('mmproj = '+$projector.FullName)}};$sources=@(@{Label='Library';Path=(Join-Path $env:USERPROFILE 'LocalAI-Models')},@{Label='Desktop';Path=(Join-Path $env:USERPROFILE 'Desktop')},@{Label='Downloads';Path=(Join-Path $env:USERPROFILE 'Downloads')});foreach($source in $sources){if(Test-Path -LiteralPath $source.Path -PathType Container){Get-ChildItem -LiteralPath $source.Path -File|Where-Object{$_.Extension-ieq'.gguf'-and$_.Name-notmatch'(?i)^mmproj'-and$_.Name-notmatch'(?i)-000(0[2-9]|[1-9][0-9])-of-'}|Sort-Object FullName|ForEach-Object{Add-LocalModel $source.Label $_ $null}}};$library=Join-Path $env:USERPROFILE 'LocalAI-Models';if(Test-Path -LiteralPath $library -PathType Container){Get-ChildItem -LiteralPath $library -Directory|Sort-Object FullName|ForEach-Object{$files=@(Get-ChildItem -LiteralPath $_.FullName -File|Where-Object{$_.Extension-ieq'.gguf'}|Sort-Object FullName);$primary=$files|Where-Object{$_.Name-notmatch'(?i)^mmproj'-and$_.Name-notmatch'(?i)-000(0[2-9]|[1-9][0-9])-of-'}|Select-Object -First 1;$projector=$files|Where-Object{$_.Name-match'(?i)^mmproj'}|Select-Object -First 1;if($null-ne$primary){Add-LocalModel 'Bundle' $primary $projector}}};[IO.File]::WriteAllLines($env:LOCALAI_PRESETFILE,$lines,(New-Object Text.UTF8Encoding($false)));New-Item -ItemType Directory -Force -Path $env:LOCALAI_CACHE_DIR|Out-Null;$env:LLAMA_CACHE=$env:LOCALAI_CACHE_DIR;$serverArgs=@('--models-dir',('"'+$env:LOCALAI_MODEL_DIR+'"'),'--models-preset',('"'+$env:LOCALAI_PRESETFILE+'"'),'--models-max','1','--models-autoload','--parallel','1','--cache-ram','256','--no-cache-idle-slots','--host','127.0.0.1','--port','8080','--context-shift','--jinja','--reasoning','off','--reasoning-format','deepseek','--tools','all','--path',('"'+$env:LOCALAI_WEB+'"'),'--ui-config-file',('"'+$env:LOCALAI_UI_CONFIG+'"'));$p=$null;try{$p=Start-Process -FilePath $env:LOCALAI_SERVER -WorkingDirectory $env:USERPROFILE -ArgumentList $serverArgs -RedirectStandardOutput $env:LOCALAI_OUTLOG -RedirectStandardError $env:LOCALAI_ERRLOG -PassThru;$c=$null;for($i=0;$i-lt 20-and$null-eq$c;$i++){Start-Sleep -Milliseconds 50;$c=Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId='+$p.Id) -ErrorAction SilentlyContinue};if($null-eq$c){throw 'Could not record process creation identity.'};[IO.File]::WriteAllLines($env:LOCALAI_PIDFILE,@($p.Id.ToString(),$c.CreationDate.ToUniversalTime().Ticks.ToString()),(New-Object Text.UTF8Encoding($false)));[IO.File]::WriteAllText($env:LOCALAI_CTXFILE,$ctx.ToString())}catch{if($null-ne$p-and-not$p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue};Remove-Item -LiteralPath $env:LOCALAI_PIDFILE -Force -ErrorAction SilentlyContinue;throw}"
if errorlevel 1 goto :START_FAILED
set /p SERVERPID=<"%PIDFILE%"

set /a WAITCOUNT=0
:WAIT_READY
powershell.exe -NoLogo -NoProfile -Command "try{$r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 1 -Uri '%URL%/props';if($r.StatusCode-eq 200){exit 0}}catch{};exit 1" >nul 2>&1
if not errorlevel 1 goto :READY
tasklist /FI "PID eq %SERVERPID%" /NH 2>nul | findstr /R /C:"[ ]%SERVERPID%[ ]" >nul || goto :SERVER_EXITED
set /a WAITCOUNT+=1
if %WAITCOUNT% GEQ 300 goto :TIMEOUT
timeout /t 1 /nobreak >nul
goto :WAIT_READY

:READY
powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';$lines=[IO.File]::ReadAllLines($env:LOCALAI_PIDFILE);$serverPid=[int]$lines[0];$ticks=[int64]$lines[1];$c=Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId='+$serverPid) -ErrorAction Stop;$expected=[IO.Path]::GetFullPath($env:LOCALAI_SERVER);$modelDir=[IO.Path]::GetFullPath($env:LOCALAI_MODEL_DIR);if([IO.Path]::GetFullPath($c.ExecutablePath)-ne$expected-or$c.CreationDate.ToUniversalTime().Ticks-ne$ticks-or-not$c.CommandLine.Contains('--models-dir')-or-not$c.CommandLine.Contains($modelDir)-or-not$c.CommandLine.Contains('--host 127.0.0.1')-or-not$c.CommandLine.Contains('--port 8080')){throw 'Server identity changed during startup.'}" >nul 2>&1
if errorlevel 1 (
  echo ERROR: The healthy port did not belong to the server started by this USB.
  call :CLEAN_FAILED_START
  goto :ERROR_END
)
echo.
echo LOCAL AI READY
echo DO NOT REMOVE USB WHILE AI IS RUNNING
echo Choose a model in the website. Only one model is kept in RAM.
echo Models: USB plus LocalAI-Models, Desktop, and Downloads on this PC.
echo The website asks before tools run unless you choose an Always allow option.
echo Acceleration: %ACCELERATION%
if exist "%CTXFILE%" set /p CTX_SIZE=<"%CTXFILE%"
if defined CTX_SIZE echo Context: %CTX_SIZE% tokens with automatic local conversation compaction
start "" "%URL%/?launch=%RANDOM%%RANDOM%&bundle=%UI_BUNDLE%"
echo.
echo Run STOP AI.bat before ejecting the USB.
pause
exit /b 0

:ALREADY_RUNNING
echo LOCAL AI is already running from this USB.
echo DO NOT REMOVE USB WHILE AI IS RUNNING
start "" "%URL%/?launch=%RANDOM%%RANDOM%&bundle=%UI_BUNDLE%"
pause
exit /b 0

:NO_MODEL
echo ERROR: No readable primary GGUF model was found in "%MODEL_DIR%".
goto :ERROR_END
:NO_SELECTOR
echo ERROR: The automatic model selector is missing: "%MODEL_SELECTOR%"
goto :ERROR_END
:NO_SERVER
echo ERROR: No compatible Windows llama-server was found.
goto :ERROR_END
:NO_WEB
echo ERROR: Offline agent interface not found: "%WEB%\index.html"
goto :ERROR_END
:UNSUPPORTED
echo ERROR: 32-bit Windows is unsupported. Windows x86-64 or ARM64 is required.
goto :ERROR_END
:HASH_FAILED
echo ERROR: Could not create this USB's private runtime identifier.
goto :ERROR_END
:WORK_FAILED
echo ERROR: Could not create the private runtime directory in %%TEMP%%.
goto :ERROR_END
:START_FAILED
echo ERROR: Could not start the LocalAI model router. Check:
echo   %ERRLOG%
goto :ERROR_END
:PID_CHECK_FAILED
echo ERROR: The existing PID record does not safely identify this USB's server.
echo Inspect this stale record only after confirming no LocalAI server is running:
echo   %PIDFILE%
goto :ERROR_END
:SERVER_EXITED
del /q "%PIDFILE%" >nul 2>&1
echo ERROR: llama-server exited before becoming ready. Port 8080 may already be in use.
echo Check: %ERRLOG%
goto :ERROR_END
:TIMEOUT
echo ERROR: Timed out waiting for llama-server. Stopping the tracked server...
call :CLEAN_FAILED_START
if errorlevel 1 echo WARNING: The tracked server could not be safely stopped. Do not eject the USB yet.
goto :ERROR_END

:ERROR_END
echo The terminal will stay open so you can read this error.
pause
exit /b 1

:CLEAN_FAILED_START
powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';$lines=[IO.File]::ReadAllLines($env:LOCALAI_PIDFILE);if($lines.Count-lt 2){throw 'Incomplete PID record.'};$serverPid=[int]$lines[0];$ticks=[int64]$lines[1];$c=Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId='+$serverPid) -ErrorAction SilentlyContinue;if($null-ne$c){$actual=[IO.Path]::GetFullPath($c.ExecutablePath);$expected=[IO.Path]::GetFullPath($env:LOCALAI_SERVER);$modelDir=[IO.Path]::GetFullPath($env:LOCALAI_MODEL_DIR);if($actual-ne$expected-or$c.CreationDate.ToUniversalTime().Ticks-ne$ticks-or-not$c.CommandLine.Contains('--models-dir')-or-not$c.CommandLine.Contains($modelDir)){throw 'PID identity mismatch; nothing was stopped.'};Stop-Process -Id $serverPid -Force};Remove-Item -LiteralPath $env:LOCALAI_PIDFILE -Force -ErrorAction SilentlyContinue"
exit /b %errorlevel%
