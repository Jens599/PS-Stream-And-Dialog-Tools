$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleManifests = @(
    Join-Path $repoRoot 'Add-Path\Add-Path.psd1'
    Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1'
    Join-Path $repoRoot 'ytm-dl\ytm-dl.psd1'
)

$moduleSources = @(
    Join-Path $repoRoot 'Add-Path\Add-Path.psm1'
    Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psm1'
    Join-Path $repoRoot 'ytm-dl\ytm-dl.psm1'
) + @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Start-MPVStream\Private') -Filter '*.ps1' | Select-Object -ExpandProperty FullName)

Describe 'PowerShell module manifests' {
    It 'all manifests parse successfully' {
        foreach ($manifest in $moduleManifests) {
            { Test-ModuleManifest -Path $manifest -ErrorAction Stop } | Should Not Throw
        }
    }

    It 'module GUIDs are unique' {
        $guids = foreach ($manifest in $moduleManifests) {
            (Test-ModuleManifest -Path $manifest).Guid.Guid
        }

        ($guids | Sort-Object -Unique).Count | Should Be $guids.Count
    }
}

Describe 'PowerShell module source' {
    It 'all module files parse without syntax errors' {
        foreach ($source in $moduleSources) {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors) > $null
            $errors.Count | Should Be 0
        }
    }
}

Describe 'Public module exports' {
    It 'exports intended commands and aliases' {
        Import-Module (Join-Path $repoRoot 'Add-Path\Add-Path.psd1') -Force
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force
        Import-Module (Join-Path $repoRoot 'ytm-dl\ytm-dl.psd1') -Force

        (Get-Command Add-Path -ErrorAction Stop).CommandType | Should Be 'Function'
        (Get-Command Start-MPVStream -ErrorAction Stop).CommandType | Should Be 'Function'
        (Get-Command Invoke-YtmDownload -ErrorAction Stop).CommandType | Should Be 'Function'
        (Get-Alias play -ErrorAction Stop).ResolvedCommandName | Should Be 'Start-MPVStream'
        (Get-Alias ydl -ErrorAction Stop).ResolvedCommandName | Should Be 'Invoke-YtmDownload'
        (Get-Alias ytm-dl -ErrorAction Stop).ResolvedCommandName | Should Be 'Invoke-YtmDownload'
        Get-Command Show-GitStyleHelp -ErrorAction SilentlyContinue | Should Be $null
    }
}

Describe 'Profile loader' {
    It 'loads all project modules' {
        . (Join-Path $repoRoot 'Profile\PS-Stream-And-Dialog-Tools.profile.ps1')

        (Get-Command Add-Path -ErrorAction Stop).CommandType | Should Be 'Function'
        (Get-Command Start-MPVStream -ErrorAction Stop).CommandType | Should Be 'Function'
        (Get-Command Invoke-YtmDownload -ErrorAction Stop).CommandType | Should Be 'Function'
        (Get-Alias play -ErrorAction Stop).ResolvedCommandName | Should Be 'Start-MPVStream'
        (Get-Alias ydl -ErrorAction Stop).ResolvedCommandName | Should Be 'Invoke-YtmDownload'
        (Get-Alias ytm-dl -ErrorAction Stop).ResolvedCommandName | Should Be 'Invoke-YtmDownload'
    }
}

Describe 'Start-MPVStream behavior' {
    It 'labels mixed search results and launches the selected URL' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Read-MPVStreamConfig {
                Get-MPVStreamDefaultConfig
            }

            function yt-dlp {
                $script:ytdlpArgs = $args
                return @(
                    "Creator`tUC123`tYoutubeTab`thttps://www.youtube.com/channel/UC123"
                    "Only Result`tvideo123`tYoutube`thttps://www.youtube.com/watch?v=video123"
                    "Playlist Result`tPL123`tYoutubeTab`thttps://www.youtube.com/playlist?list=PL123"
                )
            }

            function Select-MPVStreamSearchResult {
                param(
                    [object[]]$Items,
                    [string]$Title,
                    [pscustomobject]$Config
                )

                $script:menuOptions = $Items.MenuTitle
                return $Items[1]
            }

            function mpv {
                $script:mpvArgs = $args
            }

            function Add-MPVStreamHistoryItem { }

            Start-MPVStream 'only result' -Search -Size Small -YtdlFormat audio

            $script:ytdlpArgs[0] | Should Be 'https://www.youtube.com/results?search_query=only%20result'
            $script:ytdlpArgs[2] | Should Be "%(title)s`t%(id)s`t%(ie_key)s`t%(webpage_url)s`t%(duration_string)s`t%(uploader)s`t%(view_count)s"
            $script:menuOptions[0] | Should Be '[Channel] Creator'
            $script:menuOptions[1] | Should Be '[Video] Only Result'
            $script:menuOptions[2] | Should Be '[Playlist] Playlist Result'
            $script:mpvArgs[-1] | Should Be 'https://www.youtube.com/watch?v=video123'

            Remove-Item Function:\yt-dlp -ErrorAction SilentlyContinue
            Remove-Item Function:\Select-MPVStreamSearchResult -ErrorAction SilentlyContinue
            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Item Function:\Add-MPVStreamHistoryItem -ErrorAction SilentlyContinue
            Remove-Variable ytdlpArgs -Scope Script -ErrorAction SilentlyContinue
            Remove-Variable menuOptions -Scope Script -ErrorAction SilentlyContinue
            Remove-Variable mpvArgs -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'does not require mpv for cookie configuration mode' {
        $source = Get-Content -LiteralPath (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psm1') -Raw

        $source | Should Match '\$isConfigOnly = \[string\]::IsNullOrWhiteSpace\(\$Url\) -and \$CookiePath'
        $source | Should Match '\$player = Resolve-MPVStreamPlayer -PlayerPath \$configData\.playerPath'
        $source | Should Match 'if \(\$Search -and -not \(Get-Command yt-dlp'
    }

    It 'exposes modular persistent config settings' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        (Get-Command Start-MPVStream -ErrorAction Stop).Parameters.Keys -contains 'Config' | Should Be $true
        (Get-Command Start-MPVStream -ErrorAction Stop).Parameters.Keys -contains 'MpvArgument' | Should Be $true
        (Get-Command Start-MPVStream -ErrorAction Stop).Parameters.Keys -contains 'DryRun' | Should Be $true
        (Get-Command Start-MPVStream -ErrorAction Stop).Parameters.Keys -contains 'SubtitleLanguage' | Should Be $true
        (Get-Command Start-MPVStream -ErrorAction Stop).Parameters.Keys -contains 'Clipboard' | Should Be $true
        (Get-Command Start-MPVStream -ErrorAction Stop).Parameters.Keys -contains 'History' | Should Be $true
        (Get-Command Start-MPVStream -ErrorAction Stop).Parameters.Keys -contains 'Last' | Should Be $true

        InModuleScope Start-MPVStream {
            $config = Get-MPVStreamDefaultConfig

            $config.menuProvider | Should Be 'fzf'
            $config.playerPath | Should Be $null
            $config.size | Should Be 'PIP'
            $config.ytdlFormat | Should Be '480p'
            $config.maxResults | Should Be 10
            $config.subtitleLanguage | Should Be 'en'
            Normalize-MPVStreamMenuProvider 'fzf' | Should Be 'fzf'
            Normalize-MPVStreamMenuProvider 'Microsoft.PowerShell.ConsoleGuiTools' | Should Be 'ConsoleGuiTools'
            Normalize-MPVStreamMenuProvider 'Out-ConsoleGridView' | Should Be 'OutConsoleGridView'
            Normalize-MPVStreamMenuProvider 'Show-Menu' | Should Be 'BasicPrompt'
            Normalize-MPVStreamMenuProvider 'Basic Prompt' | Should Be 'BasicPrompt'
            Normalize-MPVStreamMenuProvider 'not-real' | Should Be 'fzf'

            $command = Get-Command Start-MPVStream -ErrorAction Stop
            ($command.Parameters['Config'].Aliases -contains 'cfg') | Should Be $true
            ($command.Parameters['First'].Aliases -contains 'fi') | Should Be $true
            ($command.Parameters['Type'].Aliases -contains 't') | Should Be $true
            ($command.Parameters['MpvArgument'].Aliases -contains 'ma') | Should Be $true
            ($command.Parameters['DryRun'].Aliases -contains 'dr') | Should Be $true
            ($command.Parameters['Clipboard'].Aliases -contains 'cb') | Should Be $true
            ($command.Parameters['History'].Aliases -contains 'hi') | Should Be $true
            ($command.Parameters['Last'].Aliases -contains 'la') | Should Be $true
            ($command.Parameters['NoSubtitles'].Aliases -contains 'ns') | Should Be $true
            ($command.Parameters['SubtitleLanguage'].Aliases -contains 'sl') | Should Be $true
        }
    }

    It 'applies direct playback flags and aliases' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Read-MPVStreamConfig { Get-MPVStreamDefaultConfig }
            function Add-MPVStreamHistoryItem { }
            function mpv { $script:mpvArgs = $args }

            Start-MPVStream -u 'https://example.test/direct' -sz Medium -f best -a -l -h -b -r -ns -ma '--force-window=yes'

            ($script:mpvArgs -contains '--terminal=yes') | Should Be $false
            ($script:mpvArgs -contains '--geometry=1280x720-10-10') | Should Be $true
            ($script:mpvArgs -contains '--autofit=1280x720') | Should Be $true
            ($script:mpvArgs -contains '--ytdl-format=bestvideo+bestaudio/best') | Should Be $true
            ($script:mpvArgs -contains '--no-video') | Should Be $true
            ($script:mpvArgs -contains '--loop=inf') | Should Be $true
            ($script:mpvArgs -contains '--hwdec=auto') | Should Be $true
            ($script:mpvArgs -contains '--ytdl-raw-options=playlist-items=1-') | Should Be $true
            ($script:mpvArgs -contains '--ytdl-raw-options=playlist-reverse=') | Should Be $true
            ($script:mpvArgs -contains '--slang=en') | Should Be $false
            ($script:mpvArgs -contains '--force-window=yes') | Should Be $true
            $script:mpvArgs[-1] | Should Be 'https://example.test/direct'

            Remove-Item Function:\Add-MPVStreamHistoryItem -ErrorAction SilentlyContinue
            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Variable mpvArgs -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'applies search flags and aliases' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Read-MPVStreamConfig { Get-MPVStreamDefaultConfig }
            function mpv { }
            function yt-dlp {
                $script:ytdlpArgs = $args
                return @(
                    "Video Result`tvideo123`tYoutube`thttps://www.youtube.com/watch?v=video123",
                    "Playlist Result`tPL123`tYoutubeTab`thttps://www.youtube.com/playlist?list=PL123"
                )
            }
            function Select-MPVStreamSearchResult { throw 'Selector should not be called with -fi.' }

            Start-MPVStream 'query' -s -p -fi -t Playlist -max 7 -dr

            $script:ytdlpArgs[0] | Should Be 'https://www.youtube.com/results?search_query=query&sp=EgIQAw%3D%3D'
            $script:ytdlpArgs[5] | Should Be '1:7'

            Remove-Item Function:\yt-dlp -ErrorAction SilentlyContinue
            Remove-Item Function:\Select-MPVStreamSearchResult -ErrorAction SilentlyContinue
            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Variable ytdlpArgs -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'resolves cookie paths through the cookie helper' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            $testRoot = Join-Path $env:TEMP 'start-mpvstream-cookie-root'
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
            $cookie = Join-Path $testRoot 'cookies.txt'
            Set-Content -LiteralPath $cookie -Value '# cookies' -Encoding UTF8

            $config = Get-MPVStreamDefaultConfig
            $resolved = Resolve-MPVStreamCookiePath -ConfigData $config -ScriptRoot $testRoot

            $resolved | Should Be $cookie
            $config.cookiePath | Should Be $null

            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'parses yt-dlp search rows into normalized menu items' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            $channel = ConvertFrom-MPVStreamSearchRow "Creator`tUC123`tYoutubeTab`thttps://www.youtube.com/channel/UC123"
            $video = ConvertFrom-MPVStreamSearchRow "Only Result`tvideo123`tYoutube`thttps://www.youtube.com/watch?v=video123`t3:45`tExample Channel`t1234"
            $playlist = ConvertFrom-MPVStreamSearchRow "Playlist Result`tPL123`tYoutubeTab`thttps://www.youtube.com/playlist?list=PL123"

            $channel.Type | Should Be 'Channel'
            $channel.MenuTitle | Should Be '[Channel] Creator'
            $channel.Url | Should Be 'https://www.youtube.com/channel/UC123'

            $video.Type | Should Be 'Video'
            $video.Duration | Should Be '3:45'
            $video.Uploader | Should Be 'Example Channel'
            $video.ViewCount | Should Be '1234'
            $video.MenuTitle | Should Be '[Video] Only Result | 3:45 | Example Channel | 1,234 views'

            $playlist.Type | Should Be 'Playlist'
            $playlist.MenuTitle | Should Be '[Playlist] Playlist Result'

            ConvertFrom-MPVStreamSearchRow "missing`tfields" | Should Be $null
            ConvertFrom-MPVStreamSearchRow "`tmissing-title`tYoutube`thttps://example.test" | Should Be $null
        }
    }

    It 'formats search results as readable picker columns' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            $item = [pscustomobject]@{
                Type      = 'Video'
                Duration  = '31:58'
                ViewCount = '345570'
                Uploader  = 'Very Long Channel Name That Should Be Shortened'
                Title     = 'The Greatest Sci-Fi Reinterpretation Ever Made'
            }

            $line = Format-MPVStreamSearchResultLine -Item $item -Index 2

            $line | Should Match '^02\s+Video\s+31:58\s+345,570\s+Very Long Channel\.\.\.\s+The Greatest Sci-Fi Reinterpretation Ever Made$'
        }
    }

    It 'formats config menu options without media columns' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            $items = @(
                [pscustomobject]@{ Index = 0; Title = 'Search UI Provider: fzf'; Type = 'Option'; Url = $null; MenuTitle = 'Search UI Provider: fzf' },
                [pscustomobject]@{ Index = 1; Title = 'Cookie Path: <not set>'; Type = 'Option'; Url = $null; MenuTitle = 'Cookie Path: <not set>' }
            )

            Test-MPVStreamOptionMenu -Items $items | Should Be $true
            Format-MPVStreamOptionLine -Item $items[0] -Index 1 | Should Be '01  Search UI Provider: fzf'
            Format-MPVStreamOptionLine -Item $items[1] -Index 2 | Should Be '02  Cookie Path: <not set>'
        }
    }

    It 'builds yt-dlp search arguments with metadata fields and cookies' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            $args = New-MPVStreamYtdlpSearchArgument -EncodedQuery 'lofi%20beats' -Playlist -MaxResults 7 -CookiePath 'C:\Temp\cookies.txt'

            $args[0] | Should Be 'https://www.youtube.com/results?search_query=lofi%20beats&sp=EgIQAw%3D%3D'
            $args[1] | Should Be '--print'
            $args[2] | Should Be "%(title)s`t%(id)s`t%(ie_key)s`t%(webpage_url)s`t%(duration_string)s`t%(uploader)s`t%(view_count)s"
            $args[3] | Should Be '--flat-playlist'
            $args[4] | Should Be '--playlist-items'
            $args[5] | Should Be '1:7'
            $args[6] | Should Be '--cookies'
            $args[7] | Should Be 'C:\Temp\cookies.txt'
        }
    }

    It 'plays the first search result without opening the selector' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Read-MPVStreamConfig {
                Get-MPVStreamDefaultConfig
            }

            function yt-dlp {
                return @(
                    "First Result`tfirst123`tYoutube`thttps://www.youtube.com/watch?v=first123`t1:00`tChannel One`t100",
                    "Second Result`tsecond123`tYoutube`thttps://www.youtube.com/watch?v=second123`t2:00`tChannel Two`t200"
                )
            }

            function Select-MPVStreamSearchResult {
                throw 'Selector should not be called when -First is used.'
            }

            function mpv {
                $script:mpvArgs = $args
            }

            function Add-MPVStreamHistoryItem { }

            Start-MPVStream 'first result' -Search -First -Size Small -YtdlFormat audio

            $script:mpvArgs[-1] | Should Be 'https://www.youtube.com/watch?v=first123'

            Remove-Item Function:\yt-dlp -ErrorAction SilentlyContinue
            Remove-Item Function:\Select-MPVStreamSearchResult -ErrorAction SilentlyContinue
            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Item Function:\Add-MPVStreamHistoryItem -ErrorAction SilentlyContinue
            Remove-Variable mpvArgs -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'can load more interactive search results before selection' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Read-MPVStreamConfig {
                Get-MPVStreamDefaultConfig
            }

            function yt-dlp {
                $script:ytdlpRanges += $args[5]
                if ($args[5] -eq '1:2') {
                    return @(
                        "First Result`tfirst123`tYoutube`thttps://www.youtube.com/watch?v=first123`t1:00`tChannel One`t100",
                        "Second Result`tsecond123`tYoutube`thttps://www.youtube.com/watch?v=second123`t2:00`tChannel Two`t200"
                    )
                }

                return @(
                    "First Result`tfirst123`tYoutube`thttps://www.youtube.com/watch?v=first123`t1:00`tChannel One`t100",
                    "Second Result`tsecond123`tYoutube`thttps://www.youtube.com/watch?v=second123`t2:00`tChannel Two`t200",
                    "Third Result`tthird123`tYoutube`thttps://www.youtube.com/watch?v=third123`t3:00`tChannel Three`t300",
                    "Fourth Result`tfourth123`tYoutube`thttps://www.youtube.com/watch?v=fourth123`t4:00`tChannel Four`t400"
                )
            }

            function Select-MPVStreamSearchResult {
                param(
                    [object[]]$Items,
                    [string]$Title,
                    [pscustomobject]$Config
                )

                $script:menuCounts += $Items.Count
                if ($script:menuCounts.Count -eq 1) {
                    return $Items[-1]
                }

                return $Items[3]
            }

            function mpv {
                $script:mpvArgs = $args
            }

            function Add-MPVStreamHistoryItem { }

            $script:ytdlpRanges = @()
            $script:menuCounts = @()

            Start-MPVStream 'more results' -Search -MaxResults 2 -Size Small -YtdlFormat audio

            $script:ytdlpRanges[0] | Should Be '1:2'
            $script:ytdlpRanges[1] | Should Be '1:4'
            $script:menuCounts[0] | Should Be 3
            $script:menuCounts[1] | Should Be 5
            $script:mpvArgs[-1] | Should Be 'https://www.youtube.com/watch?v=fourth123'

            Remove-Item Function:\yt-dlp -ErrorAction SilentlyContinue
            Remove-Item Function:\Select-MPVStreamSearchResult -ErrorAction SilentlyContinue
            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Item Function:\Add-MPVStreamHistoryItem -ErrorAction SilentlyContinue
            Remove-Variable ytdlpRanges -Scope Script -ErrorAction SilentlyContinue
            Remove-Variable menuCounts -Scope Script -ErrorAction SilentlyContinue
            Remove-Variable mpvArgs -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'stops offering more search results when expansion does not add results' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Search-MPVStreamYouTube {
                param([int]$MaxResults)
                $script:requestedMaxResults += $MaxResults
                return @(
                    [pscustomobject]@{ Title = 'First'; Type = 'Video'; Url = 'https://example.test/first'; MenuTitle = '[Video] First' },
                    [pscustomobject]@{ Title = 'Second'; Type = 'Video'; Url = 'https://example.test/second'; MenuTitle = '[Video] Second' }
                )
            }

            function Select-MPVStreamSearchResult {
                param([object[]]$Items)
                $script:menuCounts += $Items.Count
                if ($script:menuCounts.Count -eq 1) { return $Items[-1] }
                return $Items[0]
            }

            $script:requestedMaxResults = @()
            $script:menuCounts = @()

            $selected = Select-MPVStreamYouTubeSearchResult -EncodedQuery 'query' -MaxResults 2 -Type Video -Config (Get-MPVStreamDefaultConfig) -Title 'Search Results: query' -EmptyMessage 'No results found.'

            $script:requestedMaxResults[0] | Should Be 2
            $script:requestedMaxResults[1] | Should Be 4
            $script:menuCounts[0] | Should Be 3
            $script:menuCounts[1] | Should Be 2
            $selected.Url | Should Be 'https://example.test/first'

            Remove-Item Function:\Search-MPVStreamYouTube -ErrorAction SilentlyContinue
            Remove-Item Function:\Select-MPVStreamSearchResult -ErrorAction SilentlyContinue
            Remove-Variable requestedMaxResults -Scope Script -ErrorAction SilentlyContinue
            Remove-Variable menuCounts -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'caps load more search requests at fifty results' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Search-MPVStreamYouTube {
                param([int]$MaxResults)
                for ($i = 1; $i -le $MaxResults; $i++) {
                    [pscustomobject]@{ Title = "Result $i"; Type = 'Video'; Url = "https://example.test/$i"; MenuTitle = "[Video] Result $i" }
                }
            }

            function Select-MPVStreamSearchResult {
                param([object[]]$Items)
                $script:loadMoreTitle = $Items[-1].Title
                return $null
            }

            Select-MPVStreamYouTubeSearchResult -EncodedQuery 'query' -MaxResults 40 -Config (Get-MPVStreamDefaultConfig) -Title 'Search Results: query' -EmptyMessage 'No results found.' | Out-Null

            $script:loadMoreTitle | Should Be 'Load more results (40 -> 50)'

            Remove-Item Function:\Search-MPVStreamYouTube -ErrorAction SilentlyContinue
            Remove-Item Function:\Select-MPVStreamSearchResult -ErrorAction SilentlyContinue
            Remove-Variable loadMoreTitle -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'filters search results by type' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function yt-dlp {
                return @(
                    "Creator`tUC123`tYoutubeTab`thttps://www.youtube.com/channel/UC123",
                    "Only Result`tvideo123`tYoutube`thttps://www.youtube.com/watch?v=video123",
                    "Playlist Result`tPL123`tYoutubeTab`thttps://www.youtube.com/playlist?list=PL123"
                )
            }

            $videos = @(Search-MPVStreamYouTube -EncodedQuery 'query' -MaxResults 10 -Type Video)
            $playlists = @(Search-MPVStreamYouTube -EncodedQuery 'query' -MaxResults 10 -Type Playlist)
            $channels = @(Search-MPVStreamYouTube -EncodedQuery 'query' -MaxResults 10 -Type Channel)

            $videos.Count | Should Be 1
            $videos[0].Type | Should Be 'Video'
            $playlists.Count | Should Be 1
            $playlists[0].Type | Should Be 'Playlist'
            $channels.Count | Should Be 1
            $channels[0].Type | Should Be 'Channel'

            Remove-Item Function:\yt-dlp -ErrorAction SilentlyContinue
        }
    }

    It 'builds mpv arguments from playback options' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            $mpvArgs = @(New-MPVStreamMpvArgument -Size PIP -YtdlFormat '720p' -CookiePath 'C:\Temp\cookies.txt' -AudioOnly -Loop -HardwareAccel -ReversePlaylist -CustomArgument @('--speed=1.25', '--volume=70'))

            ($mpvArgs -contains '--terminal=yes') | Should Be $true
            ($mpvArgs -contains '--geometry=320x180-10-10') | Should Be $true
            ($mpvArgs -contains '--autofit=320x180') | Should Be $true
            ($mpvArgs -contains '--no-border') | Should Be $true
            ($mpvArgs -contains '--ontop') | Should Be $true
            ($mpvArgs -contains '--no-video') | Should Be $true
            ($mpvArgs -contains '--loop=inf') | Should Be $true
            ($mpvArgs -contains '--hwdec=auto') | Should Be $true
            ($mpvArgs -contains '--ytdl-raw-options=playlist-items=1-') | Should Be $true
            ($mpvArgs -contains '--ytdl-raw-options=playlist-reverse=') | Should Be $true
            ($mpvArgs -contains '--ytdl-format=bestvideo[height<=720]+bestaudio/best') | Should Be $true
            ($mpvArgs -contains '--ytdl-raw-options=cookies=C:\Temp\cookies.txt') | Should Be $true
            ($mpvArgs -contains '--ytdl-raw-options=no-download-archive=') | Should Be $true
            ($mpvArgs -contains '--slang=en') | Should Be $true
            ($mpvArgs -contains '--speed=1.25') | Should Be $true
            ($mpvArgs -contains '--volume=70') | Should Be $true

            $backgroundArgs = @(New-MPVStreamMpvArgument -Size Small -YtdlFormat audio -Background -NoSubtitles)
            ($backgroundArgs -contains '--terminal=yes') | Should Be $false
            ($backgroundArgs -contains '--slang=en') | Should Be $false
            ($backgroundArgs -contains '--geometry=854x480-10-10') | Should Be $true
            ($backgroundArgs -contains '--autofit=854x480') | Should Be $true
            ($backgroundArgs -contains '--ytdl-format=bestaudio/best') | Should Be $true

            $mediumArgs = @(New-MPVStreamMpvArgument -Size Medium -YtdlFormat '480p')
            ($mediumArgs -contains '--geometry=1280x720-10-10') | Should Be $true
            ($mediumArgs -contains '--autofit=1280x720') | Should Be $true

            $subtitleArgs = @(New-MPVStreamMpvArgument -Size Small -YtdlFormat audio -SubtitleLanguage @('en', 'ja'))
            ($subtitleArgs -contains '--slang=en,ja') | Should Be $true
        }
    }

    It 'resolves configured player paths and fallback commands' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Get-Command {
                param(
                    [string]$Name,
                    [System.Management.Automation.ActionPreference]$ErrorAction
                )

                if ($Name -eq 'mpvnet.com') {
                    return [pscustomobject]@{
                        Name        = 'mpvnet.com'
                        Source      = 'mpvnet.com'
                        CommandType = 'Function'
                    }
                }

                return $null
            }

            $fallback = Resolve-MPVStreamPlayer
            $configured = Resolve-MPVStreamPlayer -PlayerPath 'mpvnet.com'

            $fallback.Name | Should Be 'mpvnet.com'
            $configured.Name | Should Be 'mpvnet.com'

            Remove-Item Function:\Get-Command -ErrorAction SilentlyContinue
        }
    }

    It 'plays a clipboard URL without requiring a positional URL' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Read-MPVStreamConfig { Get-MPVStreamDefaultConfig }
            function Get-MPVStreamClipboardText { 'https://example.test/clipboard' }
            function mpv { $script:mpvArgs = $args }
            function Add-MPVStreamHistoryItem { }

            Start-MPVStream -Clipboard

            $script:mpvArgs[-1] | Should Be 'https://example.test/clipboard'

            Remove-Item Function:\Get-MPVStreamClipboardText -ErrorAction SilentlyContinue
            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Item Function:\Add-MPVStreamHistoryItem -ErrorAction SilentlyContinue
            Remove-Variable mpvArgs -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'stores and replays playback history' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            $script:historyPath = Join-Path $env:TEMP 'start-mpvstream-history-test.json'
            function Get-MPVStreamHistoryPath { $script:historyPath }
            function Read-MPVStreamConfig { Get-MPVStreamDefaultConfig }
            function mpv { $script:mpvArgs = $args }

            Add-MPVStreamHistoryItem -Url 'https://example.test/one' -Title 'One' -Type 'Direct'
            Add-MPVStreamHistoryItem -Url 'https://example.test/two' -Title 'Two' -Type 'Direct'

            (Get-MPVStreamLastHistoryItem).Url | Should Be 'https://example.test/two'

            Start-MPVStream -Last
            $script:mpvArgs[-1] | Should Be 'https://example.test/two'

            Remove-Item Function:\Get-MPVStreamHistoryPath -ErrorAction SilentlyContinue
            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $script:historyPath -ErrorAction SilentlyContinue
            Remove-Variable mpvArgs -Scope Script -ErrorAction SilentlyContinue
            Remove-Variable historyPath -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'does not start mpv during dry run' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function Read-MPVStreamConfig {
                Get-MPVStreamDefaultConfig
            }

            function mpv {
                throw 'mpv should not be started during dry run.'
            }

            function Add-MPVStreamHistoryItem { throw 'History should not be written during dry run.' }

            Start-MPVStream 'https://example.test/video' -DryRun -MpvArgument '--speed=1.25'

            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Item Function:\Add-MPVStreamHistoryItem -ErrorAction SilentlyContinue
        }
    }

    It 'does not fallback to the first result when selection is cancelled' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            $script:providerChecks = @()

            function Test-MPVStreamMenuProvider {
                param([string]$Provider)
                $script:providerChecks += (Normalize-MPVStreamMenuProvider $Provider)
                (Normalize-MPVStreamMenuProvider $Provider) -eq 'BasicPrompt'
            }

            function Select-MPVStreamSearchResultWithBasicPrompt {
                param([object[]]$Items, [string]$Title)
                return $null
            }

            $config = Get-MPVStreamDefaultConfig
            $config.menuProvider = 'BasicPrompt'
            $items = @(
                [pscustomobject]@{ Title = 'First'; Type = 'Video'; Url = 'https://example.test/first'; MenuTitle = '[Video] First' }
            )

            Select-MPVStreamSearchResult -Items $items -Title 'Search Results: test' -Config $config | Should Be $null
            $script:providerChecks.Count | Should Be 1

            Remove-Item Function:\Test-MPVStreamMenuProvider -ErrorAction SilentlyContinue
            Remove-Item Function:\Select-MPVStreamSearchResultWithBasicPrompt -ErrorAction SilentlyContinue
            Remove-Variable providerChecks -Scope Script -ErrorAction SilentlyContinue
        }
    }
}
