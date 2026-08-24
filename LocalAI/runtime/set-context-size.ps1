param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(512, 131072)]
    [int] $ContextSize
)

$ErrorActionPreference = 'Stop'
$presetFile = $env:LOCALAI_PRESETFILE
if ([string]::IsNullOrWhiteSpace($presetFile) -or
    -not (Test-Path -LiteralPath $presetFile -PathType Leaf)) {
    throw 'The active LocalAI preset file is unavailable.'
}

$preferenceFile = Join-Path $env:USERPROFILE '.localai-usb-context-size'
[IO.File]::WriteAllText(
    $preferenceFile,
    $ContextSize.ToString() + [Environment]::NewLine,
    (New-Object Text.UTF8Encoding($false))
)

$source = [IO.File]::ReadAllLines($presetFile)
$output = New-Object 'Collections.Generic.List[string]'
$inserted = $false
$globalFound = $false

function Add-ContextSize {
    if ($script:inserted) { return }
    $output.Add('ctx-size = ' + $ContextSize)
    $script:inserted = $true
}

foreach ($line in $source) {
    if ($line -match '^\[\*\]\s*$') {
        $output.Add($line)
        Add-ContextSize
        $globalFound = $true
        continue
    }
    if (-not $globalFound -and $line -match '^\[') {
        $output.Add('[*]')
        Add-ContextSize
        $output.Add('')
        $globalFound = $true
    }
    if ($line -notmatch '^ctx-size\s*=') { $output.Add($line) }
}
if (-not $globalFound) {
    $output.Add('')
    $output.Add('[*]')
    Add-ContextSize
}

$newText = [string]::Join([Environment]::NewLine, $output) + [Environment]::NewLine
$oldText = [IO.File]::ReadAllText($presetFile)
$changed = $newText -cne $oldText
if ($changed) {
    [IO.File]::WriteAllText($presetFile, $newText, (New-Object Text.UTF8Encoding($false)))
}

Write-Output ('changed=' + $changed.ToString().ToLowerInvariant() +
    ' context=' + $ContextSize +
    ' restart=false')
