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
        $configDir = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Start-MPVStream'
        $configFile = Join-Path $configDir 'config.json'
        $legacyConfigFile = Join-Path $env:USERPROFILE '.mpvstream-config.json'
        $finalCookiePath = $null
        
        # Read from config file if it exists
        $configFileToRead = if (Test-Path $configFile -PathType Leaf) { $configFile } elseif (Test-Path $legacyConfigFile -PathType Leaf) { $legacyConfigFile } else { $null }
        if ($configFileToRead) {
            try {
                $config = Get-Content -LiteralPath $configFileToRead -Raw | ConvertFrom-Json
                if ($config.cookiePath -and (Test-Path $config.cookiePath -PathType Leaf)) {
                    $finalCookiePath = $config.cookiePath
                }
            } catch {
                Write-Warning "Failed to read config file: $configFileToRead"
            }
        }
        
        if ($CookiePath) {
            # Use provided cookie path and save it
            $finalCookiePath = $CookiePath
            Write-Host "→ Cookie path provided: $CookiePath" -ForegroundColor Yellow
            
            # Save to config file
            try {
                if (-not (Test-Path $configDir -PathType Container)) {
                    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                }
                $config = @{ cookiePath = $finalCookiePath } | ConvertTo-Json
                $config | Out-File -FilePath $configFile -Encoding UTF8
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
                if (-not (Get-Command Show-Menu -ErrorAction SilentlyContinue)) {
                    $showMenuManifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'Show-Menu\Show-Menu.psd1'
                    if (Test-Path -LiteralPath $showMenuManifest -PathType Leaf) {
                        Import-Module $showMenuManifest -ErrorAction SilentlyContinue
                    }
                }

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
                        if (-not (Get-Command Show-Menu -ErrorAction SilentlyContinue)) {
                            Write-Warning "Show-Menu function not found. Using first result."
                            $resultIndex = 0
                        } else {
                            $resultIndex = Show-Menu -Options $TitleArray -Title "Playlist Results: $Url" -ReturnIndex 
                        }
                        if ($null -eq $resultIndex) { return }

                        $targetUrl = $choices[$resultIndex].Url
                        Write-Host "Match [$($choices[$resultIndex].Type)]: $($choices[$resultIndex].Title)" -ForegroundColor Cyan 
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
                        if (-not (Get-Command Show-Menu -ErrorAction SilentlyContinue)) {
                            Write-Warning "Show-Menu function not found. Using first result."
                            $resultIndex = 0
                        } else {
                            $resultIndex = Show-Menu -Options $TitleArray -Title "Search Results: $Url" -ReturnIndex
                        }
                        if ($null -eq $resultIndex) { return }

                        $targetUrl = $choices[$resultIndex].Url 
                        Write-Host "Match [$($choices[$resultIndex].Type)]: $($choices[$resultIndex].Title)" -ForegroundColor Cyan 
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
    Write-Host "`nExamples" -ForegroundColor White 
    Write-Host "    play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'" -ForegroundColor $cDesc 
    Write-Host "    play 'never gonna give you up' -s" -ForegroundColor $cDesc 
    Write-Host "    play 'lofi beats' -s -p -f audio" -ForegroundColor $cDesc 
    Write-Host "    play 'https://youtu.be/dQw4w9WgXcQ' -sz Small -f 720p" -ForegroundColor $cDesc 
    Write-Host "    play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' -c cookies.txt" -ForegroundColor $cDesc 
    Write-Host "    play -c .\Downloads\Compressed\cookies.txt" -ForegroundColor $cDesc 
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
