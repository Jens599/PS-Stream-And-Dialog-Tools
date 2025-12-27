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
        if (-not (Get-Command mpv -ErrorAction SilentlyContinue)) {
            Write-Error "mpv is missing from PATH. Please install mpv media player." 
            return 
        }
        
        # Only check yt-dlp dependency if searching or in config mode
        if (($Search -or -not $Url) -and -not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
            Write-Error "yt-dlp is missing from PATH. Please install yt-dlp for search/configuration functionality." 
            return 
        }
        
        # --- Cookie Configuration ---
        $configFile = "$env:USERPROFILE\.mpvstream-config.json"
        $finalCookiePath = $null
        
        # Read from config file if it exists
        if (Test-Path $configFile -PathType Leaf) {
            try {
                $config = Get-Content $configFile -Raw | ConvertFrom-Json
                if ($config.cookiePath -and (Test-Path $config.cookiePath -PathType Leaf)) {
                    $finalCookiePath = $config.cookiePath
                }
            } catch {
                Write-Warning "Failed to read config file: $configFile"
            }
        }
        
        if ($CookiePath) {
            # Use provided cookie path and save it
            $finalCookiePath = $CookiePath
            Write-Host "→ Cookie path provided: $CookiePath" -ForegroundColor Yellow
            
            # Save to config file
            try {
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
            # Basic URL validation for direct playback
            if ($Url -notmatch '^https?://') {
                Write-Error "Invalid URL format. URLs should start with http:// or https://"
                return
            }
            
            # Sanitize URL to prevent command injection
            $targetUrl = $Url -replace '[;&|`$()]', ''
            if ($targetUrl -ne $Url) {
                Write-Warning "URL contained potentially dangerous characters and has been sanitized."
            }
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
                    $ytdlArgs = @($searchUrl, '--get-id', '--get-title', '--flat-playlist', '--playlist-items', "1:$MaxResults")
                    if ($finalCookiePath) { $ytdlArgs += "--cookies", $finalCookiePath }
                    $SearchResult = yt-dlp @ytdlArgs 

                    if ($null -eq $SearchResult -or $SearchResult.Count -eq 0) {
                        Write-Host "No playlists found for that search." -ForegroundColor Red 
                        return
                    }

                    Write-Host "Search results found: $($SearchResult.Count / 2)" -ForegroundColor Yellow 

                    $choices = [ordered]@{}

                    for ($i = 0; $i -lt $SearchResult.Count; $i += 2) {
                        if ($i + 1 -lt $SearchResult.Count) {
                            $index = $i / 2
                            $choices.Add($index, [ordered]@{
                                    Title = $SearchResult[$i]
                                    ID    = $SearchResult[$i + 1]
                                })
                        }
                    }

                    $TitleArray = $choices.Values.Title 
                    if ($TitleArray) {
                        if (-not (Get-Command Show-Menu -ErrorAction SilentlyContinue)) {
                            Write-Warning "Show-Menu function not found. Using first result."
                            $resultIndex = 0
                        } else {
                            $resultIndex = Show-Menu -Options $TitleArray -Title "Select a Playlist" -ReturnIndex 
                        }
                        if ($null -eq $resultIndex) { return }

                        $selectedID = $choices[$resultIndex].ID
                        $targetUrl = "https://www.youtube.com/playlist?list=$selectedID"
                        Write-Host "Match [Playlist]: $($choices[$resultIndex].Title)" -ForegroundColor Cyan 
                    } else { return }
                } else {
                    # Standard Video Search
                    $searchUrl = "ytsearch$MaxResults`:$Url"
                    $ytdlArgs = @($searchUrl, '--get-id', '--get-title', '--flat-playlist', '--no-playlist')
                    if ($finalCookiePath) { $ytdlArgs += "--cookies", $finalCookiePath }
                    $SearchResult = yt-dlp @ytdlArgs 
                    
                    $choices = [ordered]@{}

                    for ($i = 0; $i -lt $SearchResult.Count; $i += 2) {
                        if ($i + 1 -lt $SearchResult.Count) {
                            $index = $i / 2
                            $choices.Add($index, [ordered]@{
                                    Title = $SearchResult[$i]
                                    ID    = $SearchResult[$i + 1]
                                })
                        }
                    }
                    $TitleArray = $choices.Values.Title
                    if ($TitleArray) {
                        if (-not (Get-Command Show-Menu -ErrorAction SilentlyContinue)) {
                            Write-Warning "Show-Menu function not found. Using first result."
                            $resultIndex = 0
                        } else {
                            $resultIndex = Show-Menu -Options $TitleArray -Title "Select a Video" -ReturnIndex
                        }
                        if ($null -eq $resultIndex) { return }

                        $targetUrl = "https://www.youtube.com/watch?v=$($choices[$resultIndex].ID)" 
                        Write-Host "Match [Video]: $($choices[$resultIndex].Title)" -ForegroundColor Cyan 
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
                Start-Process -FilePath "mpv" -ArgumentList $processArgs -ErrorAction Stop
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
    Write-Host "    $("{0,-22}" -f "-Format, -f <mode>") Quality (480p, 720p, 1080p, best, audio)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-AudioOnly, -a") Stream audio only" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Background, -b") Run in background process" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Loop, -l") Loop playback infinitely" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-HardwareAccel, -h") Enable hardware acceleration" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-NoSessionId, -nosub") Disable session ID (--sid=1)" -ForegroundColor $cDesc 
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

Export-ModuleMember -Function Start-MPVStream -Alias play 