function Get-MPVStreamConfigPath {
    Join-Path (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Start-MPVStream') 'config.json'
}

function Get-MPVStreamDefaultConfig {
    [pscustomobject]@{
        cookiePath       = $null
        menuProvider     = 'fzf'
        size             = 'PIP'
        ytdlFormat       = '480p'
        maxResults       = 10
        audioOnly        = $false
        background       = $false
        loop             = $false
        hardwareAccel    = $false
        reversePlaylist  = $false
        noSubtitles      = $false
        subtitleLanguage = 'en'
    }
}

function Read-MPVStreamConfig {
    $config = Get-MPVStreamDefaultConfig
    $configPath = Get-MPVStreamConfigPath

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return $config
    }

    try {
        $savedConfig = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        foreach ($property in $config.PSObject.Properties.Name) {
            if ($savedConfig.PSObject.Properties.Name -contains $property) {
                $config.$property = $savedConfig.$property
            }
        }
        $config.menuProvider = Normalize-MPVStreamMenuProvider $config.menuProvider
    } catch {
        Write-Warning "Failed to read config file: $configPath"
    }

    return $config
}

function Save-MPVStreamConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    $configPath = Get-MPVStreamConfigPath
    $configDir = Split-Path -Parent $configPath
    if (-not (Test-Path -LiteralPath $configDir -PathType Container)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $Config | ConvertTo-Json | Out-File -LiteralPath $configPath -Encoding UTF8
}

function Invoke-MPVStreamConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    while ($true) {
        $options = @(
            "Search UI Provider: $(Get-MPVStreamMenuProviderLabel $Config.menuProvider)"
            "Cookie Path: $(if ($Config.cookiePath) { $Config.cookiePath } else { '<not set>' })"
            "Default Window Size: $($Config.size)"
            "Default Quality / Format: $($Config.ytdlFormat)"
            "Max Search Results: $($Config.maxResults)"
            "Audio Only: $($Config.audioOnly)"
            "Background Playback: $($Config.background)"
            "Loop Playback: $($Config.loop)"
            "Hardware Acceleration: $($Config.hardwareAccel)"
            "Reverse Playlist: $($Config.reversePlaylist)"
            "Subtitles Disabled: $($Config.noSubtitles)"
            "Subtitle Language: $($Config.subtitleLanguage)"
            'Show Current Config'
            'Reset Config'
            'Save and Exit'
        )

        $selection = Select-MPVStreamMenuIndex -Options $options -Title 'Start-MPVStream Config' -Config $Config
        if ($null -eq $selection) { return }

        switch ($selection) {
            0 { Set-MPVStreamMenuProvider -Config $Config }
            1 { Set-MPVStreamCookiePath -Config $Config }
            2 { $Config.size = Select-MPVStreamConfigValue -Title 'Default Window Size' -Options @('PIP', 'Small', 'Medium', 'Max') -CurrentValue $Config.size }
            3 { $Config.ytdlFormat = Select-MPVStreamConfigValue -Title 'Default Quality / Format' -Options @('480p', '720p', '1080p', 'best', 'audio') -CurrentValue $Config.ytdlFormat }
            4 { Set-MPVStreamMaxResults -Config $Config }
            5 { $Config.audioOnly = -not $Config.audioOnly }
            6 { $Config.background = -not $Config.background }
            7 { $Config.loop = -not $Config.loop }
            8 { $Config.hardwareAccel = -not $Config.hardwareAccel }
            9 { $Config.reversePlaylist = -not $Config.reversePlaylist }
            10 { $Config.noSubtitles = -not $Config.noSubtitles }
            11 { Set-MPVStreamSubtitleLanguage -Config $Config }
            12 { $Config | Format-List; Read-Host 'Press Enter to continue' | Out-Null }
            13 { $Config = Get-MPVStreamDefaultConfig }
            14 {
                Save-MPVStreamConfig -Config $Config
                Write-Host "Saved config: $(Get-MPVStreamConfigPath)" -ForegroundColor Green
                return
            }
        }
    }
}

function Select-MPVStreamConfigValue {
    param(
        [string]$Title,
        [string[]]$Options,
        [string]$CurrentValue
    )

    $config = Read-MPVStreamConfig
    $selection = Select-MPVStreamMenuIndex -Options $Options -Title "$Title (current: $CurrentValue)" -Config $config
    if ($null -eq $selection) { return $CurrentValue }
    return $Options[$selection]
}

function Set-MPVStreamCookiePath {
    param([pscustomobject]$Config)

    $path = Read-Host 'Cookie path (blank to clear)'
    if ([string]::IsNullOrWhiteSpace($path)) {
        $Config.cookiePath = $null
        return
    }

    if (-not [System.IO.Path]::IsPathRooted($path)) {
        try { $path = (Resolve-Path $path -ErrorAction Stop | Select-Object -ExpandProperty Path) } catch { }
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Warning "Cookie file not found: $path"
        Read-Host 'Press Enter to continue' | Out-Null
        return
    }

    $Config.cookiePath = $path
}

function Set-MPVStreamMaxResults {
    param([pscustomobject]$Config)

    $value = Read-Host "Max search results (1-50, current: $($Config.maxResults))"
    $parsed = 0
    if ([int]::TryParse($value, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 50) {
        $Config.maxResults = $parsed
    } else {
        Write-Warning 'Please enter a number from 1 to 50.'
        Read-Host 'Press Enter to continue' | Out-Null
    }
}

function Set-MPVStreamSubtitleLanguage {
    param([pscustomobject]$Config)

    $value = Read-Host "Subtitle language(s), comma-separated (current: $($Config.subtitleLanguage))"
    if ([string]::IsNullOrWhiteSpace($value)) {
        $Config.subtitleLanguage = 'en'
        return
    }

    $languages = @($value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($languages.Count -eq 0) {
        $Config.subtitleLanguage = 'en'
        return
    }

    $Config.subtitleLanguage = $languages -join ','
}

function Set-MPVStreamMenuProvider {
    param([pscustomobject]$Config)

    $labels = @('fzf', 'Microsoft.PowerShell.ConsoleGuiTools', 'Out-ConsoleGridView', 'Basic Prompt')
    $selection = Select-MPVStreamMenuIndex -Options $labels -Title 'Search UI Provider' -Config $Config
    if ($null -eq $selection) { return }

    $provider = Normalize-MPVStreamMenuProvider $labels[$selection]
    if (-not (Test-MPVStreamMenuProvider $provider)) {
        $install = Read-Host "$(Get-MPVStreamMenuProviderLabel $provider) is not installed. Install now? [Y/N]"
        if ($install -match '^(y|yes)$') {
            Install-MPVStreamMenuProvider $provider
        }
    }

    $Config.menuProvider = $provider
}

function Normalize-MPVStreamMenuProvider {
    param([string]$Provider)

    switch -Regex ($Provider) {
        '^fzf$' { return 'fzf' }
        '^Microsoft\.PowerShell\.ConsoleGuiTools$' { return 'ConsoleGuiTools' }
        '^ConsoleGuiTools$' { return 'ConsoleGuiTools' }
        '^Out-?ConsoleGridView$' { return 'OutConsoleGridView' }
        '^Show-?Menu$' { return 'BasicPrompt' }
        '^Basic\s*Prompt$' { return 'BasicPrompt' }
        '^BasicPrompt$' { return 'BasicPrompt' }
        default { return 'fzf' }
    }
}

function Get-MPVStreamMenuProviderLabel {
    param([string]$Provider)

    switch (Normalize-MPVStreamMenuProvider $Provider) {
        'fzf' { return 'fzf' }
        'ConsoleGuiTools' { return 'Microsoft.PowerShell.ConsoleGuiTools' }
        'OutConsoleGridView' { return 'Out-ConsoleGridView' }
        'BasicPrompt' { return 'Basic Prompt' }
        default { return 'fzf' }
    }
}

function Test-MPVStreamMenuProvider {
    param([string]$Provider)

    switch (Normalize-MPVStreamMenuProvider $Provider) {
        'fzf' { return [bool](Get-Command fzf -ErrorAction SilentlyContinue) }
        'ConsoleGuiTools' { return [bool](Get-Command Out-ConsoleGridView -ErrorAction SilentlyContinue) }
        'OutConsoleGridView' { return [bool](Get-Command Out-ConsoleGridView -ErrorAction SilentlyContinue) }
        'BasicPrompt' { return $true }
    }
}

function Install-MPVStreamMenuProvider {
    param([string]$Provider)

    switch (Normalize-MPVStreamMenuProvider $Provider) {
        'fzf' { winget install junegunn.fzf }
        'ConsoleGuiTools' { Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser }
        'OutConsoleGridView' { Install-Module Microsoft.PowerShell.ConsoleGuiTools -Scope CurrentUser }
        'BasicPrompt' { Write-Host 'Basic prompt is built into PowerShell.' -ForegroundColor Green }
    }
}
