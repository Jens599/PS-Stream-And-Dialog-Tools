function New-MPVStreamDoctorResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Detail
    )

    [pscustomobject]@{
        Name   = $Name
        Status = $Status
        Detail = $Detail
    }
}

function Test-MPVStreamCommandDiagnostic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($command) {
        $detail = if ($command.Source) { $command.Source } else { $command.Name }
        return (New-MPVStreamDoctorResult -Name $Name -Status 'OK' -Detail $detail)
    }

    New-MPVStreamDoctorResult -Name $Name -Status 'Missing' -Detail "$CommandName not found in PATH"
}

function Invoke-MPVStreamDoctor {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )

    $results = @()

    $player = Resolve-MPVStreamPlayer -PlayerPath $Config.playerPath
    if ($player) {
        $results += New-MPVStreamDoctorResult -Name 'Player' -Status 'OK' -Detail $player.DisplayName
    } else {
        $results += New-MPVStreamDoctorResult -Name 'Player' -Status 'Missing' -Detail 'Install mpv/mpv.net or set Player Path in -Config'
    }

    $results += Test-MPVStreamCommandDiagnostic -Name 'yt-dlp' -CommandName 'yt-dlp'
    $results += Test-MPVStreamCommandDiagnostic -Name 'fzf' -CommandName 'fzf'
    $results += Test-MPVStreamCommandDiagnostic -Name 'Out-ConsoleGridView' -CommandName 'Out-ConsoleGridView'

    $cookiePath = Resolve-MPVStreamCookiePath -ConfigData $Config -ScriptRoot $ScriptRoot
    if ($cookiePath) {
        $results += New-MPVStreamDoctorResult -Name 'Cookies' -Status 'OK' -Detail $cookiePath
    } else {
        $results += New-MPVStreamDoctorResult -Name 'Cookies' -Status 'Optional' -Detail 'No cookie file configured or discovered'
    }

    $configPath = Get-MPVStreamConfigPath
    $configStatus = if (Test-Path -LiteralPath $configPath -PathType Leaf) { 'OK' } else { 'Optional' }
    $results += New-MPVStreamDoctorResult -Name 'Config Path' -Status $configStatus -Detail $configPath

    $historyPath = Get-MPVStreamHistoryPath
    $historyStatus = if (Test-Path -LiteralPath $historyPath -PathType Leaf) { 'OK' } else { 'Optional' }
    $results += New-MPVStreamDoctorResult -Name 'History Path' -Status $historyStatus -Detail $historyPath

    Write-Host 'Start-MPVStream Doctor' -ForegroundColor Cyan
    $results | Format-Table -AutoSize | Out-Host
    return $results
}
