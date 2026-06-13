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
        commandTerminal  = 'auto'
        commandGeometry  = 'from size'
        commandAutofit   = 'from size'
        commandNoBorder  = 'auto'
        commandOntop     = 'auto'
        commandHwdec     = 'auto'
        commandSavePosition = 'auto'
        commandWatchLaterOptions = 'start,speed'
        commandNoDownloadArchive = $true
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
        [object]$DefaultValue,
        [string]$Tooltip
    )

    $displayDefault = if ($null -eq $DefaultValue -or [string]::IsNullOrWhiteSpace([string]$DefaultValue)) { '<not set>' } else { $DefaultValue }
    $displayCurrent = if ($null -eq $CurrentValue -or [string]::IsNullOrWhiteSpace([string]$CurrentValue)) { $displayDefault } else { $CurrentValue }

    [pscustomobject]@{
        Title        = $Title
        CurrentValue = $displayCurrent
        DefaultValue = $displayDefault
        Tooltip      = $Tooltip
    }
}

function Show-MPVStreamConfigTooltip {
    param(
        [string]$Title,
        [string]$Tooltip
    )

    if ([string]::IsNullOrWhiteSpace($Tooltip)) {
        Write-Host "No tooltip available for $Title." -ForegroundColor Yellow
    } else {
        Write-Host "`n$Title" -ForegroundColor Cyan
        Write-Host $Tooltip
    }

    Read-Host 'Press Enter to continue' | Out-Null
}

function Get-MPVStreamCommandSummary {
    param([pscustomobject]$Config)

    $changed = 0
    $defaultConfig = Get-MPVStreamDefaultConfig
    foreach ($property in @('playerPath', 'size', 'ytdlFormat', 'audioOnly', 'background', 'loop', 'rememberPlaybackSpeed', 'hardwareAccel', 'reversePlaylist', 'noSubtitles', 'subtitleLanguage', 'ytdlVideoSelector', 'ytdlVideoCodecFilter', 'ytdlMaxHeight', 'ytdlAudioSelector', 'ytdlFallbackSelector', 'commandTerminal', 'commandGeometry', 'commandAutofit', 'commandNoBorder', 'commandOntop', 'commandHwdec', 'commandSavePosition', 'commandWatchLaterOptions', 'commandNoDownloadArchive')) {
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
        $options = @(
            New-MPVStreamConfigMenuOption -Title 'Player and Overrides' -CurrentValue 'open' -DefaultValue 'category' -Tooltip 'Configure executable path plus full-command prepend, replace, append, URL, and background overrides.'
            New-MPVStreamConfigMenuOption -Title 'Window Layout' -CurrentValue 'open' -DefaultValue 'category' -Tooltip 'Configure terminal, geometry, autofit, border, and always-on-top mpv flags.'
            New-MPVStreamConfigMenuOption -Title 'Playback Flags' -CurrentValue 'open' -DefaultValue 'category' -Tooltip 'Configure playback behavior such as audio-only, loop, hardware decoding, and watch-later flags.'
            New-MPVStreamConfigMenuOption -Title 'YTDL Format' -CurrentValue 'open' -DefaultValue 'category' -Tooltip 'Configure the generated --ytdl-format selector parts and ytdl raw options.'
            New-MPVStreamConfigMenuOption -Title 'Subtitles' -CurrentValue 'open' -DefaultValue 'category' -Tooltip 'Configure subtitle language and whether subtitle preferences are emitted.'
            'Back'
        )

        $selection = Select-MPVStreamMenuIndex -Options $options -Title 'Modify Command' -Config $Config
        if ($null -eq $selection) { return }

        switch ($selection) {
            0 { Invoke-MPVStreamPlayerCommandConfig -Config $Config }
            1 { Invoke-MPVStreamWindowCommandConfig -Config $Config }
            2 { Invoke-MPVStreamPlaybackCommandConfig -Config $Config }
            3 { Invoke-MPVStreamYtdlCommandConfig -Config $Config }
            4 { Invoke-MPVStreamSubtitleCommandConfig -Config $Config }
            5 { return }
        }
    }
}

function Invoke-MPVStreamConfigOptionAction {
    param(
        [pscustomobject]$Config,
        [string]$Title,
        [string]$Tooltip,
        [scriptblock]$Edit
    )

    & $Edit
}

function Invoke-MPVStreamPlayerCommandConfig {
    param([pscustomobject]$Config)

    while ($true) {
        $options = @(
            New-MPVStreamConfigMenuOption -Title 'Player Path' -CurrentValue $Config.playerPath -DefaultValue '<auto>' -Tooltip 'Base player configured before command overrides. Auto searches mpv, mpvnet.com, and mpvnet.exe.'
            New-MPVStreamConfigMenuOption -Title 'Override Player' -CurrentValue $Config.commandPlayer -DefaultValue '<not set>' -Tooltip 'Replaces the resolved player in the final command, for example C:\Users\Dell\Documents\MPV\mpv.com.'
            New-MPVStreamConfigMenuOption -Title 'Prepend Arguments' -CurrentValue $Config.commandPrependArgument -DefaultValue '<not set>' -Tooltip 'Arguments inserted before generated mpv arguments.'
            New-MPVStreamConfigMenuOption -Title 'Replace Arguments' -CurrentValue $Config.commandReplaceArgument -DefaultValue '<not set>' -Tooltip 'Replaces all generated mpv arguments. URL is still appended unless Override URL is set.'
            New-MPVStreamConfigMenuOption -Title 'Append Arguments' -CurrentValue $Config.commandAppendArgument -DefaultValue '<not set>' -Tooltip 'Arguments appended after generated mpv arguments and before the URL.'
            New-MPVStreamConfigMenuOption -Title 'Override URL' -CurrentValue $Config.commandUrl -DefaultValue '<not set>' -Tooltip 'Replaces the resolved playback URL in the final command.'
            New-MPVStreamConfigMenuOption -Title 'Override Background' -CurrentValue $Config.commandBackground -DefaultValue '<not set>' -Tooltip 'Overrides whether the final command starts in background mode.'
            'Back'
        )

        $selection = Select-MPVStreamMenuIndex -Options $options -Title 'Player and Overrides' -Config $Config
        if ($null -eq $selection -or $selection -eq 7) { return }

        switch ($selection) {
            0 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Player Path' -Tooltip $options[0].Tooltip -Edit { Set-MPVStreamPlayerPath -Config $Config } }
            1 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Override Player' -Tooltip $options[1].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandPlayer -Title 'Override Player' -DefaultLabel '<not set>' -Presets @('mpv', 'mpvnet.com', 'mpvnet.exe', 'C:\Users\Dell\Documents\MPV\mpv.com') -CustomPrompt 'Custom player path or command' } }
            2 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Prepend Arguments' -Tooltip $options[2].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandPrependArgument -Title 'Prepend Arguments' -DefaultLabel '<not set>' -Presets @('--no-config', '--profile=high-quality', '--msg-level=all=warn', '--force-window=yes') -CustomPrompt 'Custom arguments to prepend' } }
            3 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Replace Arguments' -Tooltip $options[3].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandReplaceArgument -Title 'Replace Arguments' -DefaultLabel '<not set>' -Presets @('--no-config', '--idle=yes', '--force-window=yes', '--terminal=yes') -CustomPrompt 'Custom replacement arguments' } }
            4 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Append Arguments' -Tooltip $options[4].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandAppendArgument -Title 'Append Arguments' -DefaultLabel '<not set>' -Presets @('--profile=high-quality', '--speed=1.25', '--volume=70', '--force-window=yes') -CustomPrompt 'Custom arguments to append' } }
            5 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Override URL' -Tooltip $options[5].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandUrl -Title 'Override URL' -DefaultLabel '<not set>' -Presets @('https://www.youtube.com/', 'https://www.youtube.com/feed/subscriptions', 'https://www.youtube.com/playlist?list=UUEQg9lX9Y61J4U9Gck9QsWg') -CustomPrompt 'Custom override URL' } }
            6 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Override Background' -Tooltip $options[6].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandBackground -Title 'Override Background' -DefaultLabel '<not set>' -Presets @('true', 'false') -CustomPrompt $null -Boolean } }
        }
    }
}

function Invoke-MPVStreamWindowCommandConfig {
    param([pscustomobject]$Config)

    $defaultConfig = Get-MPVStreamDefaultConfig
    while ($true) {
        $options = @(
            New-MPVStreamConfigMenuOption -Title 'Default Window Size' -CurrentValue $Config.size -DefaultValue $defaultConfig.size -Tooltip 'Controls the default window preset used to generate geometry and autofit values.'
            New-MPVStreamConfigMenuOption -Title 'Terminal' -CurrentValue $Config.commandTerminal -DefaultValue $defaultConfig.commandTerminal -Tooltip 'Controls --terminal=yes. Auto emits it unless background playback is enabled.'
            New-MPVStreamConfigMenuOption -Title 'Geometry' -CurrentValue $Config.commandGeometry -DefaultValue $defaultConfig.commandGeometry -Tooltip 'Controls --geometry. Use from size for preset geometry, None to omit, or custom values like 320x180-10-10.'
            New-MPVStreamConfigMenuOption -Title 'Autofit' -CurrentValue $Config.commandAutofit -DefaultValue $defaultConfig.commandAutofit -Tooltip 'Controls --autofit. Use from size for preset dimensions, None to omit, or custom values like 320x180.'
            New-MPVStreamConfigMenuOption -Title 'No Border' -CurrentValue $Config.commandNoBorder -DefaultValue $defaultConfig.commandNoBorder -Tooltip 'Controls --no-border. Auto emits it for PIP only.'
            New-MPVStreamConfigMenuOption -Title 'On Top' -CurrentValue $Config.commandOntop -DefaultValue $defaultConfig.commandOntop -Tooltip 'Controls --ontop. Auto emits it for PIP only.'
            'Back'
        )

        $selection = Select-MPVStreamMenuIndex -Options $options -Title 'Window Layout' -Config $Config
        if ($null -eq $selection -or $selection -eq 6) { return }

        switch ($selection) {
            0 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Default Window Size' -Tooltip $options[0].Tooltip -Edit { $Config.size = Select-MPVStreamConfigValue -Title 'Default Window Size' -Options @('PIP', 'Small', 'Medium', 'Max') -CurrentValue $Config.size } }
            1 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Terminal' -Tooltip $options[1].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandTerminal -Title 'Terminal' -DefaultLabel $defaultConfig.commandTerminal -Presets @('true', 'false') -CustomPrompt $null -BooleanAuto } }
            2 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Geometry' -Tooltip $options[2].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandGeometry -Title 'Geometry' -DefaultLabel $defaultConfig.commandGeometry -Presets @('320x180-10-10', '854x480-10-10', '1280x720-10-10') -CustomPrompt 'Custom mpv geometry' -AllowNone } }
            3 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Autofit' -Tooltip $options[3].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandAutofit -Title 'Autofit' -DefaultLabel $defaultConfig.commandAutofit -Presets @('320x180', '854x480', '1280x720') -CustomPrompt 'Custom mpv autofit size' -AllowNone } }
            4 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'No Border' -Tooltip $options[4].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandNoBorder -Title 'No Border' -DefaultLabel $defaultConfig.commandNoBorder -Presets @('true', 'false') -CustomPrompt $null -BooleanAuto } }
            5 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'On Top' -Tooltip $options[5].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandOntop -Title 'On Top' -DefaultLabel $defaultConfig.commandOntop -Presets @('true', 'false') -CustomPrompt $null -BooleanAuto } }
        }
    }
}

function Invoke-MPVStreamPlaybackCommandConfig {
    param([pscustomobject]$Config)

    $defaultConfig = Get-MPVStreamDefaultConfig
    while ($true) {
        $options = @(
            New-MPVStreamConfigMenuOption -Title 'Audio Only' -CurrentValue $Config.audioOnly -DefaultValue $defaultConfig.audioOnly -Tooltip 'Controls --no-video.'
            New-MPVStreamConfigMenuOption -Title 'Background Playback' -CurrentValue $Config.background -DefaultValue $defaultConfig.background -Tooltip 'Starts mpv in background and suppresses terminal output when active.'
            New-MPVStreamConfigMenuOption -Title 'Loop Playback' -CurrentValue $Config.loop -DefaultValue $defaultConfig.loop -Tooltip 'Controls --loop=inf.'
            New-MPVStreamConfigMenuOption -Title 'Hardware Acceleration' -CurrentValue $Config.hardwareAccel -DefaultValue $defaultConfig.hardwareAccel -Tooltip 'Enables hardware decoding and controls --hwdec through Hardware Decoder.'
            New-MPVStreamConfigMenuOption -Title 'Hardware Decoder' -CurrentValue $Config.commandHwdec -DefaultValue $defaultConfig.commandHwdec -Tooltip 'Controls --hwdec. Auto emits auto-safe when Hardware Acceleration is enabled.'
            New-MPVStreamConfigMenuOption -Title 'Remember Playback Speed' -CurrentValue $Config.rememberPlaybackSpeed -DefaultValue $defaultConfig.rememberPlaybackSpeed -Tooltip 'Controls whether watch-later flags are emitted by default.'
            New-MPVStreamConfigMenuOption -Title 'Save Position' -CurrentValue $Config.commandSavePosition -DefaultValue $defaultConfig.commandSavePosition -Tooltip 'Controls --save-position-on-quit. Auto follows Remember Playback Speed.'
            New-MPVStreamConfigMenuOption -Title 'Watch Later Options' -CurrentValue $Config.commandWatchLaterOptions -DefaultValue $defaultConfig.commandWatchLaterOptions -Tooltip 'Controls --watch-later-options, for example start,speed.'
            New-MPVStreamConfigMenuOption -Title 'Reverse Playlist' -CurrentValue $Config.reversePlaylist -DefaultValue $defaultConfig.reversePlaylist -Tooltip 'Controls playlist-items and playlist-reverse ytdl raw options.'
            'Back'
        )

        $selection = Select-MPVStreamMenuIndex -Options $options -Title 'Playback Flags' -Config $Config
        if ($null -eq $selection -or $selection -eq 9) { return }

        switch ($selection) {
            0 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Audio Only' -Tooltip $options[0].Tooltip -Edit { $Config.audioOnly = -not $Config.audioOnly } }
            1 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Background Playback' -Tooltip $options[1].Tooltip -Edit { $Config.background = -not $Config.background } }
            2 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Loop Playback' -Tooltip $options[2].Tooltip -Edit { $Config.loop = -not $Config.loop } }
            3 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Hardware Acceleration' -Tooltip $options[3].Tooltip -Edit { $Config.hardwareAccel = -not $Config.hardwareAccel } }
            4 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Hardware Decoder' -Tooltip $options[4].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandHwdec -Title 'Hardware Decoder' -DefaultLabel $defaultConfig.commandHwdec -Presets @('auto-safe', 'auto', 'd3d11va', 'dxva2', 'no') -CustomPrompt 'Custom --hwdec value' -AllowNone } }
            5 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Remember Playback Speed' -Tooltip $options[5].Tooltip -Edit { $Config.rememberPlaybackSpeed = -not $Config.rememberPlaybackSpeed } }
            6 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Save Position' -Tooltip $options[6].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandSavePosition -Title 'Save Position' -DefaultLabel $defaultConfig.commandSavePosition -Presets @('true', 'false') -CustomPrompt $null -BooleanAuto } }
            7 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Watch Later Options' -Tooltip $options[7].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property commandWatchLaterOptions -Title 'Watch Later Options' -DefaultLabel $defaultConfig.commandWatchLaterOptions -Presets @('start,speed', 'start', 'speed', 'all') -CustomPrompt 'Custom watch-later-options value' -AllowNone } }
            8 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Reverse Playlist' -Tooltip $options[8].Tooltip -Edit { $Config.reversePlaylist = -not $Config.reversePlaylist } }
        }
    }
}

function Invoke-MPVStreamYtdlCommandConfig {
    param([pscustomobject]$Config)

    $defaultConfig = Get-MPVStreamDefaultConfig
    while ($true) {
        $options = @(
            New-MPVStreamConfigMenuOption -Title 'Default Quality / Format' -CurrentValue $Config.ytdlFormat -DefaultValue $defaultConfig.ytdlFormat -Tooltip 'High-level quality preset used before selector parts are applied.'
            New-MPVStreamConfigMenuOption -Title 'YTDL Video Selector' -CurrentValue $Config.ytdlVideoSelector -DefaultValue $defaultConfig.ytdlVideoSelector -Tooltip 'Video selector before filters, for example bestvideo or bv*.'
            New-MPVStreamConfigMenuOption -Title 'YTDL Video Codec Filter' -CurrentValue $Config.ytdlVideoCodecFilter -DefaultValue $defaultConfig.ytdlVideoCodecFilter -Tooltip 'Video codec filter. Auto resolves to vcodec!*=av01 when hardware acceleration is enabled; None omits codec filtering.'
            New-MPVStreamConfigMenuOption -Title 'YTDL Max Height' -CurrentValue $Config.ytdlMaxHeight -DefaultValue $defaultConfig.ytdlMaxHeight -Tooltip 'Height filter. From quality follows 480p/720p/1080p; None omits height filtering.'
            New-MPVStreamConfigMenuOption -Title 'YTDL Audio Selector' -CurrentValue $Config.ytdlAudioSelector -DefaultValue $defaultConfig.ytdlAudioSelector -Tooltip 'Audio selector, for example bestaudio or ba.'
            New-MPVStreamConfigMenuOption -Title 'YTDL Fallback Selector' -CurrentValue $Config.ytdlFallbackSelector -DefaultValue $defaultConfig.ytdlFallbackSelector -Tooltip 'Fallback selector after slash, for example best. None omits fallback.'
            New-MPVStreamConfigMenuOption -Title 'No Download Archive' -CurrentValue $Config.commandNoDownloadArchive -DefaultValue $defaultConfig.commandNoDownloadArchive -Tooltip 'Controls --ytdl-raw-options=no-download-archive=.'
            'Back'
        )

        $selection = Select-MPVStreamMenuIndex -Options $options -Title 'YTDL Format' -Config $Config
        if ($null -eq $selection -or $selection -eq 7) { return }

        switch ($selection) {
            0 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Default Quality / Format' -Tooltip $options[0].Tooltip -Edit { $Config.ytdlFormat = Select-MPVStreamConfigValue -Title 'Default Quality / Format' -Options @('480p', '720p', '1080p', 'best', 'audio') -CurrentValue $Config.ytdlFormat } }
            1 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'YTDL Video Selector' -Tooltip $options[1].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlVideoSelector -Title 'YTDL Video Selector' -DefaultLabel $defaultConfig.ytdlVideoSelector -Presets @('bestvideo', 'bv', 'bv*', 'worstvideo', 'wv') -CustomPrompt 'Custom YTDL video selector' } }
            2 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'YTDL Video Codec Filter' -Tooltip $options[2].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlVideoCodecFilter -Title 'YTDL Video Codec Filter' -DefaultLabel $defaultConfig.ytdlVideoCodecFilter -Presets @('vcodec!*=av01', 'vcodec^=vp9', 'vcodec^=avc1', 'vcodec^=hev1', 'vcodec^=h264') -CustomPrompt 'Custom YTDL video codec filter' -AllowNone } }
            3 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'YTDL Max Height' -Tooltip $options[3].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlMaxHeight -Title 'YTDL Max Height' -DefaultLabel $defaultConfig.ytdlMaxHeight -Presets @('480', '720', '1080', '1440', '2160') -CustomPrompt 'Custom max height' -ValidateInteger -AllowNone } }
            4 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'YTDL Audio Selector' -Tooltip $options[4].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlAudioSelector -Title 'YTDL Audio Selector' -DefaultLabel $defaultConfig.ytdlAudioSelector -Presets @('bestaudio', 'ba', 'ba*', 'worstaudio', 'wa') -CustomPrompt 'Custom YTDL audio selector' } }
            5 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'YTDL Fallback Selector' -Tooltip $options[5].Tooltip -Edit { Set-MPVStreamPresetTextValue -Config $Config -Property ytdlFallbackSelector -Title 'YTDL Fallback Selector' -DefaultLabel $defaultConfig.ytdlFallbackSelector -Presets @('best', 'b', 'best[height<=720]', 'best[height<=1080]', 'worst') -CustomPrompt 'Custom YTDL fallback selector' -AllowNone } }
            6 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'No Download Archive' -Tooltip $options[6].Tooltip -Edit { $Config.commandNoDownloadArchive = -not [bool]$Config.commandNoDownloadArchive } }
        }
    }
}

function Invoke-MPVStreamSubtitleCommandConfig {
    param([pscustomobject]$Config)

    $defaultConfig = Get-MPVStreamDefaultConfig
    while ($true) {
        $options = @(
            New-MPVStreamConfigMenuOption -Title 'Subtitles Disabled' -CurrentValue $Config.noSubtitles -DefaultValue $defaultConfig.noSubtitles -Tooltip 'When true, omits subtitle language preference flags.'
            New-MPVStreamConfigMenuOption -Title 'Subtitle Language' -CurrentValue $Config.subtitleLanguage -DefaultValue $defaultConfig.subtitleLanguage -Tooltip 'Controls --slang, for example en or en,ja.'
            'Back'
        )

        $selection = Select-MPVStreamMenuIndex -Options $options -Title 'Subtitles' -Config $Config
        if ($null -eq $selection -or $selection -eq 2) { return }

        switch ($selection) {
            0 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Subtitles Disabled' -Tooltip $options[0].Tooltip -Edit { $Config.noSubtitles = -not $Config.noSubtitles } }
            1 { Invoke-MPVStreamConfigOptionAction -Config $Config -Title 'Subtitle Language' -Tooltip $options[1].Tooltip -Edit { Set-MPVStreamSubtitleLanguage -Config $Config } }
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
        [switch]$BooleanAuto,
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

    if ($BooleanAuto) {
        if ($value -eq 'auto') { $Config.$Property = 'auto'; return }
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
