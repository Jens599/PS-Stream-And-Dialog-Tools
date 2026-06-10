function Get-MPVStreamConfigPath {
    Join-Path (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Start-MPVStream') 'config.json'
}

function Get-MPVStreamDefaultConfig {
    [pscustomobject]@{
        cookiePath       = $null
        playerPath       = $null
        menuProvider     = 'fzf'
        helpRenderer     = 'Auto'
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
        $config.helpRenderer = Normalize-MPVStreamHelpRenderer $config.helpRenderer
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

function Export-MPVStreamConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = $Path
    if (-not [System.IO.Path]::IsPathRooted($resolvedPath)) {
        $resolvedPath = Join-Path (Get-Location) $resolvedPath
    }

    $directory = Split-Path -Parent $resolvedPath
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $Config | ConvertTo-Json | Out-File -LiteralPath $resolvedPath -Encoding UTF8
    Write-Host "Exported config: $resolvedPath" -ForegroundColor Green
}

function Import-MPVStreamConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Error "Config import file not found: $Path"
        return
    }

    $imported = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $config = Get-MPVStreamDefaultConfig
    foreach ($property in $config.PSObject.Properties.Name) {
        if ($imported.PSObject.Properties.Name -contains $property) {
            $config.$property = $imported.$property
        }
    }
    $config.menuProvider = Normalize-MPVStreamMenuProvider $config.menuProvider
    $config.helpRenderer = Normalize-MPVStreamHelpRenderer $config.helpRenderer

    Save-MPVStreamConfig -Config $config
    Write-Host "Imported config: $(Get-MPVStreamConfigPath)" -ForegroundColor Green
}

function Invoke-MPVStreamConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config
    )

    while ($true) {
        $options = @(
            "Search UI Provider: $(Get-MPVStreamMenuProviderLabel $Config.menuProvider)"
            "Help Renderer: $($Config.helpRenderer)"
            "Cookie Path: $(if ($Config.cookiePath) { $Config.cookiePath } else { '<not set>' })"
            "Player Path: $(if ($Config.playerPath) { $Config.playerPath } else { '<auto>' })"
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
            1 { Set-MPVStreamHelpRenderer -Config $Config }
            2 { Set-MPVStreamCookiePath -Config $Config }
            3 { Set-MPVStreamPlayerPath -Config $Config }
            4 { $Config.size = Select-MPVStreamConfigValue -Title 'Default Window Size' -Options @('PIP', 'Small', 'Medium', 'Max') -CurrentValue $Config.size }
            5 { $Config.ytdlFormat = Select-MPVStreamConfigValue -Title 'Default Quality / Format' -Options @('480p', '720p', '1080p', 'best', 'audio') -CurrentValue $Config.ytdlFormat }
            6 { Set-MPVStreamMaxResults -Config $Config }
            7 { $Config.audioOnly = -not $Config.audioOnly }
            8 { $Config.background = -not $Config.background }
            9 { $Config.loop = -not $Config.loop }
            10 { $Config.hardwareAccel = -not $Config.hardwareAccel }
            11 { $Config.reversePlaylist = -not $Config.reversePlaylist }
            12 { $Config.noSubtitles = -not $Config.noSubtitles }
            13 { Set-MPVStreamSubtitleLanguage -Config $Config }
            14 { $Config | Format-List; Read-Host 'Press Enter to continue' | Out-Null }
            15 { $Config = Get-MPVStreamDefaultConfig }
            16 {
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

function Set-MPVStreamPlayerPath {
    param([pscustomobject]$Config)

    $path = Read-Host 'Player path or command (blank for auto: mpv, mpvnet.com, mpvnet.exe)'
    if ([string]::IsNullOrWhiteSpace($path)) {
        $Config.playerPath = $null
        return
    }

    if (-not [System.IO.Path]::IsPathRooted($path)) {
        $command = Get-Command $path -ErrorAction SilentlyContinue
        if ($command) {
            $Config.playerPath = $path
            return
        }

        try { $path = (Resolve-Path $path -ErrorAction Stop | Select-Object -ExpandProperty Path) } catch { }
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Warning "Player not found: $path"
        Read-Host 'Press Enter to continue' | Out-Null
        return
    }

    $Config.playerPath = $path
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

function Set-MPVStreamHelpRenderer {
    param([pscustomobject]$Config)

    $options = @('Auto', 'Glow', 'Plain')
    $selection = Select-MPVStreamMenuIndex -Options $options -Title 'Help Renderer' -Config $Config
    if ($null -eq $selection) { return }

    $Config.helpRenderer = Normalize-MPVStreamHelpRenderer $options[$selection]
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
