<#
.SYNOPSIS
    A PowerShell wrapper for mpv.
    Optimized for terminal-integrated playback with refined PIP geometry. 
.DESCRIPTION
    This PowerShell function is a wrapper for the mpv media player. 
    It allows for more streamlined playback experience in the terminal. 
    Includes search features to find and play YouTube videos/playlists. 
#>

$privateFiles = @(
    'Private\Help.ps1'
    'Private\Config.ps1'
    'Private\Picker.ps1'
    'Private\Search.ps1'
    'Private\MpvArgs.ps1'
)

foreach ($privateFile in $privateFiles) {
    . (Join-Path $PSScriptRoot $privateFile)
}

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

        [Parameter()]
        [switch]$First,

        [Parameter()]
        [ValidateSet('Video', 'Playlist', 'Channel')]
        [string]$Type,

        [Parameter()]
        [Alias('mpvarg')]
        [string[]]$MpvArgument,

        [Parameter()]
        [switch]$DryRun,

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
        [Alias('slang')]
        [string[]]$SubtitleLanguage,

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
        if (-not $PSBoundParameters.ContainsKey('SubtitleLanguage') -and $configData.subtitleLanguage) { $SubtitleLanguage = @($configData.subtitleLanguage) }

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
                    $searchParameters = @{
                        EncodedQuery = $encodedQuery
                        Playlist     = $Playlist
                        MaxResults   = $MaxResults
                        CookiePath   = $finalCookiePath
                    }
                    if ($Type) { $searchParameters.Type = $Type }
                    $searchResults = @(Search-MPVStreamYouTube @searchParameters)

                    if ($searchResults.Count -eq 0) {
                        Write-Host "No playlists found for that search." -ForegroundColor Red 
                        return
                    }

                    Write-Host "Search results found: $($searchResults.Count)" -ForegroundColor Yellow 

                    $choices = [ordered]@{}

                    foreach ($result in $searchResults) {
                        $choices.Add($choices.Count, $result)
                    }

                    $TitleArray = $choices.Values.MenuTitle 
                    if ($TitleArray) {
                        if ($First) {
                            $selectedResult = @($choices.Values)[0]
                        } else {
                            $selectedResult = Select-MPVStreamSearchResult -Items @($choices.Values) -Title "Playlist Results: $Url" -Config $configData
                        }
                        if ($null -eq $selectedResult) { return }

                        $targetUrl = $selectedResult.Url
                        Write-Host "Match [$($selectedResult.Type)]: $($selectedResult.Title)" -ForegroundColor Cyan 
                    } else { return }
                } else {
                    # Standard mixed search: videos, playlists, and channels.
                    $searchParameters = @{
                        EncodedQuery = $encodedQuery
                        Playlist     = $Playlist
                        MaxResults   = $MaxResults
                        CookiePath   = $finalCookiePath
                    }
                    if ($Type) { $searchParameters.Type = $Type }
                    $searchResults = @(Search-MPVStreamYouTube @searchParameters)
                    
                    $choices = [ordered]@{}

                    foreach ($result in $searchResults) {
                        $choices.Add($choices.Count, $result)
                    }
                    $TitleArray = $choices.Values.MenuTitle
                    if ($TitleArray) {
                        if ($First) {
                            $selectedResult = @($choices.Values)[0]
                        } else {
                            $selectedResult = Select-MPVStreamSearchResult -Items @($choices.Values) -Title "Search Results: $Url" -Config $configData
                        }
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
        # --- 5. Argument Construction ---
        $mpvArgs = New-MPVStreamMpvArgument -Size $Size -YtdlFormat $YtdlFormat -CookiePath $finalCookiePath -AudioOnly:$AudioOnly -Loop:$Loop -HardwareAccel:$HardwareAccel -Background:$Background -ReversePlaylist:$ReversePlaylist -NoSubtitles:$NoSubtitles -SubtitleLanguage $SubtitleLanguage -CustomArgument $MpvArgument

        
        
        Write-Host "→ Launching:" -ForegroundColor Green 
        Write-Host "    mpv $($mpvArgs -join ' ') $targetUrl" -ForegroundColor Yellow 

        if ($DryRun) {
            Write-Host "→ Dry run: MPV was not started" -ForegroundColor Cyan
            return
        }

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

Export-ModuleMember -Function Start-MPVStream -Alias play
