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
    'Private\Cookies.ps1'
    'Private\History.ps1'
    'Private\MpvArgs.ps1'
    'Private\Doctor.ps1'
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
        [Alias('cfg')]
        [switch]$Config,

        [Parameter()]
        [Alias('doc')]
        [switch]$Doctor,

        [Parameter()]
        [Alias('cfgex')]
        [string]$ConfigExport,

        [Parameter()]
        [Alias('cfgim')]
        [string]$ConfigImport,

        [Alias('s')]
        [switch]$Search,

        [Parameter()]
        [Alias('Homepage')]
        [switch]$Home,

        [Alias('p')]
        [switch]$Playlist,

        [Parameter()]
        [Alias('fi')]
        [switch]$First,

        [Parameter()]
        [ValidateSet('Video', 'Playlist', 'Channel')]
        [Alias('t')]
        [string]$Type,

        [Parameter()]
        [Alias('ma', 'mpvarg')]
        [string[]]$MpvArgument,

        [Parameter()]
        [Alias('dr')]
        [switch]$DryRun,

        [Parameter()]
        [Alias('pt')]
        [switch]$PassThru,

        [Parameter()]
        [Alias('so')]
        [switch]$SelectOnly,

        [Parameter()]
        [Alias('cu')]
        [switch]$CopyUrl,

        [Parameter()]
        [Alias('o')]
        [switch]$Open,

        [Parameter()]
        [Alias('cb')]
        [switch]$Clipboard,

        [Parameter()]
        [Alias('hi')]
        [switch]$History,

        [Parameter()]
        [Alias('ch')]
        [switch]$ClearHistory,

        [Parameter()]
        [Alias('la')]
        [switch]$Last,

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
        [Alias('ns', 'nosub')]
        [switch]$NoSubtitles,

        [Parameter()]
        [Alias('sl', 'slang')]
        [string[]]$SubtitleLanguage,

        [Parameter()]
        [ValidateRange(1, 50)]
        [Alias('max')]
        [int]$MaxResults = 10
    )

    process {
        $configData = Read-MPVStreamConfig

        if ($Doctor) {
            Invoke-MPVStreamDoctor -Config $configData -ScriptRoot $PSScriptRoot
            return
        }

        if ($ConfigExport) {
            Export-MPVStreamConfig -Config $configData -Path $ConfigExport
            return
        }

        if ($ConfigImport) {
            Import-MPVStreamConfig -Path $ConfigImport
            return
        }

        if ($Config) {
            Invoke-MPVStreamConfig -Config $configData
            return
        }

        if ($ClearHistory) {
            Clear-MPVStreamHistory
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

        if ($Clipboard) {
            $Url = Get-MPVStreamClipboardText
            if ([string]::IsNullOrWhiteSpace($Url)) { return }
        }

        if ($Last) {
            $lastItem = Get-MPVStreamLastHistoryItem
            if ($null -eq $lastItem) {
                Write-Warning 'Playback history is empty.'
                return
            }

            $Url = $lastItem.Url
            $replayTitle = $lastItem.Title
            $replayType = $lastItem.Type
            $Search = $false
            Write-Host "→ Last: $($lastItem.Title)" -ForegroundColor Cyan
        }

        if ($History) {
            $historyItem = Select-MPVStreamHistoryItem -Config $configData -Type $Type
            if ($null -eq $historyItem) { return }

            $Url = $historyItem.Url
            $replayTitle = $historyItem.Title
            $replayType = $historyItem.Type
            $Search = $false
            Write-Host "→ History: $($historyItem.Title)" -ForegroundColor Cyan
        }

        # --- 0. Help Check / Config Mode ---
        $isConfigOnly = [string]::IsNullOrWhiteSpace($Url) -and $CookiePath -and -not $Home
        if ([string]::IsNullOrWhiteSpace($Url)) {
            # If only cookie path is provided, enter config mode
            if ($CookiePath -and -not $Home) {
                Write-Host "→ Configuration mode: Testing cookie path" -ForegroundColor Cyan
                # Cookie configuration logic will run below
            } elseif ($Home) {
                $Url = 'YouTube Home'
            } else {
                Write-MPVStreamHelp
                return
            }
        }

        # --- 1. Dependency Checks ---
        $requiresPlayer = -not ($SelectOnly -or $CopyUrl -or $Open)
        $player = if ($requiresPlayer) { Resolve-MPVStreamPlayer -PlayerPath $configData.playerPath } else { $null }
        if (-not $isConfigOnly -and $requiresPlayer -and -not $player) {
            Write-Error "No media player found. Configure one with play -Config, or install mpv/mpv.net in PATH."
            return 
        }
        
        # Only check yt-dlp dependency if fetching YouTube listings.
        if (($Search -or $Home) -and -not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
            Write-Error "yt-dlp is missing from PATH. Please install yt-dlp for search/homepage functionality."
            return 
        }
        
        # --- Cookie Configuration ---
        $finalCookiePath = Resolve-MPVStreamCookiePath -ConfigData $configData -CookiePath $CookiePath -ScriptRoot $PSScriptRoot

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
        if (-not $Search -and -not $Home) {
            $parsedUri = $null
            if (-not [uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsedUri) -or $parsedUri.Scheme -notin @('http', 'https')) {
                Write-Error "Invalid URL format. URLs should start with http:// or https://"
                return
            }
            $targetUrl = $Url
            $historyTitle = if ($replayTitle) { $replayTitle } else { $Url }
            $historyType = if ($replayType) { $replayType } else { 'Direct' }
        } elseif ($Home) {
            $targetUrl = 'https://www.youtube.com/'
            $historyTitle = 'YouTube Home'
            $historyType = 'Home'
        } else {
            $targetUrl = $Url
            $historyTitle = $Url
            $historyType = 'Search'
        }
        # --- 3. Search Logic ---
        if ($Search -or $Home) {
            try {
                $encodedQuery = if ($Home) { $null } else { [uri]::EscapeDataString($Url) }
                
                if ($Home) {
                    $selectedResult = Select-MPVStreamYouTubeSearchResult -Home -MaxResults $MaxResults -CookiePath $finalCookiePath -Type $Type -Config $configData -First:$First -Title 'YouTube Home' -EmptyMessage 'No homepage videos found.'
                    if ($null -eq $selectedResult) { return }

                    $targetUrl = $selectedResult.Url
                    $historyTitle = $selectedResult.Title
                    $historyType = $selectedResult.Type
                    Write-Host "Match [$($selectedResult.Type)]: $($selectedResult.Title)" -ForegroundColor Cyan
                } elseif ($Playlist) {
                    # Search for Playlists specifically using the 'sp' parameter.
                    $selectedResult = Select-MPVStreamYouTubeSearchResult -EncodedQuery $encodedQuery -Playlist:$Playlist -MaxResults $MaxResults -CookiePath $finalCookiePath -Type $Type -Config $configData -First:$First -Title "Playlist Results: $Url" -EmptyMessage 'No playlists found for that search.'
                    if ($null -eq $selectedResult) { return }

                    $targetUrl = $selectedResult.Url
                    $historyTitle = $selectedResult.Title
                    $historyType = $selectedResult.Type
                    Write-Host "Match [$($selectedResult.Type)]: $($selectedResult.Title)" -ForegroundColor Cyan
                } else {
                    # Standard mixed search: videos, playlists, and channels.
                    $selectedResult = Select-MPVStreamYouTubeSearchResult -EncodedQuery $encodedQuery -Playlist:$Playlist -MaxResults $MaxResults -CookiePath $finalCookiePath -Type $Type -Config $configData -First:$First -Title "Search Results: $Url" -EmptyMessage 'No results found for that search.'
                    if ($null -eq $selectedResult) { return }

                    $targetUrl = $selectedResult.Url
                    $historyTitle = $selectedResult.Title
                    $historyType = $selectedResult.Type
                    Write-Host "Match [$($selectedResult.Type)]: $($selectedResult.Title)" -ForegroundColor Cyan
                }
            } catch {
                Write-Error "Search failed: $($_.Exception.Message)" 
                return
            }
        }

        if ($SelectOnly) {
            [pscustomobject]@{
                Url   = $targetUrl
                Title = $historyTitle
                Type  = $historyType
            }
            return
        }

        if ($CopyUrl) {
            Set-Clipboard -Value $targetUrl
            Write-Host "→ Copied URL: $targetUrl" -ForegroundColor Green
            return
        }

        if ($Open) {
            Start-Process $targetUrl
            Write-Host "→ Opened URL: $targetUrl" -ForegroundColor Green
            return
        }

        # --- 4. Format Mapping ---
        # --- 5. Argument Construction ---
        $mpvArgs = New-MPVStreamMpvArgument -Size $Size -YtdlFormat $YtdlFormat -CookiePath $finalCookiePath -AudioOnly:$AudioOnly -Loop:$Loop -HardwareAccel:$HardwareAccel -Background:$Background -ReversePlaylist:$ReversePlaylist -NoSubtitles:$NoSubtitles -SubtitleLanguage $SubtitleLanguage -CustomArgument $MpvArgument

        
        
        Write-Host "→ Launching:" -ForegroundColor Green 
        Write-Host "    $($player.DisplayName) $($mpvArgs -join ' ') $targetUrl" -ForegroundColor Yellow 

        if ($DryRun) {
            Write-Host "→ Dry run: MPV was not started" -ForegroundColor Cyan
            if ($PassThru) {
                [pscustomobject]@{
                    Player    = $player.DisplayName
                    Arguments = $mpvArgs
                    Url       = $targetUrl
                    Title     = $historyTitle
                    Type      = $historyType
                    Command   = "$($player.DisplayName) $($mpvArgs -join ' ') $targetUrl"
                }
            }
            return
        }

        Add-MPVStreamHistoryItem -Url $targetUrl -Title $historyTitle -Type $historyType

        # --- 6. Execution ---
        if ($Background) {
            try {
                $processArgs = $mpvArgs + $targetUrl
                Invoke-MPVStreamPlayer -Player $player -Argument $processArgs -Background
                Write-Host "→ Player started in background" -ForegroundColor Green
            } catch {
                Write-Error "Failed to start player in background: $($_.Exception.Message)"
            }
        } else {
            try {
                Invoke-MPVStreamPlayer -Player $player -Argument ($mpvArgs + $targetUrl)
            } catch {
                Write-Error "Failed to start player: $($_.Exception.Message)"
            }
        }
    }
}

Export-ModuleMember -Function Start-MPVStream -Alias play
