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

    if ($Background) {
        $processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $processStartInfo.FileName = $Player.Name
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.CreateNoWindow = $true

        foreach ($item in $Argument) {
            [void]$processStartInfo.ArgumentList.Add($item)
        }

        $process = [System.Diagnostics.Process]::Start($processStartInfo)
        if ($process) { $process.Dispose() }
        return
    }

    $startProcessParameters = @{
        FilePath     = $Player.Name
        ArgumentList = Join-NativeArgument $Argument
        ErrorAction  = 'Stop'
    }

    $startProcessParameters.Wait = $true
    $startProcessParameters.NoNewWindow = $true

    Start-Process @startProcessParameters
}

function Start-MPVStreamPlayerProcess {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Player,

        [Parameter(Mandatory = $true)]
        [string[]]$Argument,

        [switch]$Background
    )

    $processStartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processStartInfo.FileName = $Player.Name
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.CreateNoWindow = [bool]$Background

    foreach ($item in $Argument) {
        [void]$processStartInfo.ArgumentList.Add($item)
    }

    return [System.Diagnostics.Process]::Start($processStartInfo)
}

function Send-MPVStreamIpcCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PipeName,

        [Parameter(Mandatory = $true)]
        [object[]]$Command,

        [int]$TimeoutMilliseconds = 10000
    )

    $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $PipeName, [System.IO.Pipes.PipeDirection]::Out)
    try {
        $client.Connect($TimeoutMilliseconds)
        $writer = [System.IO.StreamWriter]::new($client, [System.Text.UTF8Encoding]::new($false))
        try {
            $payload = @{ command = $Command } | ConvertTo-Json -Compress
            $writer.WriteLine($payload)
            $writer.Flush()
        } finally {
            $writer.Dispose()
        }
    } finally {
        $client.Dispose()
    }
}

function Invoke-MPVStreamPlayerWithUrl {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Player,

        [Parameter(Mandatory = $true)]
        [string[]]$Argument,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [switch]$Background
    )

    $isWindowsPlatform = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
    if ($Player.CommandType -eq 'Function' -or -not $isWindowsPlatform) {
        Invoke-MPVStreamPlayer -Player $Player -Argument ($Argument + $Url) -Background:$Background
        return
    }

    $pipeName = "mpvstream-$PID-$([guid]::NewGuid().ToString('N'))"
    $startupArguments = $Argument + @(
        '--force-window=yes',
        '--idle=once',
        "--input-ipc-server=\\.\pipe\$pipeName"
    )

    $process = Start-MPVStreamPlayerProcess -Player $Player -Argument $startupArguments -Background:$Background
    try {
        Send-MPVStreamIpcCommand -PipeName $pipeName -Command @('loadfile', $Url, 'replace')
        if ($Background) { return }
        $process.WaitForExit()
    } finally {
        if ($process) { $process.Dispose() }
    }
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

        [bool]$RememberPlaybackSpeed = $true,

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
    if ($RememberPlaybackSpeed) {
        $arguments += '--save-position-on-quit'
        $arguments += '--watch-later-options=start,speed'
    }

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
