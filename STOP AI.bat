@echo off
setlocal EnableExtensions
cd /d "%~dp0"
set "ROOT=%~dp0"
set "LOCALAI_ROOT=%ROOT%"
for /f "usebackq delims=" %%H in (`powershell.exe -NoLogo -NoProfile -Command "$sha=[Security.Cryptography.SHA256]::Create();try{$data=[Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($env:LOCALAI_ROOT).ToUpperInvariant());[Console]::Write(([BitConverter]::ToString($sha.ComputeHash($data))).Replace('-','').Substring(0,12))}finally{$sha.Dispose()}"`) do set "ROOT_ID=%%H"
if not defined ROOT_ID goto :HASH_FAILED
set "WORK_BASE=%TEMP%\LocalAI-USB-%ROOT_ID%"
set "PIDFILE=%WORK_BASE%\server.pid"
if not exist "%PIDFILE%" (
  echo No LOCAL AI PID record was found. Nothing was stopped.
  pause
  exit /b 0
)
set "LOCALAI_WORK_BASE=%WORK_BASE%"
set "LOCALAI_PIDFILE=%PIDFILE%"
set "LOCALAI_MODEL_DIR=%ROOT%LocalAI\models"
set "LOCALAI_PRESETFILE=%WORK_BASE%\device-models.ini"
set "LOCALAI_CACHE_DIR=%WORK_BASE%\cache"
set "LOCALAI_CTXFILE=%WORK_BASE%\context.txt"
set "LOCALAI_OUTLOG=%WORK_BASE%\server.log"
set "LOCALAI_ERRLOG=%WORK_BASE%\server-error.log"

powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop';$lines=[IO.File]::ReadAllLines($env:LOCALAI_PIDFILE);if($lines.Count-lt 2){throw 'Incomplete PID record.'};$serverPid=[int]$lines[0];$ticks=[int64]$lines[1];$c=Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId='+$serverPid) -ErrorAction SilentlyContinue;if($null-eq$c){Remove-Item -LiteralPath $env:LOCALAI_PIDFILE -Force -ErrorAction SilentlyContinue;exit 0};$actual=[IO.Path]::GetFullPath($c.ExecutablePath);$x64=[IO.Path]::GetFullPath((Join-Path $env:LOCALAI_ROOT 'LocalAI\windows-x64\llama-server.exe'));$arm=[IO.Path]::GetFullPath((Join-Path $env:LOCALAI_ROOT 'LocalAI\windows-arm64\llama-server.exe'));$modelDir=[IO.Path]::GetFullPath($env:LOCALAI_MODEL_DIR);if(($actual-ne$x64)-and($actual-ne$arm)){throw 'Executable path mismatch; nothing was stopped.'};if($c.CreationDate.ToUniversalTime().Ticks-ne$ticks){throw 'PID was reused by another process; nothing was stopped.'};if(-not$c.CommandLine.Contains('--models-dir')-or-not$c.CommandLine.Contains($modelDir)-or-not$c.CommandLine.Contains('--host 127.0.0.1')-or-not$c.CommandLine.Contains('--port 8080')){throw 'Command line mismatch; nothing was stopped.'};try{$models=(Invoke-RestMethod -TimeoutSec 2 -Uri 'http://127.0.0.1:8080/models').data;foreach($model in $models){if($model.status.value-ne'unloaded'){Invoke-RestMethod -Method Post -TimeoutSec 3 -Uri 'http://127.0.0.1:8080/models/unload' -ContentType 'application/json' -Body (@{model=$model.id}|ConvertTo-Json -Compress)|Out-Null}};for($i=0;$i-lt 40;$i++){Start-Sleep -Milliseconds 250;$active=(Invoke-RestMethod -TimeoutSec 2 -Uri 'http://127.0.0.1:8080/models').data|Where-Object{$_.status.value-ne'unloaded'};if(-not$active){break}}}catch{};Stop-Process -Id $serverPid;for($i=0;$i-lt 40;$i++){Start-Sleep -Milliseconds 250;if($null-eq(Get-Process -Id $serverPid -ErrorAction SilentlyContinue)){break}};if($null-ne(Get-Process -Id $serverPid -ErrorAction SilentlyContinue)){Stop-Process -Id $serverPid -Force};Remove-Item -LiteralPath $env:LOCALAI_PIDFILE,$env:LOCALAI_PRESETFILE,$env:LOCALAI_CTXFILE -Force -ErrorAction SilentlyContinue;if((Split-Path -Leaf $env:LOCALAI_CACHE_DIR)-eq'cache'-and(Split-Path -Parent $env:LOCALAI_CACHE_DIR)-eq$env:LOCALAI_WORK_BASE){Remove-Item -LiteralPath $env:LOCALAI_CACHE_DIR -Recurse -Force -ErrorAction SilentlyContinue}"
if errorlevel 1 (
  echo ERROR: The tracked process could not be safely stopped.
  pause
  exit /b 1
)
echo LOCAL AI stopped. It is now safe to eject the USB.
pause
exit /b 0

:HASH_FAILED
echo ERROR: Could not identify this USB's private runtime state.
pause
exit /b 1
