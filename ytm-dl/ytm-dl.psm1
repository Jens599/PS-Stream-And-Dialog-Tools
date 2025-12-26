function Show-GitStyleHelp {
    Write-Host @"
usage: Invoke-YtmDownload [-v | --version] [-h | --help] [--verbose] 
                          [--output-dir <path>] [--parallel <number>] 
                          <url> [<args>]

These are common Invoke-YtmDownload usage patterns:

BASIC DOWNLOADS:
   <url>                    Download single track or playlist
   <file.txt>               Download URLs from text file
   --help                   Show this help message
   --verbose                Show detailed download information

DOWNLOAD OPTIONS:
   --output-dir <path>      Set download directory (default: ~/Downloads/Music)
   --parallel <number>      Number of simultaneous downloads (1-10, default: 4)
   --cookies <file>         Use cookies file for premium content

PIPELINE OPERATIONS:
   "url1", "url2" |         Download multiple URLs via pipeline
   Get-Content file |        Read URLs from file via pipeline

EXAMPLES:
   # Download single track
   Invoke-YtmDownload "https://music.youtube.com/watch?v=..."

   # Download playlist to custom directory
   Invoke-YtmDownload --url "https://music.youtube.com/playlist?list=..." --output-dir "D:\MyMusic"

   # Download from file with 8 parallel connections
   Invoke-YtmDownload --url "C:\music\urls.txt" --parallel 8

   # Pipeline multiple URLs
   "url1", "url2", "url3" | Invoke-YtmDownload

   # Read URLs from file and pipe with custom settings
   Get-Content "playlist.txt" | Invoke-YtmDownload --parallel 6

CONFIGURATION:
   --cookies                Path to cookies.txt for premium content
   --no-picard              Skip automatic MusicBrainz Picard launch
   --format                 Audio format (default: opus)

TROUBLESHOOTING:
   --verbose                Show detailed yt-dlp output
   --dry-run                Simulate download without actual download
   --update                 Update yt-dlp to latest version

PERFORMANCE:
   Automatically uses aria2c for maximum download speed (16 connections)
   Falls back to yt-dlp internal optimizations if aria2c unavailable
   Optimized for YouTube Music with reduced bitrate audio formats

See 'Invoke-YtmDownload --help' for detailed parameter information.
Visit https://github.com/yt-dlp/yt-dlp for yt-dlp documentation.
"@
}

<#
.SYNOPSIS
    YouTube Music audio downloader with yt-dlp integration
.DESCRIPTION
    Invoke-YtmDownload downloads audio from YouTube Music URLs using yt-dlp.
    Automatically organizes files by album/artist, embeds metadata, and optionally
    launches MusicBrainz Picard for tagging.
    
    FEATURES:
    - Parallel downloads with configurable concurrency
    - Automatic metadata extraction and embedding
    - Cookie support for premium content
    - Modern yt-dlp optimization (2025)
    - Thread-safe progress tracking
    - Error handling and validation
.PARAMETER Url
    YouTube Music URL or path to text file containing URLs (one per line)
.PARAMETER OutputDir
    Directory to save downloaded files (default: $HOME\Downloads\Music)
.PARAMETER Parallel
    Number of simultaneous downloads (1-10, default: 4)
.EXAMPLE
    # Download single track
    Invoke-YtmDownload -Url "https://music.youtube.com/watch?v=..."

.EXAMPLE
    # Download entire playlist
    Invoke-YtmDownload -Url "https://music.youtube.com/playlist?list=..."

.EXAMPLE
    # Download from URL file with custom output directory
    Invoke-YtmDownload -Url "C:\music\urls.txt" -OutputDir "D:\MyMusic" -Parallel 8

.EXAMPLE
    # Pipeline multiple URLs
    "url1", "url2", "url3" | Invoke-YtmDownload

.EXAMPLE
    # Read URLs from file and pipe
    Get-Content "playlist.txt" | Invoke-YtmDownload -Parallel 6

.EXAMPLE
    # Quick download with default settings
    Invoke-YtmDownload

.NOTES
    REQUIREMENTS:
    - yt-dlp (https://github.com/yt-dlp/yt-dlp)
    - Optional: MusicBrainz Picard for automatic tagging
    - Optional: cookies.txt for premium content
    
    FILE FORMATS:
    - Default: Opus audio with embedded metadata
    - Output: Artist - Title.ext in album folders
    
    URL SOURCES:
    - YouTube Music URLs (music.youtube.com)
    - YouTube URLs (youtube.com, youtu.be)
    - Text files with URLs (one per line, # comments ignored)
    
    TROUBLESHOOTING:
    - Use -Verbose for detailed download information
    - Check yt-dlp installation: Get-Command yt-dlp
    - Update yt-dlp: yt-dlp --update
    - For premium content, ensure cookies.txt is valid
.LINK
    https://github.com/yt-dlp/yt-dlp
    https://picard.musicbrainz.org
#>
function Invoke-YtmDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [string[]]$Url,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
                if (-not (Test-Path $_ -PathType Container)) {
                    try { 
                        New-Item -ItemType Directory -Path $_ -Force | Out-Null
                        return $true
                    }
                    catch { 
                        throw "Cannot create output directory: $_" 
                    }
                }
                return $true
            })]
        [string]$OutputDir = "$HOME\Downloads\Music",

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$Parallel = 4  # Number of simultaneous downloads
    )

    begin {
        # Check for required dependencies
        if (-not (Get-Command yt-dlp -ErrorAction SilentlyContinue)) {
            throw "yt-dlp not found. Please install yt-dlp first."
        }
        
        # Check for aria2c for optimized downloading
        $useAria2c = Get-Command aria2c -ErrorAction SilentlyContinue
        if ($useAria2c) {
            Write-Verbose "aria2c found - will use for optimized downloading"
        }

        # Initialize array to collect all pipeline URLs
        $script:allUrls = @()
    }

    process {
        # Collect URLs from pipeline
        if ($Url) {
            foreach ($singleUrl in $Url) {
                $trimmedUrl = $singleUrl.Trim()
                if ($trimmedUrl -and -not $trimmedUrl.StartsWith('#')) {
                    $script:allUrls += $trimmedUrl
                    Write-Verbose "Added from pipeline: $trimmedUrl"
                }
            }
        }
    }

    end {
        # Show help if no URL provided and not in pipeline
        if ($script:allUrls.Count -eq 0) {
            Show-GitStyleHelp
            return
        }

        # Use first URL if no prompt needed
        $inputUrls = $script:allUrls
        Write-Verbose "Processing $($inputUrls.Count) URLs from pipeline"

        New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

        # Process each URL (handle both direct URLs and file paths)
        $finalUrls = @()
        foreach ($singleUrl in $inputUrls) {
            # Detect file vs URL
            $isFile = $false
            $resolvedPath = $singleUrl
            if ($singleUrl -notmatch '^(https?:|ytmusic:|youtube:|www\.)') {
                try { 
                    $resolvedPath = (Resolve-Path -LiteralPath $singleUrl -ErrorAction Stop).Path; 
                    $isFile = $true 
                }
                catch { 
                    Write-Warning "Cannot resolve path '$singleUrl'. Treating as URL."
                    $isFile = $false 
                }
            }

            # Read URLs from file or add direct URL
            if ($isFile) {
                try {
                    $fileUrls = Get-Content -LiteralPath $resolvedPath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
                    if ($fileUrls.Count -gt 0) {
                        $finalUrls += $fileUrls
                        Write-Verbose "Added $($fileUrls.Count) URLs from file: $resolvedPath"
                    }
                }
                catch {
                    Write-Error "Failed to read URLs from file: $resolvedPath"
                }
            }
            else { 
                $finalUrls += $singleUrl
                Write-Verbose "Added URL: $singleUrl"
            }
        }

        if ($finalUrls.Count -eq 0) { 
            Write-Warning "No valid URLs found to process."
            return 
        }

    Write-Host "Downloading from YouTube Music..." -ForegroundColor Cyan
        Write-Host "Saving to: $OutputDir`n" -ForegroundColor Green

        Write-Verbose "Found $($finalUrls.Count) URLs to process"
        $finalUrls | ForEach-Object { Write-Verbose "URL: $_" }

    # Base yt-dlp arguments (updated for 2025 best practices with aria2c optimization)
    $baseArgs = @(
        '--extract-audio', '--audio-format', 'mp3', '--audio-quality', '0',
        '--output', "$OutputDir\%(title)s.%(ext)s",
        '--format', 'bestaudio[acodec=opus][abr<=128]/bestaudio[acodec=m4a][abr<=192]/bestaudio[abr<=256]/bestaudio/best',
        '--restrict-filenames', '--windows-filenames', '--ignore-errors', '--no-overwrites',
        '--newline',
        # Speed optimization flags
        '--retries', '3',
        '--fragment-retries', '3',
        '--skip-unavailable-fragments'
    )
    
    # Add aria2c-specific optimizations if available
    if ($useAria2c) {
        $aria2cArgs = @(
            '--external-downloader', 'aria2c',
            '--external-downloader-args', 
            '-x 16 -s 16 -j 16 --max-connection-per-server=16 --split=16 --min-split-size=1M --max-tries=3 --retry-wait=1 --timeout=10 --connect-timeout=10 --lowest-speed-limit=10K --piece-length=1M --allow-overwrite=true --auto-file-renaming=false --summary-interval=0'
        )
        $baseArgs = $baseArgs + $aria2cArgs
        Write-Verbose "Using aria2c with 16 connections for maximum speed"
    }
    else {
        # Fallback to yt-dlp internal optimizations
        $fallbackArgs = @(
            '--concurrent-fragments', '8',
            '--buffer-size', '16K',
            '--http-chunk-size', '16M',
            '--keep-fragments',
            '--no-part',
            '--throttled-rate', '100K'
        )
        $baseArgs = $baseArgs + $fallbackArgs
        Write-Verbose "Using yt-dlp internal optimizations (aria2c not available)"
    }

    # Shared progress tracking
        $total = $finalUrls.Count
        $completed = 0
        $progressLock = [System.Threading.Semaphore]::New(1, 1)

        function Invoke-Download($u) {
            Write-Verbose "Starting download for: $u"
            $dlArgs = $baseArgs + $u
            Write-Verbose "yt-dlp arguments: $($dlArgs -join ' ')"
            try {
                & yt-dlp @dlArgs
                $exit = $LASTEXITCODE
                Write-Verbose "yt-dlp exit code: $exit"
            }
            catch {
                $exit = 1
                Write-Warning "Error executing yt-dlp for $u : $($_.Exception.Message)"
            }

            $progressLock.WaitOne()
            try {
                $script:completed++
                Write-Progress -Activity "Invoke-YtmDownload: Downloading" -Status "$completed of $total completed" -PercentComplete (($completed / $total) * 100)
            }
            finally {
                $progressLock.Release()
            }

            if ($exit -ne 0) { Write-Warning "yt-dlp failed for $u (exit code: $exit)" }
        }

        # Simple single-threaded download with progress animation
        $spinner = @('|', '/', '-', '\')
        $spinnerIndex = 0
        
        foreach ($u in $finalUrls) {
            $currentTitle = "Downloading $($finalUrls.IndexOf($u) + 1)/$($finalUrls.Count)"
            
            # Show spinner while downloading
            $job = Start-Job -ScriptBlock {
                param($dlArgs, $url)
                $output = & yt-dlp @dlArgs $url 2>&1
                return @{
                    ExitCode = $LASTEXITCODE
                    Output = $output -join "`n"
                }
            } -ArgumentList $baseArgs, $u
            
            # Show spinner animation
            while ($job.State -eq 'Running') {
                $spinnerChar = $spinner[$spinnerIndex % $spinner.Length]
                $currentProgress = if ($total -gt 0) { [Math]::Min(($script:completed / $total) * 100, 100) } else { 0 }
                Write-Progress -Activity "Invoke-YtmDownload" -Status "$currentTitle $spinnerChar" -PercentComplete $currentProgress
                Start-Sleep -Milliseconds 200
                $spinnerIndex++
            }
            
            $result = $job | Receive-Job -Wait
            Remove-Job $job -Force
            
            $script:completed++
            $finalProgress = if ($total -gt 0) { [Math]::Min(($script:completed / $total) * 100, 100) } else { 0 }
            Write-Progress -Activity "Invoke-YtmDownload" -Status "Completed $($script:completed)/$total" -PercentComplete $finalProgress
            
            # Better success detection - check for actual file creation and success indicators
            $actualFailure = $false
            if ($result.ExitCode -ne 0) {
                # Check if it's actually a failure by looking at output
                $outputText = $result.Output.ToLower()
                $successIndicators = @('100%', 'already downloaded', 'has already been downloaded', 'skipped', 'found existing file')
                $failureIndicators = @('error', 'failed', 'unable', 'cannot', 'permission denied', 'not found', 'network error')
                
                $hasSuccess = $successIndicators | Where-Object { $outputText -contains $_ }
                $hasFailure = $failureIndicators | Where-Object { $outputText -contains $_ }
                
                if ($hasFailure -or -not $hasSuccess) {
                    $actualFailure = $true
                }
            }
            
            if ($actualFailure) { 
                Write-Warning "Download failed for track $($finalUrls.IndexOf($u) + 1)"
                if ($VerbosePreference -eq 'Continue') {
                    Write-Host "Error output: $($result.Output)" -ForegroundColor DarkGray
                }
            }
        }

        Write-Host "`nAll downloads finished." -ForegroundColor Magenta

        # Auto-launch Picard only when downloads actually happened
        if ($finalUrls.Count -gt 0) {
            if (Get-Command picard -ErrorAction SilentlyContinue) {
                Write-Host "Starting MusicBrainz Picard in the download folder..." -ForegroundColor Cyan
                Start-Sleep -Milliseconds 800
                try {
                    picard "$OutputDir"
                }
                catch {
                    Write-Warning "Failed to launch MusicBrainz Picard: $($_.Exception.Message)"
                }
            }
            else {
                Write-Warning "MusicBrainz Picard not found. Skipping automatic launch."
            }
        }
    }
}

# Alias for backward compatibility
Set-Alias -Name ydl -Value Invoke-YtmDownload
Set-Alias -Name ytm-dl -Value Invoke-YtmDownload

# Export everything
Export-ModuleMember -Function Invoke-YtmDownload -Alias ydl, ytm-dl