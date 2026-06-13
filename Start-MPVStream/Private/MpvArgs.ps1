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

function Format-MPVStreamLaunchCommand {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Player,

        [Parameter(Mandatory = $true)]
        [string[]]$Argument,

        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    "$($Player.DisplayName) $(Join-NativeArgument ($Argument + $Url))"
}

function Split-MPVStreamCommandArgumentText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    @([regex]::Matches($Text, '"(?:\\.|[^"])*"|''(?:''''|[^''])*''|\S+') | ForEach-Object {
        $value = $_.Value
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            return ($value.Substring(1, $value.Length - 2) -replace '\\"', '"')
        }
        if ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) {
            return ($value.Substring(1, $value.Length - 2) -replace "''", "'")
        }
        return $value
    })
}

function Update-MPVStreamLaunchFromConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Player,

        [Parameter(Mandatory = $true)]
        [string[]]$Argument,

        [Parameter(Mandatory = $true)]
        [string]$Url,

        [switch]$Background
    )

    $launch = [pscustomobject]@{
        Player     = $Player
        Arguments  = @($Argument)
        Url        = $Url
        Background = [bool]$Background
        Command    = Format-MPVStreamLaunchCommand -Player $Player -Argument $Argument -Url $Url
    }

    if ($Config.PSObject.Properties.Name -contains 'commandPlayer' -and -not [string]::IsNullOrWhiteSpace($Config.commandPlayer)) {
        $resolvedPlayer = Resolve-MPVStreamPlayer -PlayerPath $Config.commandPlayer
        if (-not $resolvedPlayer) { throw "Configured command player was not found: $($Config.commandPlayer)" }
        $launch.Player = $resolvedPlayer
    }

    if ($Config.PSObject.Properties.Name -contains 'commandReplaceArgument' -and -not [string]::IsNullOrWhiteSpace($Config.commandReplaceArgument)) {
        $launch.Arguments = @(Split-MPVStreamCommandArgumentText $Config.commandReplaceArgument)
    } else {
        if ($Config.PSObject.Properties.Name -contains 'commandPrependArgument' -and -not [string]::IsNullOrWhiteSpace($Config.commandPrependArgument)) {
            $launch.Arguments = @(Split-MPVStreamCommandArgumentText $Config.commandPrependArgument) + @($launch.Arguments)
        }

        if ($Config.PSObject.Properties.Name -contains 'commandAppendArgument' -and -not [string]::IsNullOrWhiteSpace($Config.commandAppendArgument)) {
            $launch.Arguments = @($launch.Arguments) + @(Split-MPVStreamCommandArgumentText $Config.commandAppendArgument)
        }
    }

    if ($Config.PSObject.Properties.Name -contains 'commandUrl' -and -not [string]::IsNullOrWhiteSpace($Config.commandUrl)) { $launch.Url = $Config.commandUrl }
    if ($Config.PSObject.Properties.Name -contains 'commandBackground' -and $null -ne $Config.commandBackground) { $launch.Background = [bool]$Config.commandBackground }

    $launch.Command = Format-MPVStreamLaunchCommand -Player $launch.Player -Argument $launch.Arguments -Url $launch.Url
    return $launch
}

function Test-MPVStreamFormatNoneValue {
    param([object]$Value)

    if ($null -eq $Value) { return $false }
    [string]$Value -match '^(<none>|none|null|omit)$'
}

function Test-MPVStreamFormatAutoValue {
    param([object]$Value)

    if ($null -eq $Value) { return $true }
    [string]::IsNullOrWhiteSpace([string]$Value) -or [string]$Value -match '^(auto|from quality)$'
}

function Test-MPVStreamCommandAutoValue {
    param([object]$Value)

    if ($null -eq $Value) { return $true }
    [string]::IsNullOrWhiteSpace([string]$Value) -or [string]$Value -match '^(auto|from size)$'
}

function Test-MPVStreamCommandEnabledValue {
    param(
        [object]$Value,
        [bool]$AutoValue
    )

    if (Test-MPVStreamFormatNoneValue $Value) { return $false }
    if (Test-MPVStreamCommandAutoValue $Value) { return $AutoValue }
    [string]$Value -match '^(true|t|yes|y|1)$'
}

function New-MPVStreamYtdlFormatExpression {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('480p', '720p', '1080p', 'best', 'audio')]
        [string]$YtdlFormat,

        [switch]$HardwareAccel,

        [string]$VideoSelector,

        [string]$VideoCodecFilter,

        [object]$MaxHeight,

        [string]$AudioSelector,

        [string]$FallbackSelector
    )

    $heightMap = @{
        '480p'  = 480
        '720p'  = 720
        '1080p' = 1080
    }

    $videoSelectorValue = if (Test-MPVStreamFormatAutoValue $VideoSelector) { 'bestvideo' } else { $VideoSelector }
    $audioSelectorValue = if (Test-MPVStreamFormatAutoValue $AudioSelector) { 'bestaudio' } else { $AudioSelector }
    $fallbackSelectorValue = if (Test-MPVStreamFormatNoneValue $FallbackSelector) { $null } elseif (Test-MPVStreamFormatAutoValue $FallbackSelector) { 'best' } else { $FallbackSelector }

    $effectiveMaxHeight = $null
    $omitHeight = Test-MPVStreamFormatNoneValue $MaxHeight
    $parsedMaxHeight = 0
    if (-not $omitHeight -and -not (Test-MPVStreamFormatAutoValue $MaxHeight) -and [int]::TryParse([string]$MaxHeight, [ref]$parsedMaxHeight) -and $parsedMaxHeight -gt 0) {
        $effectiveMaxHeight = $parsedMaxHeight
    } elseif (-not $omitHeight -and $heightMap.ContainsKey($YtdlFormat)) {
        $effectiveMaxHeight = $heightMap[$YtdlFormat]
    }

    $effectiveCodecFilter = $VideoCodecFilter
    if (Test-MPVStreamFormatNoneValue $effectiveCodecFilter) {
        $effectiveCodecFilter = $null
    } elseif ((Test-MPVStreamFormatAutoValue $effectiveCodecFilter) -and $HardwareAccel -and $YtdlFormat -ne 'audio') {
        $effectiveCodecFilter = 'vcodec!*=av01'
    } elseif (Test-MPVStreamFormatAutoValue $effectiveCodecFilter) {
        $effectiveCodecFilter = $null
    }

    if ($YtdlFormat -eq 'audio') {
        if ($fallbackSelectorValue) { return "$audioSelectorValue/$fallbackSelectorValue" }
        return $audioSelectorValue
    }

    $videoFilters = @()
    if (-not [string]::IsNullOrWhiteSpace($effectiveCodecFilter)) { $videoFilters += "[$effectiveCodecFilter]" }
    if ($effectiveMaxHeight) { $videoFilters += "[height<=$effectiveMaxHeight]" }

    $videoFormat = "$videoSelectorValue$($videoFilters -join '')+$audioSelectorValue"
    if (-not $fallbackSelectorValue) {
        return $videoFormat
    }

    if (-not [string]::IsNullOrWhiteSpace($effectiveCodecFilter)) {
        $fallbackFilters = @("[$effectiveCodecFilter]")
        if ($effectiveMaxHeight) { $fallbackFilters += "[height<=$effectiveMaxHeight]" }
        $heightFallback = if ($effectiveMaxHeight) { "/$fallbackSelectorValue[height<=$effectiveMaxHeight]" } else { '' }
        return "$videoFormat/$fallbackSelectorValue$($fallbackFilters -join '')$heightFallback"
    }

    return "$videoFormat/$fallbackSelectorValue"
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
        Write-Host "→ MPV window opened; loading URL..." -ForegroundColor Cyan
        if (-not $Background) { Start-Sleep -Milliseconds 200 }
        Write-Host "→ Sending URL to MPV..." -ForegroundColor Cyan
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

        [string[]]$CustomArgument,

        [string]$YtdlVideoSelector,

        [string]$YtdlVideoCodecFilter,

        [object]$YtdlMaxHeight,

        [string]$YtdlAudioSelector,

        [string]$YtdlFallbackSelector,

        [object]$CommandTerminal,

        [object]$CommandGeometry,

        [object]$CommandAutofit,

        [object]$CommandNoBorder,

        [object]$CommandOntop,

        [object]$CommandHwdec,

        [object]$CommandSavePosition,

        [object]$CommandWatchLaterOptions,

        [bool]$CommandNoDownloadArchive = $true
    )

    $ytdlFormatExpression = New-MPVStreamYtdlFormatExpression -YtdlFormat $YtdlFormat -HardwareAccel:($HardwareAccel -and -not $AudioOnly) -VideoSelector $YtdlVideoSelector -VideoCodecFilter $YtdlVideoCodecFilter -MaxHeight $YtdlMaxHeight -AudioSelector $YtdlAudioSelector -FallbackSelector $YtdlFallbackSelector

    $sizeGeometry = @{
        'PIP'    = '320x180-10-10'
        'Small'  = '854x480-10-10'
        'Medium' = '1280x720-10-10'
    }

    $sizeAutofit = @{
        'PIP'    = '320x180'
        'Small'  = '854x480'
        'Medium' = '1280x720'
    }

    $arguments = @()
    if (Test-MPVStreamCommandEnabledValue -Value $CommandTerminal -AutoValue:(-not [bool]$Background)) { $arguments += '--terminal=yes' }

    switch ($Size) {
        'PIP' {
            if (-not (Test-MPVStreamFormatNoneValue $CommandGeometry)) {
                $geometry = if (Test-MPVStreamCommandAutoValue $CommandGeometry) { $sizeGeometry[$Size] } else { [string]$CommandGeometry }
                if ($geometry) { $arguments += "--geometry=$geometry" }
            }
            if (-not (Test-MPVStreamFormatNoneValue $CommandAutofit)) {
                $autofit = if (Test-MPVStreamCommandAutoValue $CommandAutofit) { $sizeAutofit[$Size] } else { [string]$CommandAutofit }
                if ($autofit) { $arguments += "--autofit=$autofit" }
            }
            if (Test-MPVStreamCommandEnabledValue -Value $CommandNoBorder -AutoValue:$true) { $arguments += '--no-border' }
            if (Test-MPVStreamCommandEnabledValue -Value $CommandOntop -AutoValue:$true) { $arguments += '--ontop' }
        }
        'Small' {
            if (-not (Test-MPVStreamFormatNoneValue $CommandGeometry)) {
                $geometry = if (Test-MPVStreamCommandAutoValue $CommandGeometry) { $sizeGeometry[$Size] } else { [string]$CommandGeometry }
                if ($geometry) { $arguments += "--geometry=$geometry" }
            }
            if (-not (Test-MPVStreamFormatNoneValue $CommandAutofit)) {
                $autofit = if (Test-MPVStreamCommandAutoValue $CommandAutofit) { $sizeAutofit[$Size] } else { [string]$CommandAutofit }
                if ($autofit) { $arguments += "--autofit=$autofit" }
            }
            if (Test-MPVStreamCommandEnabledValue -Value $CommandNoBorder -AutoValue:$false) { $arguments += '--no-border' }
            if (Test-MPVStreamCommandEnabledValue -Value $CommandOntop -AutoValue:$false) { $arguments += '--ontop' }
        }
        'Medium' {
            if (-not (Test-MPVStreamFormatNoneValue $CommandGeometry)) {
                $geometry = if (Test-MPVStreamCommandAutoValue $CommandGeometry) { $sizeGeometry[$Size] } else { [string]$CommandGeometry }
                if ($geometry) { $arguments += "--geometry=$geometry" }
            }
            if (-not (Test-MPVStreamFormatNoneValue $CommandAutofit)) {
                $autofit = if (Test-MPVStreamCommandAutoValue $CommandAutofit) { $sizeAutofit[$Size] } else { [string]$CommandAutofit }
                if ($autofit) { $arguments += "--autofit=$autofit" }
            }
            if (Test-MPVStreamCommandEnabledValue -Value $CommandNoBorder -AutoValue:$false) { $arguments += '--no-border' }
            if (Test-MPVStreamCommandEnabledValue -Value $CommandOntop -AutoValue:$false) { $arguments += '--ontop' }
        }
        'Max' { $arguments += '--fullscreen' }
    }

    if ($AudioOnly) { $arguments += '--no-video' }
    if ($Loop) { $arguments += '--loop=inf' }
    if (-not (Test-MPVStreamFormatNoneValue $CommandHwdec)) {
        if (Test-MPVStreamCommandAutoValue $CommandHwdec) {
            if ($HardwareAccel) { $arguments += '--hwdec=auto-safe' }
        } elseif ([string]$CommandHwdec -ne 'no') {
            $arguments += "--hwdec=$CommandHwdec"
        }
    }
    if (Test-MPVStreamCommandEnabledValue -Value $CommandSavePosition -AutoValue:([bool]$RememberPlaybackSpeed)) {
        $arguments += '--save-position-on-quit'
    }

    if (-not (Test-MPVStreamFormatNoneValue $CommandWatchLaterOptions)) {
        $watchLaterOptions = if (Test-MPVStreamCommandAutoValue $CommandWatchLaterOptions) { 'start,speed' } else { [string]$CommandWatchLaterOptions }
        if ($RememberPlaybackSpeed -or -not (Test-MPVStreamCommandAutoValue $CommandWatchLaterOptions)) {
            $arguments += "--watch-later-options=$watchLaterOptions"
        }
    }

    if ($ReversePlaylist) {
        $arguments += '--ytdl-raw-options=playlist-items=1-'
        $arguments += '--ytdl-raw-options=playlist-reverse='
    }

    $arguments += "--ytdl-format=$ytdlFormatExpression"

    if ($CookiePath) {
        $arguments += "--ytdl-raw-options=cookies=$CookiePath"
    }

    if ($CommandNoDownloadArchive) { $arguments += '--ytdl-raw-options=no-download-archive=' }

    if (-not $NoSubtitles) {
        $subtitleValue = if ($SubtitleLanguage) { ($SubtitleLanguage -join ',') } else { 'en' }
        $arguments += "--slang=$subtitleValue"
    }

    if ($CustomArgument) {
        $arguments += $CustomArgument
    }

    return $arguments
}
