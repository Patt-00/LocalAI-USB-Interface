param(
    [Parameter(Mandatory = $true)]
    [string] $Root
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-LlamaDevices([string] $RuntimeDirectory) {
    $server = Join-Path $RuntimeDirectory 'llama-server.exe'
    if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
        return ''
    }

    $savedPath = $env:PATH
    try {
        $env:PATH = $RuntimeDirectory + ';' + $savedPath
        return ((& $server --list-devices 2>&1) | Out-String)
    }
    catch {
        return ''
    }
    finally {
        $env:PATH = $savedPath
    }
}

$preferenceFile = Join-Path $env:USERPROFILE '.localai-usb-gpu-mode'
$savedMode = if (Test-Path -LiteralPath $preferenceFile -PathType Leaf) {
    [IO.File]::ReadAllText($preferenceFile).Trim().ToLowerInvariant()
} else {
    'on'
}

if ($env:LOCALAI_FORCE_CPU -eq '1' -or $savedMode -eq 'off') {
    Write-Output 'CPU|'
    exit 0
}

$isArm64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') -or
    ($env:PROCESSOR_ARCHITEW6432 -eq 'ARM64')

if ($isArm64) {
    $runtime = Join-Path $Root 'LocalAI\windows-arm64'
    $devices = Get-LlamaDevices $runtime
    $openClMatch = [regex]::Match($devices, '(?im)^\s*(OpenCL\d+)\s*:\s*(.+)$')
    if ($openClMatch.Success) {
        Write-Output ('OPENCL|' + $openClMatch.Groups[1].Value)
        exit 0
    }

    Write-Output 'CPU|'
    exit 0
}

$runtime = Join-Path $Root 'LocalAI\windows-x64'
$devices = Get-LlamaDevices $runtime
$cudaMatch = [regex]::Match($devices, '(?im)^\s*(CUDA\d+)\s*:\s*(.+)$')
if ($cudaMatch.Success) {
    Write-Output ('CUDA|' + $cudaMatch.Groups[1].Value)
    exit 0
}

$vulkanMatches = [regex]::Matches($devices, '(?im)^\s*(Vulkan\d+)\s*:\s*(.+)$')
foreach ($match in $vulkanMatches) {
    $description = $match.Groups[2].Value
    if ($description -notmatch '(?i)llvmpipe|swiftshader|software|microsoft basic render') {
        Write-Output ('VULKAN|' + $match.Groups[1].Value)
        exit 0
    }
}

Write-Output 'CPU|'
