param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('on', 'off')]
    [string] $Mode
)

$ErrorActionPreference = 'Stop'
$presetFile = $env:LOCALAI_PRESETFILE
if ([string]::IsNullOrWhiteSpace($presetFile) -or
    -not (Test-Path -LiteralPath $presetFile -PathType Leaf)) {
    throw 'The active LocalAI preset file is unavailable.'
}

$preferenceFile = Join-Path $env:USERPROFILE '.localai-usb-gpu-mode'
[IO.File]::WriteAllText(
    $preferenceFile,
    $Mode + [Environment]::NewLine,
    (New-Object Text.UTF8Encoding($false))
)

$backend = if ($env:LOCALAI_GPU_BACKEND) { $env:LOCALAI_GPU_BACKEND } else { 'CPU' }
$device = if ($env:LOCALAI_GPU_DEVICE) { $env:LOCALAI_GPU_DEVICE } else { '' }
$active = $Mode -eq 'on' -and $backend -ne 'CPU'
$source = [IO.File]::ReadAllLines($presetFile)
$output = New-Object 'Collections.Generic.List[string]'
$inserted = $false
$globalFound = $false

function Add-GpuSettings {
    if ($script:inserted) { return }
    if ($active) {
        $output.Add('gpu-layers = auto')
        if ($device) { $output.Add('device = ' + $device) }
        $output.Add('fit = on')
        $output.Add('fit-target = 512')
    }
    else {
        $output.Add('gpu-layers = 0')
    }
    $script:inserted = $true
}

foreach ($line in $source) {
    if ($line -match '^\[\*\]\s*$') {
        $output.Add($line)
        Add-GpuSettings
        $globalFound = $true
        continue
    }
    if (-not $globalFound -and $line -match '^\[') {
        $output.Add('[*]')
        Add-GpuSettings
        $output.Add('')
        $globalFound = $true
    }
    if ($line -notmatch '^(gpu-layers|device|fit|fit-target)\s*=') {
        $output.Add($line)
    }
}
if (-not $globalFound) {
    $output.Add('')
    $output.Add('[*]')
    Add-GpuSettings
}

$newText = [string]::Join([Environment]::NewLine, $output) + [Environment]::NewLine
$oldText = [IO.File]::ReadAllText($presetFile)
$changed = $newText -cne $oldText
if ($changed) {
    [IO.File]::WriteAllText($presetFile, $newText, (New-Object Text.UTF8Encoding($false)))
}

Write-Output ('changed=' + $changed.ToString().ToLowerInvariant() +
    ' mode=' + $Mode +
    ' active=' + $active.ToString().ToLowerInvariant() +
    ' backend=' + $backend +
    ' device=' + $device)
