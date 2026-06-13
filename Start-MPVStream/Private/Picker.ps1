function Select-MPVStreamSearchResult {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $configuredProvider = Normalize-MPVStreamMenuProvider $Config.menuProvider
    $providers = @($configuredProvider, 'fzf', 'ConsoleGuiTools', 'OutConsoleGridView', 'BasicPrompt') | Select-Object -Unique
    $providerToUse = $null

    foreach ($provider in $providers) {
        if (-not (Test-MPVStreamMenuProvider $provider)) {
            if ($provider -eq $configuredProvider) {
                $install = Read-Host "$(Get-MPVStreamMenuProviderLabel $provider) is not installed. Install now? [Y/N]"
                if ($install -match '^(y|yes)$') {
                    Install-MPVStreamMenuProvider $provider
                }
            }

            if (-not (Test-MPVStreamMenuProvider $provider)) { continue }
        }

        $providerToUse = $provider
        break
    }

    if (-not $providerToUse) {
        Write-Warning 'No interactive selector is available. Using first result.'
        return $Items[0]
    }

    switch ($providerToUse) {
        'fzf' { return (Select-MPVStreamSearchResultWithFzf -Items $Items -Title $Title) }
        'ConsoleGuiTools' { return (Select-MPVStreamSearchResultWithConsoleGridView -Items $Items -Title $Title) }
        'OutConsoleGridView' { return (Select-MPVStreamSearchResultWithConsoleGridView -Items $Items -Title $Title) }
        'BasicPrompt' { return (Select-MPVStreamSearchResultWithBasicPrompt -Items $Items -Title $Title) }
    }
}

function Select-MPVStreamMenuIndex {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Options,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $items = for ($i = 0; $i -lt $Options.Count; $i++) {
        $option = $Options[$i]
        if ($option -isnot [string]) {
            [pscustomobject]@{
                Index        = $i
                Title        = $option.Title
                Type         = 'Option'
                Url          = $null
                MenuTitle    = $option.Title
                CurrentValue = $option.CurrentValue
                DefaultValue = $option.DefaultValue
                Tooltip      = $option.Tooltip
            }
            continue
        }

        [pscustomobject]@{
            Index     = $i
            Title     = $option
            Type      = 'Option'
            Url       = $null
            MenuTitle = $option
        }
    }

    $selected = Select-MPVStreamSearchResult -Items @($items) -Title $Title -Config $Config
    if ($null -eq $selected) { return $null }
    return $selected.Index
}

function Select-MPVStreamSearchResultWithFzf {
    param([object[]]$Items, [string]$Title)

    $isOptionMenu = Test-MPVStreamOptionMenu -Items $Items
    $tooltipPath = $null
    $tooltipScriptPath = $null

    $lines = for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($isOptionMenu) {
            Format-MPVStreamOptionLine -Item $Items[$i] -Index ($i + 1)
        } else {
            Format-MPVStreamSearchResultLine -Item $Items[$i] -Index ($i + 1)
        }
    }

    $header = $Title
    $controls = 'Enter select | Esc cancel'
    if (-not $isOptionMenu) {
        $header = @(
            $Title,
            ('{0,-3} {1,-8} {2,-8} {3,12}  {4,-20}  {5}' -f 'No', 'Type', 'Length', 'Views', 'Uploader', 'Title')
        ) -join "`n"
    } elseif (Test-MPVStreamOptionMenuHasValueColumns -Items $Items) {
        $controls = if (Test-MPVStreamOptionMenuHasTooltips -Items $Items) { 'Enter edit/open | Alt-T tooltip | Esc back' } else { 'Enter edit/open | Esc back' }
        $header = @(
            $Title,
            ('{0,-3} {1,-32} {2,-24} {3}' -f 'No', 'Setting', 'Current', 'Default')
        ) -join "`n"
    } else {
        $controls = if (Test-MPVStreamOptionMenuHasTooltips -Items $Items) { 'Enter select | Alt-T tooltip | Esc back' } else { 'Enter select | Esc back' }
    }

    $fzfArguments = @(
        '--height', '55%'
        '--layout', 'reverse'
        '--border', 'rounded'
        '--border-label', " $controls "
        '--border-label-pos', '-2:bottom'
        '--info', 'inline'
        '--cycle'
        '--header', $header
        '--prompt', 'Search> '
        '--pointer', '>'
        '--marker', '+'
    )

    if ($isOptionMenu -and (Test-MPVStreamOptionMenuHasTooltips -Items $Items)) {
        $tooltipPath = [System.IO.Path]::GetTempFileName()
        $tooltipScriptPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.ps1')
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $tooltip = Get-MPVStreamDisplayValue $Items[$i].Tooltip
            "{0:00}`t{1}" -f ($i + 1), $tooltip | Add-Content -LiteralPath $tooltipPath -Encoding UTF8
        }

        @'
param(
    [string]$TooltipPath,
    [string]$Index
)

if (-not (Test-Path -LiteralPath $TooltipPath -PathType Leaf)) { return }

Get-Content -LiteralPath $TooltipPath | ForEach-Object {
    $parts = $_ -split "`t", 2
    if ($parts.Count -eq 2 -and $parts[0] -eq $Index) {
        $parts[1]
        return
    }
}
'@ | Set-Content -LiteralPath $tooltipScriptPath -Encoding UTF8

        $previewCommand = 'pwsh -NoProfile -ExecutionPolicy Bypass -File "' + $tooltipScriptPath + '" "' + $tooltipPath + '" {1}'
        $fzfArguments += @('--preview', $previewCommand, '--preview-window', 'down:4:hidden:wrap', '--bind', 'alt-t:toggle-preview')
    }

    try {
        $selected = $lines | fzf @fzfArguments
    } finally {
        if ($tooltipPath -and (Test-Path -LiteralPath $tooltipPath -PathType Leaf)) {
            Remove-Item -LiteralPath $tooltipPath -Force -ErrorAction SilentlyContinue
        }
        if ($tooltipScriptPath -and (Test-Path -LiteralPath $tooltipScriptPath -PathType Leaf)) {
            Remove-Item -LiteralPath $tooltipScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $selected) {
        $global:LASTEXITCODE = 0
        return $null
    }

    if ($selected -match '^(\d+)\s') {
        return $Items[[int]$Matches[1] - 1]
    }

    return $null
}

function Select-MPVStreamSearchResultWithConsoleGridView {
    param([object[]]$Items, [string]$Title)

    $isOptionMenu = Test-MPVStreamOptionMenu -Items $Items

    $gridItems = for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($isOptionMenu) {
            $gridItem = [ordered]@{
                Index = $i
                Title = $Items[$i].Title
            }

            if (Test-MPVStreamOptionMenuHasValueColumns -Items $Items) {
                $gridItem.Current = Get-MPVStreamDisplayValue $Items[$i].CurrentValue
                $gridItem.Default = Get-MPVStreamDisplayValue $Items[$i].DefaultValue
            }

            [pscustomobject]$gridItem
            continue
        }

        [pscustomobject]@{
            Index    = $i
            Type     = $Items[$i].Type
            Length   = Get-MPVStreamDisplayValue $Items[$i].Duration
            Views    = Format-MPVStreamViewCount $Items[$i].ViewCount
            Uploader = Get-MPVStreamDisplayValue $Items[$i].Uploader
            Title    = $Items[$i].Title
            Url      = $Items[$i].Url
        }
    }

    $selected = $gridItems | Out-ConsoleGridView -Title $Title -OutputMode Single
    if ($null -eq $selected) { return $null }
    return $Items[$selected.Index]
}

function Select-MPVStreamSearchResultWithBasicPrompt {
    param([object[]]$Items, [string]$Title)

    Write-Host "`n$Title" -ForegroundColor Cyan
    $isOptionMenu = Test-MPVStreamOptionMenu -Items $Items

    if (-not $isOptionMenu) {
        Write-Host ('  {0,-3} {1,-8} {2,-8} {3,12}  {4,-20}  {5}' -f 'No', 'Type', 'Length', 'Views', 'Uploader', 'Title') -ForegroundColor DarkGray
    } elseif (Test-MPVStreamOptionMenuHasValueColumns -Items $Items) {
        Write-Host ('  {0,-3} {1,-32} {2,-24} {3}' -f 'No', 'Setting', 'Current', 'Default') -ForegroundColor DarkGray
    }

    for ($i = 0; $i -lt $Items.Count; $i++) {
        if ($isOptionMenu) {
            Write-Host ('  {0}' -f (Format-MPVStreamOptionLine -Item $Items[$i] -Index ($i + 1)))
        } else {
            Write-Host ('  {0}' -f (Format-MPVStreamSearchResultLine -Item $Items[$i] -Index ($i + 1)))
        }
    }

    $answer = Read-Host 'Select number or press Enter to cancel'
    if ([string]::IsNullOrWhiteSpace($answer)) { return $null }

    $index = 0
    if ([int]::TryParse($answer, [ref]$index) -and $index -ge 1 -and $index -le $Items.Count) {
        return $Items[$index - 1]
    }

    Write-Warning 'Invalid selection.'
    return $null
}

function Test-MPVStreamOptionMenu {
    param([object[]]$Items)

    if ($Items.Count -eq 0) { return $false }
    foreach ($item in $Items) {
        if ($item.Type -ne 'Option') { return $false }
    }

    return $true
}

function Format-MPVStreamOptionLine {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Item,

        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    if (Test-MPVStreamOptionMenuHasValueColumns -Items @($Item)) {
        return '{0:00}  {1,-32} {2,-24} {3}' -f $Index, (Limit-MPVStreamText -Text $Item.Title -Length 32), (Limit-MPVStreamText -Text (Get-MPVStreamDisplayValue $Item.CurrentValue) -Length 24), (Get-MPVStreamDisplayValue $Item.DefaultValue)
    }

    '{0:00}  {1}' -f $Index, (Get-MPVStreamDisplayValue $Item.Title)
}

function Test-MPVStreamOptionMenuHasValueColumns {
    param([object[]]$Items)

    foreach ($item in $Items) {
        if (($item.PSObject.Properties.Name -contains 'CurrentValue') -or ($item.PSObject.Properties.Name -contains 'DefaultValue')) {
            return $true
        }
    }

    return $false
}

function Test-MPVStreamOptionMenuHasTooltips {
    param([object[]]$Items)

    foreach ($item in $Items) {
        if (($item.PSObject.Properties.Name -contains 'Tooltip') -and -not [string]::IsNullOrWhiteSpace([string]$item.Tooltip)) {
            return $true
        }
    }

    return $false
}

function Format-MPVStreamSearchResultLine {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Item,

        [Parameter(Mandatory = $true)]
        [int]$Index
    )

    $type = Get-MPVStreamDisplayValue $Item.Type
    $duration = Get-MPVStreamDisplayValue $Item.Duration
    $views = Format-MPVStreamViewCount $Item.ViewCount
    $uploader = Limit-MPVStreamText -Text (Get-MPVStreamDisplayValue $Item.Uploader) -Length 20
    $title = Get-MPVStreamDisplayValue $Item.Title

    if ($type -eq '-') {
        $type = 'Option'
    }

    '{0:00}  {1,-8} {2,-8} {3,12}  {4,-20}  {5}' -f $Index, $type, $duration, $views, $uploader, $title
}

function Get-MPVStreamDisplayValue {
    param([object]$Value)

    if ($null -eq $Value) { return '-' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq 'NA') { return '-' }
    return $text
}

function Format-MPVStreamViewCount {
    param([object]$ViewCount)

    $text = Get-MPVStreamDisplayValue $ViewCount
    if ($text -eq '-') { return '-' }

    $viewNumber = 0L
    if ([long]::TryParse($text, [ref]$viewNumber)) {
        return ('{0:N0}' -f $viewNumber)
    }

    return $text
}

function Limit-MPVStreamText {
    param(
        [object]$Text,
        [int]$Length = 20
    )

    $value = Get-MPVStreamDisplayValue $Text
    if ($value.Length -le $Length) { return $value }
    if ($Length -le 1) { return $value.Substring(0, $Length) }
    if ($Length -le 3) { return $value.Substring(0, $Length) }
    return $value.Substring(0, $Length - 3) + '...'
}
