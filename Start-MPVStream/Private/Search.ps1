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

function Normalize-MPVStreamType {
    param([string]$Type)

    if ([string]::IsNullOrWhiteSpace($Type)) { return $null }

    switch -Regex ($Type.Trim()) {
        '^(v|video|videos)$' { return 'Video' }
        '^(p|pl|playlist|playlists)$' { return 'Playlist' }
        '^(c|ch|channel|channels)$' { return 'Channel' }
        default { return $null }
    }
}

function New-MPVStreamYtdlpSearchArgument {
    param(
        [string]$EncodedQuery,

        [switch]$Home,

        [switch]$Playlist,

        [Parameter(Mandatory = $true)]
        [int]$MaxResults,

        [string]$CookiePath
    )

    $searchUrl = if ($Home) { 'https://www.youtube.com/' } else { "https://www.youtube.com/results?search_query=$EncodedQuery" }
    if (-not $Home -and $Playlist) {
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
        [string]$EncodedQuery,

        [switch]$Home,

        [switch]$Playlist,

        [Parameter(Mandatory = $true)]
        [int]$MaxResults,

        [string]$CookiePath,

        [string]$Type
    )

    $Type = Normalize-MPVStreamType $Type

    $ytdlArgs = New-MPVStreamYtdlpSearchArgument -EncodedQuery $EncodedQuery -Home:$Home -Playlist:$Playlist -MaxResults $MaxResults -CookiePath $CookiePath
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

function Select-MPVStreamYouTubeSearchResult {
    param(
        [string]$EncodedQuery,

        [switch]$Home,

        [switch]$Playlist,

        [Parameter(Mandatory = $true)]
        [int]$MaxResults,

        [string]$CookiePath,

        [string]$Type,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Config,

        [switch]$First,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$EmptyMessage
    )

    $currentMaxResults = $MaxResults
    $maxSearchResults = 50
    $previousResultCount = $null

    while ($true) {
        $searchParameters = @{
            EncodedQuery = $EncodedQuery
            Home         = $Home
            Playlist     = $Playlist
            MaxResults   = $currentMaxResults
            CookiePath   = $CookiePath
        }
        if ($Type) { $searchParameters.Type = $Type }

        $searchResults = @(Search-MPVStreamYouTube @searchParameters)
        if ($searchResults.Count -eq 0) {
            Write-Host $EmptyMessage -ForegroundColor Red
            $global:LASTEXITCODE = 0
            return $null
        }

        Write-Host "Search results found: $($searchResults.Count)" -ForegroundColor Yellow

        if ($First) {
            return $searchResults[0]
        }

        $selectableResults = @($searchResults)
        $hasMoreResults = $currentMaxResults -lt $maxSearchResults
        if ($null -ne $previousResultCount -and $searchResults.Count -le $previousResultCount) { $hasMoreResults = $false }
        if (-not $Type -and $searchResults.Count -lt $currentMaxResults) { $hasMoreResults = $false }

        if ($hasMoreResults) {
            $nextMaxResults = [Math]::Min($currentMaxResults + $MaxResults, $maxSearchResults)
            $selectableResults += [pscustomobject]@{
                Title      = "Load more results ($currentMaxResults -> $nextMaxResults)"
                ID         = $null
                Type       = 'Option'
                Url        = $null
                Duration   = $null
                Uploader   = $null
                ViewCount  = $null
                MenuTitle  = "Load more results ($currentMaxResults -> $nextMaxResults)"
                IsLoadMore = $true
            }
        }

        $selectedResult = Select-MPVStreamSearchResult -Items $selectableResults -Title $Title -Config $Config
        if ($null -eq $selectedResult) {
            $global:LASTEXITCODE = 0
            return $null
        }

        if ($selectedResult.IsLoadMore) {
            $previousResultCount = $searchResults.Count
            $currentMaxResults = [Math]::Min($currentMaxResults + $MaxResults, $maxSearchResults)
            continue
        }

        return $selectedResult
    }
}

function Get-MPVStreamYouTubeChannelTabUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Videos', 'Shorts', 'Streams', 'Playlists', 'Community', 'Channels', 'Featured')]
        [string]$ChannelTab
    )

    $tabPath = switch ($ChannelTab) {
        'Videos' { 'videos' }
        'Shorts' { 'shorts' }
        'Streams' { 'streams' }
        'Playlists' { 'playlists' }
        'Community' { 'community' }
        'Channels' { 'channels' }
        'Featured' { 'featured' }
    }

    $baseUrl = $Url -replace '[?#].*$', ''
    $baseUrl = $baseUrl.TrimEnd('/')
    $baseUrl = $baseUrl -replace '/(videos|shorts|streams|playlists|community|channels|featured)$', ''

    return "$baseUrl/$tabPath"
}

function Test-MPVStreamYouTubeTabHasItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [string]$CookiePath
    )

    $arguments = @(
        $Url,
        '--flat-playlist',
        '--playlist-items',
        '1',
        '--print',
        '%(id)s'
    )

    if ($CookiePath) {
        $arguments += '--cookies', $CookiePath
    }

    $output = @(yt-dlp @arguments 2>$null)
    return ($LASTEXITCODE -eq 0 -and @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne 'NA' }).Count -gt 0)
}

function Convert-MPVStreamYouTubeVideosTabToUploadsPlaylistUrl {
    param([string]$Url)

    if ($Url -match 'youtube\.com/channel/(UC[^/?#]+)') {
        $uploadsPlaylistId = 'UU' + $Matches[1].Substring(2)
        return "https://www.youtube.com/playlist?list=$uploadsPlaylistId"
    }

    return $Url
}

function Resolve-MPVStreamYouTubeChannelTabSelection {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Selection,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Videos', 'Shorts', 'Streams', 'Playlists', 'Community', 'Channels', 'Featured')]
        [string]$ChannelTab,

        [string]$CookiePath
    )

    if ($Selection.Type -ne 'Channel' -or [string]::IsNullOrWhiteSpace($Selection.Url)) {
        return $Selection
    }

    $tabs = @('Videos', 'Shorts', 'Streams', 'Playlists', 'Community', 'Channels', 'Featured')
    $startIndex = [Array]::IndexOf($tabs, $ChannelTab)
    if ($startIndex -lt 0) { $startIndex = 0 }

    foreach ($tab in @($tabs[$startIndex..($tabs.Count - 1)])) {
        $tabUrl = Get-MPVStreamYouTubeChannelTabUrl -Url $Selection.Url -ChannelTab $tab
        if (Test-MPVStreamYouTubeTabHasItem -Url $tabUrl -CookiePath $CookiePath) {
            $Selection.Url = if ($tab -eq 'Videos') { Convert-MPVStreamYouTubeVideosTabToUploadsPlaylistUrl $tabUrl } else { $tabUrl }
            $Selection.Type = "Channel/$tab"
            if ($tab -ne $ChannelTab) {
                Write-Warning "Channel $ChannelTab tab has no playable items. Using $tab tab instead."
            }
            return $Selection
        }
    }

    Write-Warning "No playable channel tabs found. Using selected channel URL instead."
    return $Selection
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

    [pscustomobject][ordered]@{
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
