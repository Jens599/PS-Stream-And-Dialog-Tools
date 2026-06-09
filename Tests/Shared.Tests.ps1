$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleManifests = @(
    Join-Path $repoRoot 'Add-Path\Add-Path.psd1'
    Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1'
    Join-Path $repoRoot 'ytm-dl\ytm-dl.psd1'
)

$moduleSources = @(
    Join-Path $repoRoot 'Add-Path\Add-Path.psm1'
    Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psm1'
    Join-Path $repoRoot 'ytm-dl\ytm-dl.psm1'
) + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Start-MPVStream\Private') -Filter '*.ps1' | Select-Object -ExpandProperty FullName)

