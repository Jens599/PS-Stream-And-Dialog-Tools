function Get-MPVStreamHistoryPath {
    Join-Path (Split-Path -Parent (Get-MPVStreamConfigPath)) 'history.json'
}

function Read-MPVStreamHistory {
    $historyPath = Get-MPVStreamHistoryPath
    if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        return @()
    }

    try {
        return @(Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json)
    } catch {
        Write-Warning "Failed to read history file: $historyPath"
        return @()
    }
}

function Save-MPVStreamHistory {
    param([object[]]$History)

    $historyPath = Get-MPVStreamHistoryPath
    $historyDir = Split-Path -Parent $historyPath
    if (-not (Test-Path -LiteralPath $historyDir -PathType Container)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }

    @($History) | ConvertTo-Json | Out-File -LiteralPath $historyPath -Encoding UTF8
}

function Add-MPVStreamHistoryItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [string]$Title,

        [string]$Type = 'Direct'
    )

    if ([string]::IsNullOrWhiteSpace($Url)) { return }

    $history = @(Read-MPVStreamHistory | Where-Object { $_.Url -ne $Url })
    $item = [pscustomobject]@{
        Title     = if ($Title) { $Title } else { $Url }
        Type      = if ($Type) { $Type } else { 'Direct' }
        Url       = $Url
        PlayedAt  = (Get-Date).ToString('o')
        MenuTitle = "[$(if ($Type) { $Type } else { 'Direct' })] $(if ($Title) { $Title } else { $Url })"
    }

    Save-MPVStreamHistory -History @((@($item) + @($history)) | Select-Object -First 50)
}

function Get-MPVStreamLastHistoryItem {
    $history = @(Read-MPVStreamHistory)
    if ($history.Count -eq 0) { return $null }
    return $history[0]
}

function Select-MPVStreamHistoryItem {
    param([Parameter(Mandatory = $true)][pscustomobject]$Config)

    $history = @(Read-MPVStreamHistory)
    if ($history.Count -eq 0) { return $null }

    $items = for ($i = 0; $i -lt $history.Count; $i++) {
        [pscustomobject]@{
            Index     = $i
            Title     = $history[$i].Title
            Type      = $history[$i].Type
            Url       = $history[$i].Url
            MenuTitle = $history[$i].MenuTitle
        }
    }

    Select-MPVStreamSearchResult -Items @($items) -Title 'Playback History' -Config $Config
}

function Get-MPVStreamClipboardText {
    try {
        $value = Get-Clipboard -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        return $value.Trim()
    } catch {
        Write-Error "Failed to read clipboard: $($_.Exception.Message)"
        return $null
    }
}
