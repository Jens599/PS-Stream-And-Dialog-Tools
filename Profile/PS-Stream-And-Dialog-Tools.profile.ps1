# Dot-source this file from your PowerShell profile to load every module in this repository.

$projectRoot = Split-Path -Parent $PSScriptRoot
$moduleManifests = @(
    Join-Path $projectRoot 'Add-Path\Add-Path.psd1'
    Join-Path $projectRoot 'Start-MPVStream\Start-MPVStream.psd1'
    Join-Path $projectRoot 'ytm-dl\ytm-dl.psd1'
)

foreach ($manifest in $moduleManifests) {
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        Import-Module $manifest -Force -ErrorAction Stop
    }
    else {
        Write-Warning "Module manifest not found: $manifest"
    }
}
