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
        [string[]]$Options,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $items = for ($i = 0; $i -lt $Options.Count; $i++) {
        [pscustomobject]@{
            Index     = $i
            Title     = $Options[$i]
            Type      = 'Option'
            Url       = $null
            MenuTitle = $Options[$i]
        }
    }

    $selected = Select-MPVStreamSearchResult -Items @($items) -Title $Title -Config $Config
    if ($null -eq $selected) { return $null }
    return $selected.Index
}

function Select-MPVStreamSearchResultWithFzf {
    param([object[]]$Items, [string]$Title)

    $lines = for ($i = 0; $i -lt $Items.Count; $i++) {
        Format-MPVStreamSearchResultLine -Item $Items[$i] -Index ($i + 1)
    }

    $header = @(
        $Title,
        ('{0,-3} {1,-8} {2,-8} {3,12}  {4,-20}  {5}' -f 'No', 'Type', 'Length', 'Views', 'Uploader', 'Title')
    ) -join "`n"

    $selected = $lines | fzf `
        --height 55% `
        --layout reverse `
        --border rounded `
        --info inline `
        --header $header `
        --prompt 'Search> ' `
        --pointer '>' `
        --marker '+'
    if (-not $selected) { return $null }

    if ($selected -match '^(\d+)\s') {
        return $Items[[int]$Matches[1] - 1]
    }

    return $null
}

function Select-MPVStreamSearchResultWithConsoleGridView {
    param([object[]]$Items, [string]$Title)

    $gridItems = for ($i = 0; $i -lt $Items.Count; $i++) {
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
    Write-Host ('  {0,-3} {1,-8} {2,-8} {3,12}  {4,-20}  {5}' -f 'No', 'Type', 'Length', 'Views', 'Uploader', 'Title') -ForegroundColor DarkGray
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ('  {0}' -f (Format-MPVStreamSearchResultLine -Item $Items[$i] -Index ($i + 1)))
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
