function Get-MPVStreamConfigPath {
    Join-Path (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Start-MPVStream') 'config.json'
}

function Get-MPVStreamDefaultConfig {
    [pscustomobject]@{
        cookiePath       = $null
        playerPath       = $null
        menuProvider     = 'fzf'
        helpRenderer     = 'Auto'
        commandPlayer    = $null
        commandPrependArgument = $null
        commandReplaceArgument = $null
        commandAppendArgument = $null
        commandUrl       = $null
        commandBackground = $null
        ytdlVideoSelector = 'bestvideo'
        ytdlVideoCodecFilter = 'auto'
        ytdlMaxHeight    = 'from quality'
        ytdlAudioSelector = 'bestaudio'
        ytdlFallbackSelector = 'best'
        size             = 'PIP'
        ytdlFormat       = '480p'
        maxResults       = 10
        audioOnly        = $false
        background       = $false
        loop             = $false
        rememberPlaybackSpeed = $true
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

    $defaultConfig = Get-MPVStreamDefaultConfig

    while ($true) {
        $options = @(
            New-MPVStreamConfigMenuOption -Title 'Search UI Provider' -CurrentValue (Get-MPVStreamMenuProviderLabel $Config.menuProvider) -DefaultValue (Get-MPVStreamMenuProviderLabel $defaultConfig.menuProvider)
            New-MPVStreamConfigMenuOption -Title 'Help Renderer' -CurrentValue $Config.helpRenderer -DefaultValue $defaultConfig.helpRenderer
            New-MPVStreamConfigMenuOption -Title 'Cookie Path' -CurrentValue $Config.cookiePath -DefaultValue '<not set>'
            New-MPVStreamConfigMenuOption -Title 'Max Search Results' -CurrentValue $Config.maxResults -DefaultValue $defaultConfig.maxResults
            New-MPVStreamConfigMenuOption -Title 'Modify Command' -CurrentValue (Get-MPVStreamCommandSummary -Config $Config) -DefaultValue 'defaults'
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
            3 { Set-MPVStreamMaxResults -Config $Config }
            4 { Invoke-MPVStreamCommandConfig -Config $Config }
            5 { $Config | Format-List; Read-Host 'Press Enter to continue' | Out-Null }
            6 { $Config = Get-MPVStreamDefaultConfig }
            7 {
                Save-MPVStreamConfig -Config $Config
                Write-Host "Saved config: $(Get-MPVStreamConfigPath)" -ForegroundColor Green
                return
            }
        }
    }
}

function New-MPVStreamConfigMenuOption {
    param(
        [string]$Title,
        [object]$CurrentValue,
        [object]$DefaultValue
    )

    $displayDefault = if ($null -eq $DefaultValue -or [string]::IsNullOrWhiteSpace([string]$DefaultValue)) { '<not set>' } else { $DefaultValue }
    $displayCurrent = if ($null -eq $CurrentValue -or [string]::IsNullOrWhiteSpace([string]$CurrentValue)) { $displayDefault } else { $CurrentValue }

    [pscustomobject]@{
        Title        = $Title
        CurrentValue = $displayCurrent
        DefaultValue = $displayDefault
    }
}

function Get-MPVStreamCommandSummary {
    param([pscustomobject]$Config)

    $changed = 0
    $defaultConfig = Get-MPVStreamDefaultConfig
    foreach ($property in @('playerPath', 'size', 'ytdlFormat', 'audioOnly', 'background', 'loop', 'rememberPlaybackSpeed', 'hardwareAccel', 'reversePlaylist', 'noSubtitles', 'subtitleLanguage', 'ytdlVideoSelector', 'ytdlVideoCodecFilter', 'ytdlMaxHeight', 'ytdlAudioSelector', 'ytdlFallbackSelector')) {
        if ($Config.PSObject.Properties.Name -contains $property) {
            $value = $Config.$property
            if ([string]$value -ne [string]$defaultConfig.$property) { $changed++ }
        }
    }

    foreach ($property in @('commandPlayer', 'commandPrependArgument', 'commandReplaceArgument', 'commandAppendArgument', 'commandUrl', 'commandBackground')) {
        if ($Config.PSObject.Properties.Name -contains $property) {
            $value = $Config.$property
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { $changed++ }
        }
    }

    if ($changed -eq 0) { return 'defaults' }
    return "$changed custom setting(s)"
}

function Invoke-MPVStreamCommandConfig {
    param([pscustomobject]$Config)

    while ($true) {
        $defaultConfig = Get-MPVStreamDefaultConfig
        $options = @(
            New-MPVStreamConfigMenuOption -Title 'Player Path' -CurrentValue $Config.playerPath -DefaultValue '<auto>'
            New-MPVStreamConfigMenuOption -Title 'Default Window Size' -CurrentValue $Config.size -DefaultValue $defaultConfig.size
            New-MPVStreamConfigMenuOption -Title 'Default Quality / Format' -CurrentValue $Config.ytdlFormat -DefaultValue $defaultConfig.ytdlFormat
            New-MPVStreamConfigMenuOption -Title 'YTDL Video Selector' -CurrentValue $Config.ytdlVideoSelector -DefaultValue $defaultConfig.ytdlVideoSelector
            New-MPVStreamConfigMenuOption -Title 'YTDL Video Codec Filter' -CurrentValue $Config.ytdlVideoCodecFilter -DefaultValue $defaultConfig.ytdlVideoCodecFilter
            New-MPVStreamConfigMenuOption -Title 'YTDL Max Height' -CurrentValue $Config.ytdlMaxHeight -DefaultValue $defaultConfig.ytdlMaxHeight
            New-MPVStreamConfigMenuOption -Title 'YTDL Audio Selector' -CurrentValue $Config.ytdlAudioSelector -DefaultValue $defaultConfig.ytdlAudioSelector
            New-MPVStreamConfigMenuOption -Title 'YTDL Fallback Selector' -CurrentValue $Config.ytdlFallbackSelector -DefaultValue $defaultConfig.ytdlFallbackSelector
            New-MPVStreamConfigMenuOption -Title 'Audio Only' -CurrentValue $Config.audioOnly -DefaultValue $defaultConfig.audioOnly
            New-MPVStreamConfigMenuOption -Title 'Background Playback' -CurrentValue $Config.background -DefaultValue $defaultConfig.background
            New-MPVStreamConfigMenuOption -Title 'Loop Playback' -CurrentValue $Config.loop -DefaultValue $defaultConfig.loop
            New-MPVStreamConfigMenuOption -Title 'Remember Playback Speed' -CurrentValue $Config.rememberPlaybackSpeed -DefaultValue $defaultConfig.rememberPlaybackSpeed
            New-MPVStreamConfigMenuOption -Title 'Hardware Acceleration' -CurrentValue $Config.hardwareAccel -DefaultValue $defaultConfig.hardwareAccel
            New-MPVStreamConfigMenuOption -Title 'Reverse Playlist' -CurrentValue $Config.reversePlaylist -DefaultValue $defaultConfig.reversePlaylist
            New-MPVStreamConfigMenuOption -Title 'Subtitles Disabled' -CurrentValue $Config.noSubtitles -DefaultValue $defaultConfig.noSubtitles
            New-MPVStreamConfigMenuOption -Title 'Subtitle Language' -CurrentValue $Config.subtitleLanguage -DefaultValue $defaultConfig.subtitleLanguage
            New-MPVStreamConfigMenuOption -Title 'Override Player' -CurrentValue $Config.commandPlayer -DefaultValue '<not set>'
            New-MPVStreamConfigMenuOption -Title 'Prepend Arguments' -CurrentValue $Config.commandPrependArgument -DefaultValue '<not set>'
            New-MPVStreamConfigMenuOption -Title 'Replace Arguments' -CurrentValue $Config.commandReplaceArgument -DefaultValue '<not set>'
            New-MPVStreamConfigMenuOption -Title 'Append Arguments' -CurrentValue $Config.commandAppendArgument -DefaultValue '<not set>'
            New-MPVStreamConfigMenuOption -Title 'Override URL' -CurrentValue $Config.commandUrl -DefaultValue '<not set>'
            New-MPVStreamConfigMenuOption -Title 'Override Background' -CurrentValue $Config.commandBackground -DefaultValue '<not set>'
            'Back'
        )

        $selection = Select-MPVStreamMenuIndex -Options $options -Title 'Modify Command' -Config $Config
        if ($null -eq $selection) { return }

        switch ($selection) {
            0 { Set-MPVStreamPlayerPath -Config $Config }
            1 { $Config.size = Select-MPVStreamConfigValue -Title 'Default Window Size' -Options @('PIP', 'Small', 'Medium', 'Max') -CurrentValue $Config.size }
            2 { $Config.ytdlFormat = Select-MPVStreamConfigValue -Title 'Default Quality / Format' -Options @('480p', '720p', '1080p', 'best', 'audio') -CurrentValue $Config.ytdlFormat }
            3 { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlVideoSelector -Title 'YTDL Video Selector' -DefaultLabel $defaultConfig.ytdlVideoSelector -Presets @('bestvideo', 'bv', 'bv*', 'worstvideo', 'wv') -CustomPrompt 'Custom YTDL video selector' }
            4 { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlVideoCodecFilter -Title 'YTDL Video Codec Filter' -DefaultLabel $defaultConfig.ytdlVideoCodecFilter -Presets @('vcodec!*=av01', 'vcodec^=vp9', 'vcodec^=avc1', 'vcodec^=hev1', 'vcodec^=h264') -CustomPrompt 'Custom YTDL video codec filter' -AllowNone }
            5 { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlMaxHeight -Title 'YTDL Max Height' -DefaultLabel $defaultConfig.ytdlMaxHeight -Presets @('480', '720', '1080', '1440', '2160') -CustomPrompt 'Custom max height' -ValidateInteger -AllowNone }
            6 { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlAudioSelector -Title 'YTDL Audio Selector' -DefaultLabel $defaultConfig.ytdlAudioSelector -Presets @('bestaudio', 'ba', 'ba*', 'worstaudio', 'wa') -CustomPrompt 'Custom YTDL audio selector' }
            7 { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlFallbackSelector -Title 'YTDL Fallback Selector' -DefaultLabel $defaultConfig.ytdlFallbackSelector -Presets @('best', 'b', 'best[height<=720]', 'best[height<=1080]', 'worst') -CustomPrompt 'Custom YTDL fallback selector' -AllowNone }
            8 { $Config.audioOnly = -not $Config.audioOnly }
            9 { $Config.background = -not $Config.background }
            10 { $Config.loop = -not $Config.loop }
            11 { $Config.rememberPlaybackSpeed = -not $Config.rememberPlaybackSpeed }
            12 { $Config.hardwareAccel = -not $Config.hardwareAccel }
            13 { $Config.reversePlaylist = -not $Config.reversePlaylist }
            14 { $Config.noSubtitles = -not $Config.noSubtitles }
            15 { Set-MPVStreamSubtitleLanguage -Config $Config }
            16 { Set-MPVStreamPresetTextValue -Config $Config -Property commandPlayer -Title 'Override Player' -DefaultLabel '<not set>' -Presets @('mpv', 'mpvnet.com', 'mpvnet.exe') -CustomPrompt 'Custom player path or command' }
            17 { Set-MPVStreamPresetTextValue -Config $Config -Property commandPrependArgument -Title 'Prepend Arguments' -DefaultLabel '<not set>' -Presets @('--no-config', '--profile=high-quality', '--msg-level=all=warn', '--force-window=yes') -CustomPrompt 'Custom arguments to prepend' }
            18 { Set-MPVStreamPresetTextValue -Config $Config -Property commandReplaceArgument -Title 'Replace Arguments' -DefaultLabel '<not set>' -Presets @('--no-config', '--idle=yes', '--force-window=yes', '--terminal=yes') -CustomPrompt 'Custom replacement arguments' }
            19 { Set-MPVStreamPresetTextValue -Config $Config -Property commandAppendArgument -Title 'Append Arguments' -DefaultLabel '<not set>' -Presets @('--profile=high-quality', '--speed=1.25', '--volume=70', '--force-window=yes') -CustomPrompt 'Custom arguments to append' }
            20 { Set-MPVStreamPresetTextValue -Config $Config -Property commandUrl -Title 'Override URL' -DefaultLabel '<not set>' -Presets @('https://www.youtube.com/', 'https://www.youtube.com/feed/subscriptions') -CustomPrompt 'Custom override URL' }
            21 { Set-MPVStreamPresetTextValue -Config $Config -Property commandBackground -Title 'Override Background' -DefaultLabel '<not set>' -Presets @('true', 'false') -CustomPrompt $null -Boolean }
            22 { return }
        }
    }
}

function Set-MPVStreamPresetTextValue {
    param(
        [pscustomobject]$Config,
        [string]$Property,
        [string]$Title,
        [string]$DefaultLabel,
        [string[]]$Presets,
        [AllowNull()]
        [string]$CustomPrompt,
        [switch]$ValidateInteger,
        [switch]$Boolean,
        [switch]$AllowNone
    )

    $options = @("Use default ($DefaultLabel)") + $Presets
    if ($AllowNone) { $options += 'None (omit)' }
    if ($CustomPrompt) { $options += 'Custom...' }
    $options += 'Back'

    $currentValue = if ($null -eq $Config.$Property -or [string]::IsNullOrWhiteSpace([string]$Config.$Property)) { $DefaultLabel } else { $Config.$Property }
    $selection = Select-MPVStreamMenuIndex -Options $options -Title "$Title (current: $currentValue)" -Config $Config
    if ($null -eq $selection -or $selection -eq ($options.Count - 1)) { return }

    if ($selection -eq 0) {
        $Config.$Property = if ($DefaultLabel -eq '<not set>') { $null } else { $DefaultLabel }
        return
    }

    $value = $options[$selection]
    if ($AllowNone -and $value -eq 'None (omit)') {
        $Config.$Property = '<none>'
        return
    }

    if ($CustomPrompt -and $selection -eq ($options.Count - 2)) {
        $value = Read-Host "$CustomPrompt (blank to clear)"
        if ([string]::IsNullOrWhiteSpace($value)) {
            $Config.$Property = $null
            return
        }

        if ($AllowNone -and (Test-MPVStreamNoneValue $value)) {
            $Config.$Property = '<none>'
            return
        }
    }

    if ($ValidateInteger) {
        $parsed = 0
        if (-not [int]::TryParse($value, [ref]$parsed) -or $parsed -le 0) {
            Write-Warning 'Please enter a positive number.'
            Read-Host 'Press Enter to continue' | Out-Null
            return
        }

        $Config.$Property = $parsed
        return
    }

    if ($Boolean) {
        $Config.$Property = [bool]::Parse($value)
        return
    }

    $Config.$Property = $value
}

function Test-MPVStreamNoneValue {
    param([object]$Value)

    if ($null -eq $Value) { return $false }
    [string]$Value -match '^(<none>|none|null|omit)$'
}

function Set-MPVStreamCommandBackground {
    param([pscustomobject]$Config)

    $value = Read-Host 'Override background? true, false, or blank to clear'
    if ([string]::IsNullOrWhiteSpace($value)) {
        $Config.commandBackground = $null
        return
    }

    if ($value -match '^(true|t|yes|y|1)$') { $Config.commandBackground = $true; return }
    if ($value -match '^(false|f|no|n|0)$') { $Config.commandBackground = $false; return }

    Write-Warning 'Please enter true, false, or blank.'
    Read-Host 'Press Enter to continue' | Out-Null
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
