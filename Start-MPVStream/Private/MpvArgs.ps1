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
        'Small' { $arguments += '--autofit=854x480' }
        'Medium' { $arguments += '--autofit=1280x720' }
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
