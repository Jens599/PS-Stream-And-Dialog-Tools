function Join-NativeArgument {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Argument
    )

    ($Argument | ForEach-Object {
        if ($_ -notmatch '[\s"&|<>^]') { return $_ }
        '"' + ($_ -replace '"', '\"') + '"'
    }) -join ' '
}

function Resolve-MPVStreamPlayer {
    param([string]$PlayerPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PlayerPath)) {
        $candidates += $PlayerPath
    }

    $candidates += @('mpv', 'mpvnet.com', 'mpvnet.exe')

    $localMpvNetDir = Join-Path $env:LOCALAPPDATA 'Programs\mpv.net'
    $candidates += @(
        (Join-Path $localMpvNetDir 'mpvnet.com'),
        (Join-Path $localMpvNetDir 'mpvnet.exe')
    )

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }

        if ([System.IO.Path]::IsPathRooted($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [pscustomobject]@{
                Name        = $candidate
                DisplayName = $candidate
                CommandType = 'Application'
            }
        }

        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($command) {
            return [pscustomobject]@{
                Name        = $command.Name
                DisplayName = if ($command.Source) { $command.Source } else { $command.Name }
                CommandType = $command.CommandType
            }
        }
    }

    return $null
}

function Invoke-MPVStreamPlayer {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Player,

        [Parameter(Mandatory = $true)]
        [string[]]$Argument,

        [switch]$Background
    )

    if ($Player.CommandType -eq 'Function') {
        & $Player.Name @Argument
        return
    }

    $startProcessParameters = @{
        FilePath     = $Player.Name
        ArgumentList = Join-NativeArgument $Argument
        ErrorAction  = 'Stop'
    }

    if (-not $Background) {
        $startProcessParameters.Wait = $true
        $startProcessParameters.NoNewWindow = $true
    }

    Start-Process @startProcessParameters
}

function New-MPVStreamMpvArgument {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('PIP', 'Small', 'Medium', 'Max')]
        [string]$Size,

        [Parameter(Mandatory = $true)]
        [ValidateSet('480p', '720p', '1080p', 'best', 'audio')]
        [string]$YtdlFormat,

        [string]$CookiePath,

        [switch]$AudioOnly,

        [switch]$Loop,

        [switch]$HardwareAccel,

        [switch]$Background,

        [switch]$ReversePlaylist,

        [switch]$NoSubtitles,

        [string[]]$SubtitleLanguage,

        [string[]]$CustomArgument
    )

    $formatMap = @{
        '480p'  = 'bestvideo[height<=480]+bestaudio/best'
        '720p'  = 'bestvideo[height<=720]+bestaudio/best'
        '1080p' = 'bestvideo[height<=1080]+bestaudio/best'
        'best'  = 'bestvideo+bestaudio/best'
        'audio' = 'bestaudio/best'
    }

    $arguments = @()
    if (-not $Background) { $arguments += '--terminal=yes' }

    switch ($Size) {
        'PIP' {
            $arguments += '--geometry=320x180-10-10'
            $arguments += '--autofit=320x180'
            $arguments += '--no-border'
            $arguments += '--ontop'
        }
        'Small' {
            $arguments += '--geometry=854x480-10-10'
            $arguments += '--autofit=854x480'
        }
        'Medium' {
            $arguments += '--geometry=1280x720-10-10'
            $arguments += '--autofit=1280x720'
        }
        'Max' { $arguments += '--fullscreen' }
    }

    if ($AudioOnly) { $arguments += '--no-video' }
    if ($Loop) { $arguments += '--loop=inf' }
    if ($HardwareAccel) { $arguments += '--hwdec=auto' }

    if ($ReversePlaylist) {
        $arguments += '--ytdl-raw-options=playlist-items=1-'
        $arguments += '--ytdl-raw-options=playlist-reverse='
    }

    $arguments += "--ytdl-format=$($formatMap[$YtdlFormat])"

    if ($CookiePath) {
        $arguments += "--ytdl-raw-options=cookies=$CookiePath"
    }

    $arguments += '--ytdl-raw-options=no-download-archive='

    if (-not $NoSubtitles) {
        $subtitleValue = if ($SubtitleLanguage) { ($SubtitleLanguage -join ',') } else { 'en' }
        $arguments += "--slang=$subtitleValue"
    }

    if ($CustomArgument) {
        $arguments += $CustomArgument
    }

    return $arguments
}
