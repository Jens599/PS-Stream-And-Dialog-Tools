<#
.SYNOPSIS
    A PowerShell wrapper for mpv.
    Optimized for terminal-integrated playback with refined PIP geometry. 
.DESCRIPTION
    This PowerShell function is a wrapper for the mpv media player. 
    It allows for more streamlined playback experience in the terminal. 
    Includes search features to find and play YouTube videos/playlists. 
#>

function Start-MPVStream {
    [CmdletBinding()]
    [Alias('play')]
    param(
        [Parameter(Position = 0)]
        [Alias('u')]
        [string]$Url,

        [Parameter(Position = 1)]
        [ValidateSet('PIP', 'Small', 'Medium', 'Max')]
        [Alias('sz')]
        [string]$Size = 'PIP',

        [Parameter()]
        [ValidateSet('480p', '720p', '1080p', 'best', 'audio')]
        [Alias('f')]
        [string]$YtdlFormat = '480p',

        [Parameter()]
        [Alias('c')]
        [string]$CookiePath,

        [Parameter()]
        [switch]$Config,

        [Alias('s')]
        [switch]$Search,

        [Alias('p')]
        [switch]$Playlist,

        [Alias('a')]
        [switch]$AudioOnly,

        [Alias('l')]
        [switch]$Loop,

        [Alias('h')]
        [switch]$HardwareAccel,

        [Alias('b')]
        [switch]$Background,

        [Alias('r')]
        [switch]$ReversePlaylist,

        [Parameter()]
        [Alias('nosub')]
        [switch]$NoSubtitles,

        [Parameter()]
        [ValidateRange(1, 50)]
        [Alias('max')]
        [int]$MaxResults = 10
    )

    process {
        $configData = Read-MPVStreamConfig

        if ($Config) {
            Invoke-MPVStreamConfig -Config $configData
            return
        }

        if (-not $PSBoundParameters.ContainsKey('Size') -and $configData.size) { $Size = $configData.size }
        if (-not $PSBoundParameters.ContainsKey('YtdlFormat') -and $configData.ytdlFormat) { $YtdlFormat = $configData.ytdlFormat }
        if (-not $PSBoundParameters.ContainsKey('MaxResults') -and $configData.maxResults) { $MaxResults = $configData.maxResults }
        if (-not $PSBoundParameters.ContainsKey('AudioOnly') -and $configData.audioOnly) { $AudioOnly = $true }
        if (-not $PSBoundParameters.ContainsKey('Background') -and $configData.background) { $Background = $true }
        if (-not $PSBoundParameters.ContainsKey('Loop') -and $configData.loop) { $Loop = $true }
        if (-not $PSBoundParameters.ContainsKey('HardwareAccel') -and $configData.hardwareAccel) { $HardwareAccel = $true }
        if (-not $PSBoundParameters.ContainsKey('ReversePlaylist') -and $configData.reversePlaylist) { $ReversePlaylist = $true }
        if (-not $PSBoundParameters.ContainsKey('NoSubtitles') -and $configData.noSubtitles) { $NoSubtitles = $true }

        # --- 0. Help Check / Config Mode ---
        $isConfigOnly = [string]::IsNullOrWhiteSpace($Url) -and $CookiePath
        if ([string]::IsNullOrWhiteSpace($Url)) {
            # If only cookie path is provided, enter config mode
            if ($CookiePath) {
                Write-Host "→ Configuration mode: Testing cookie path" -ForegroundColor Cyan
                # Cookie configuration logic will run below
            } else {
                Write-MPVStreamHelp
                return
            }
        }

        # --- 1. Dependency Checks ---
        if (-not $isConfigOnly -and -not (Get-Command mpv -ErrorAction SilentlyContinue)) {
            Write-Error "mpv is missing from PATH. Please install mpv media player." 
            return 
        }
        
        # Only check yt-dlp dependency if searching.
        if ($Search -and -not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
            Write-Error "yt-dlp is missing from PATH. Please install yt-dlp for search/configuration functionality." 
            return 
        }
        
        # --- Cookie Configuration ---
        $configFile = Get-MPVStreamConfigPath
        $legacyConfigFile = Join-Path $env:USERPROFILE '.mpvstream-config.json'
        $finalCookiePath = $null
        
        if ($configData.cookiePath -and (Test-Path $configData.cookiePath -PathType Leaf)) {
            $finalCookiePath = $configData.cookiePath
        } elseif (-not (Test-Path $configFile -PathType Leaf) -and (Test-Path $legacyConfigFile -PathType Leaf)) {
            try {
                $legacyConfig = Get-Content -LiteralPath $legacyConfigFile -Raw | ConvertFrom-Json
                if ($legacyConfig.cookiePath -and (Test-Path $legacyConfig.cookiePath -PathType Leaf)) {
                    $finalCookiePath = $legacyConfig.cookiePath
                }
            } catch {
                Write-Warning "Failed to read config file: $legacyConfigFile"
            }
        }
        
        if ($CookiePath) {
            # Use provided cookie path and save it
            $finalCookiePath = $CookiePath
            Write-Host "→ Cookie path provided: $CookiePath" -ForegroundColor Yellow
            
            # Save to config file
            try {
                $configData.cookiePath = $finalCookiePath
                Save-MPVStreamConfig -Config $configData
                Write-Host "→ Cookie path saved to: $configFile" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to save config file: $configFile"
            }
        } elseif (-not $finalCookiePath) {
            # Default cookie file locations to check
            $defaultCookiePaths = @(
                "cookies.txt",
                "$env:USERPROFILE\cookies.txt",
                "$env:USERPROFILE\Downloads\cookies.txt",
                "$PSScriptRoot\cookies.txt"
            )
            
            foreach ($path in $defaultCookiePaths) {
                if (Test-Path $path -PathType Leaf) {
                    $finalCookiePath = $path
                    break
                }
            }
        }
        
        # Convert relative path to absolute path
        if ($finalCookiePath -and -not [System.IO.Path]::IsPathRooted($finalCookiePath)) {
            try {
                $resolvedPath = Resolve-Path $finalCookiePath -ErrorAction Stop | Select-Object -ExpandProperty Path
                if ($resolvedPath) {
                    $finalCookiePath = $resolvedPath
                }
            } catch {
                Write-Warning "Failed to resolve path: $finalCookiePath"
                $finalCookiePath = $null
            }
        }
        
        # Validate cookie file exists
        if ($finalCookiePath -and (Test-Path $finalCookiePath -PathType Leaf)) {
            Write-Host "→ Using cookies: $finalCookiePath" -ForegroundColor Green
        } elseif ($finalCookiePath) {
            Write-Warning "Cookie file not found: $finalCookiePath"
            $finalCookiePath = $null
        }

        # Exit if in config-only mode
        if (-not $Url) {
            if ($finalCookiePath) {
                Write-Host "→ Configuration complete: Cookie path validated" -ForegroundColor Green
            } else {
                Write-Host "→ Configuration failed: No valid cookie file found" -ForegroundColor Red
            }
            return
        }

        # --- 2. URL Validation ---
        if (-not $Search) {
            $parsedUri = $null
            if (-not [uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsedUri) -or $parsedUri.Scheme -notin @('http', 'https')) {
                Write-Error "Invalid URL format. URLs should start with http:// or https://"
                return
            }
            $targetUrl = $Url
        } else {
            $targetUrl = $Url
        }
        # --- 3. Search Logic ---
        if ($Search) {
            try {
                $encodedQuery = [uri]::EscapeDataString($Url) 
                
                if ($Playlist) {
                    # Search for Playlists specifically using the 'sp' parameter 
                    $searchUrl = "https://www.youtube.com/results?search_query=$encodedQuery&sp=EgIQAw%3D%3D"
                    $ytdlArgs = @($searchUrl, '--print', "%(title)s`t%(id)s`t%(ie_key)s`t%(webpage_url)s", '--flat-playlist', '--playlist-items', "1:$MaxResults")
                    if ($finalCookiePath) { $ytdlArgs += "--cookies", $finalCookiePath }
                    $SearchResult = yt-dlp @ytdlArgs 
                    if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) { throw "yt-dlp exited with code $LASTEXITCODE" }
                    $searchRows = @($SearchResult)

                    if ($null -eq $SearchResult -or $searchRows.Count -eq 0) {
                        Write-Host "No playlists found for that search." -ForegroundColor Red 
                        return
                    }

                    Write-Host "Search results found: $($searchRows.Count)" -ForegroundColor Yellow 

                    $choices = [ordered]@{}

                    for ($i = 0; $i -lt $searchRows.Count; $i++) {
                        $parts = $searchRows[$i] -split "`t", 4
                        if ($parts.Count -ge 4 -and $parts[0] -and $parts[1]) {
                            $resultType = Get-MPVStreamSearchType -Id $parts[1] -IeKey $parts[2] -WebpageUrl $parts[3]
                            $index = $choices.Count
                            $choices.Add($index, [ordered]@{
                                    Title      = $parts[0]
                                    ID         = $parts[1]
                                    Type       = $resultType
                                    Url        = $parts[3]
                                    MenuTitle  = "[$resultType] $($parts[0])"
                                })
                        }
                    }

                    $TitleArray = $choices.Values.MenuTitle 
                    if ($TitleArray) {
                        $selectedResult = Select-MPVStreamSearchResult -Items @($choices.Values) -Title "Playlist Results: $Url" -Config $configData
                        if ($null -eq $selectedResult) { return }

                        $targetUrl = $selectedResult.Url
                        Write-Host "Match [$($selectedResult.Type)]: $($selectedResult.Title)" -ForegroundColor Cyan 
                    } else { return }
                } else {
                    # Standard mixed search: videos, playlists, and channels.
                    $searchUrl = "https://www.youtube.com/results?search_query=$encodedQuery"
                    $ytdlArgs = @($searchUrl, '--print', "%(title)s`t%(id)s`t%(ie_key)s`t%(webpage_url)s", '--flat-playlist', '--playlist-items', "1:$MaxResults")
                    if ($finalCookiePath) { $ytdlArgs += "--cookies", $finalCookiePath }
                    $SearchResult = yt-dlp @ytdlArgs 
                    if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) { throw "yt-dlp exited with code $LASTEXITCODE" }
                    $searchRows = @($SearchResult)
                    
                    $choices = [ordered]@{}

                    for ($i = 0; $i -lt $searchRows.Count; $i++) {
                        $parts = $searchRows[$i] -split "`t", 4
                        if ($parts.Count -ge 4 -and $parts[0] -and $parts[1]) {
                            $resultType = Get-MPVStreamSearchType -Id $parts[1] -IeKey $parts[2] -WebpageUrl $parts[3]
                            $index = $choices.Count
                            $choices.Add($index, [ordered]@{
                                    Title      = $parts[0]
                                    ID         = $parts[1]
                                    Type       = $resultType
                                    Url        = $parts[3]
                                    MenuTitle  = "[$resultType] $($parts[0])"
                                })
                        }
                    }
                    $TitleArray = $choices.Values.MenuTitle
                    if ($TitleArray) {
                        $selectedResult = Select-MPVStreamSearchResult -Items @($choices.Values) -Title "Search Results: $Url" -Config $configData
                        if ($null -eq $selectedResult) { return }

                        $targetUrl = $selectedResult.Url 
                        Write-Host "Match [$($selectedResult.Type)]: $($selectedResult.Title)" -ForegroundColor Cyan 
                    } else { return }
                }
            } catch {
                Write-Error "Search failed: $($_.Exception.Message)" 
                return
            }
        }

        # --- 4. Format Mapping ---
        $formatMap = @{
            '480p'  = 'bestvideo[height<=480]+bestaudio/best' 
            '720p'  = 'bestvideo[height<=720]+bestaudio/best' 
            '1080p' = 'bestvideo[height<=1080]+bestaudio/best' 
            'best'  = 'bestvideo+bestaudio/best' 
            'audio' = 'bestaudio/best' 
        }
        $actualFormat = $formatMap[$YtdlFormat]
        
        # --- 5. Argument Construction ---
        $mpvArgs = @()
        if (-not $Background) { $mpvArgs += "--terminal=yes" } 

        switch ($Size) {
            'PIP' {
                $mpvArgs += "--geometry=320x180-10-10" 
                $mpvArgs += "--autofit=320x180" 
                $mpvArgs += "--no-border" 
                $mpvArgs += "--ontop" 
            }
            'Small' { $mpvArgs += "--autofit=854x480" } 
            'Medium' { $mpvArgs += "--autofit=1280x720" } 
            'Max' { $mpvArgs += "--fullscreen" } 
        }

        if ($AudioOnly) { $mpvArgs += "--no-video" } 
        if ($Loop) { $mpvArgs += "--loop=inf" } 
        if ($HardwareAccel) { $mpvArgs += "--hwdec=auto" } 
        
        if ($ReversePlaylist) { 
            $mpvArgs += "--ytdl-raw-options=playlist-items=1-" 
            $mpvArgs += "--ytdl-raw-options=playlist-reverse=" 
        }
        
        # Add ytdl-format option
        $mpvArgs += "--ytdl-format=$actualFormat"
        
        # Add cookie handling if available
        if ($finalCookiePath) {
            $mpvArgs += "--ytdl-raw-options=cookies=$finalCookiePath"
        }
        
        # Add no-download-archive option to prevent archive creation
        $mpvArgs += "--ytdl-raw-options=no-download-archive="
        
        # Add session ID to MPV (unless disabled)
        if (-not $NoSubtitles) {
            $mpvArgs += "--slang=en"
        }

        
        
        Write-Host "→ Launching:" -ForegroundColor Green 
        Write-Host "    mpv $($mpvArgs -join ' ') $targetUrl" -ForegroundColor Yellow 

        # --- 6. Execution ---
        if ($Background) {
            try {
                $processArgs = $mpvArgs + $targetUrl
                Start-Process -FilePath "mpv" -ArgumentList (Join-NativeArgument $processArgs) -ErrorAction Stop
                Write-Host "→ MPV started in background" -ForegroundColor Green
            } catch {
                Write-Error "Failed to start MPV in background: $($_.Exception.Message)"
            }
        } else {
            try {
                & mpv $targetUrl @mpvArgs
            } catch {
                Write-Error "Failed to start MPV: $($_.Exception.Message)"
            }
        }
    }
}

function Write-MPVStreamHelp {

    $cCmd = "Cyan"; $cDesc = "Gray"; $cHead = "Yellow"
    
    Write-Host "`nusage: play <url> [options]" -ForegroundColor $cHead 
    Write-Host "   or: play <query> -s [options]" -ForegroundColor $cHead 
    Write-Host "   or: play -c <cookie-path> [config mode]" -ForegroundColor $cHead 
    Write-Host "`nPlayback Control" -ForegroundColor White 
    Write-Host "    $("{0,-22}" -f "-Size, -sz <mode>") Window (PIP, Small, Medium, Max)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-YtdlFormat, -f <mode>") Quality (480p, 720p, 1080p, best, audio)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-AudioOnly, -a") Stream audio only" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Background, -b") Run in background process" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Loop, -l") Loop playback infinitely" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-HardwareAccel, -h") Enable hardware acceleration" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-NoSubtitles, -nosub") Disable subtitle language preference" -ForegroundColor $cDesc 
    Write-Host "`nSearch Features" -ForegroundColor White 
    Write-Host "    $("{0,-22}" -f "-Search, -s") Search YouTube instead of direct URL" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Playlist, -p") Search for playlists only" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-MaxResults, -max <num>") Number of search results (1-50, default: 10)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-ReversePlaylist, -r") Reverse playlist order" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-CookiePath, -c <path>") Path to cookie file (saved persistently)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Config, --config") Interactive persistent configuration" -ForegroundColor $cDesc 
    Write-Host "`nExamples" -ForegroundColor White 
    Write-Host "    play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'" -ForegroundColor $cDesc 
    Write-Host "    play 'never gonna give you up' -s" -ForegroundColor $cDesc 
    Write-Host "    play 'lofi beats' -s -p -f audio" -ForegroundColor $cDesc 
    Write-Host "    play 'https://youtu.be/dQw4w9WgXcQ' -sz Small -f 720p" -ForegroundColor $cDesc 
    Write-Host "    play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' -c cookies.txt" -ForegroundColor $cDesc 
    Write-Host "    play -c .\Downloads\Compressed\cookies.txt" -ForegroundColor $cDesc 
    Write-Host "    play --config" -ForegroundColor $cDesc 
}

function Get-MPVStreamConfigPath {
    Join-Path (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Start-MPVStream') 'config.json'
}

function Get-MPVStreamDefaultConfig {
    [pscustomobject]@{
        cookiePath      = $null
        menuProvider    = 'fzf'
        size            = 'PIP'
        ytdlFormat      = '480p'
        maxResults      = 10
        audioOnly       = $false
        background      = $false
        loop            = $false
        hardwareAccel   = $false
        reversePlaylist = $false
        noSubtitles     = $false
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
            11 { $Config | Format-List; Read-Host 'Press Enter to continue' | Out-Null }
            12 { $Config = Get-MPVStreamDefaultConfig }
            13 {
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
        '{0:00} {1}' -f ($i + 1), $Items[$i].MenuTitle
    }

    $selected = $lines | fzf `
        --height 40% `
        --layout reverse `
        --border rounded `
        --info inline `
        --header $Title `
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
            Index = $i
            Type  = $Items[$i].Type
            Title = $Items[$i].Title
            Url   = $Items[$i].Url
        }
    }

    $selected = $gridItems | Out-ConsoleGridView -Title $Title -OutputMode Single
    if ($null -eq $selected) { return $null }
    return $Items[$selected.Index]
}

function Select-MPVStreamSearchResultWithBasicPrompt {
    param([object[]]$Items, [string]$Title)

    Write-Host "`n$Title" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ('  {0,2}. {1}' -f ($i + 1), $Items[$i].MenuTitle)
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

function Join-NativeArgument {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Argument
    )

    ($Argument | ForEach-Object {
        if ($_ -notmatch '[\s"]') { return $_ }
        '"' + ($_ -replace '"', '\"') + '"'
    }) -join ' '
}

function Get-MPVStreamSearchType {
    param(
        [string]$Id,
        [string]$IeKey,
        [string]$WebpageUrl
    )

    if ($WebpageUrl -match '/playlist\?list=' -or $Id -like 'PL*' -or $Id -like 'UU*') {
        return 'Playlist'
    }

    if ($WebpageUrl -match '/(?:channel|c|user|@)' -or $Id -like 'UC*' -or $IeKey -eq 'YoutubeTab') {
        return 'Channel'
    }

    return 'Video'
}

Export-ModuleMember -Function Start-MPVStream -Alias play 
