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

function New-MPVStreamYtdlpSearchArgument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncodedQuery,

        [switch]$Playlist,

        [Parameter(Mandatory = $true)]
        [int]$MaxResults,

        [string]$CookiePath
    )

    $searchUrl = "https://www.youtube.com/results?search_query=$EncodedQuery"
    if ($Playlist) {
        $searchUrl = "$searchUrl&sp=EgIQAw%3D%3D"
    }

    $arguments = @(
        $searchUrl,
        '--print',
        "%(title)s`t%(id)s`t%(ie_key)s`t%(webpage_url)s`t%(duration_string)s`t%(uploader)s`t%(view_count)s",
        '--flat-playlist',
        '--playlist-items',
        "1:$MaxResults"
    )

    if ($CookiePath) {
        $arguments += '--cookies', $CookiePath
    }

    return $arguments
}

function Search-MPVStreamYouTube {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncodedQuery,

        [switch]$Playlist,

        [Parameter(Mandatory = $true)]
        [int]$MaxResults,

        [string]$CookiePath,

        [ValidateSet('Video', 'Playlist', 'Channel')]
        [string]$Type
    )

    $ytdlArgs = New-MPVStreamYtdlpSearchArgument -EncodedQuery $EncodedQuery -Playlist:$Playlist -MaxResults $MaxResults -CookiePath $CookiePath
    $searchRows = @(yt-dlp @ytdlArgs)
    if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) { throw "yt-dlp exited with code $LASTEXITCODE" }

    $results = foreach ($row in $searchRows) {
        $result = ConvertFrom-MPVStreamSearchRow -Row $row
        if ($null -eq $result) { continue }
        if ($Type -and $result.Type -ne $Type) { continue }
        $result
    }

    return @($results)
}

function ConvertFrom-MPVStreamSearchRow {
    param([string]$Row)

    $parts = $Row -split "`t", 7
    if ($parts.Count -lt 4 -or -not $parts[0] -or -not $parts[1]) {
        return $null
    }

    $resultType = Get-MPVStreamSearchType -Id $parts[1] -IeKey $parts[2] -WebpageUrl $parts[3]
    $duration = if ($parts.Count -ge 5) { $parts[4] } else { $null }
    $uploader = if ($parts.Count -ge 6) { $parts[5] } else { $null }
    $viewCount = if ($parts.Count -ge 7) { $parts[6] } else { $null }
    $metadata = @($duration, $uploader)

    if ($viewCount -and $viewCount -ne 'NA') {
        $viewNumber = 0L
        if ([long]::TryParse($viewCount, [ref]$viewNumber)) {
            $metadata += ('{0:N0} views' -f $viewNumber)
        } else {
            $metadata += "$viewCount views"
        }
    }

    $metadata = @($metadata | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne 'NA' })
    $menuTitle = "[$resultType] $($parts[0])"
    if ($metadata.Count -gt 0) {
        $menuTitle = "$menuTitle | $($metadata -join ' | ')"
    }

    [ordered]@{
        Title     = $parts[0]
        ID        = $parts[1]
        Type      = $resultType
        Url       = $parts[3]
        Duration  = $duration
        Uploader  = $uploader
        ViewCount = $viewCount
        MenuTitle = $menuTitle
    }
}
