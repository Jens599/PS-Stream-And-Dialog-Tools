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
)

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

            Start-MPVStream 'first result' -Search -First -Size Small -YtdlFormat audio

            $script:mpvArgs[-1] | Should Be 'https://www.youtube.com/watch?v=first123'

            Remove-Item Function:\yt-dlp -ErrorAction SilentlyContinue
            Remove-Item Function:\Select-MPVStreamSearchResult -ErrorAction SilentlyContinue
            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
            Remove-Variable mpvArgs -Scope Script -ErrorAction SilentlyContinue
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
            ($backgroundArgs -contains '--autofit=854x480') | Should Be $true
            ($backgroundArgs -contains '--ytdl-format=bestaudio/best') | Should Be $true

            $subtitleArgs = @(New-MPVStreamMpvArgument -Size Small -YtdlFormat audio -SubtitleLanguage @('en', 'ja'))
            ($subtitleArgs -contains '--slang=en,ja') | Should Be $true
        }
    }

    It 'resolves configured player paths and fallback commands' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        InModuleScope Start-MPVStream {
            function mpvnet.com { }

            $fallback = Resolve-MPVStreamPlayer
            $configured = Resolve-MPVStreamPlayer -PlayerPath 'mpvnet.com'

            $fallback.Name | Should Be 'mpvnet.com'
            $configured.Name | Should Be 'mpvnet.com'

            Remove-Item Function:\mpvnet.com -ErrorAction SilentlyContinue
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

            Start-MPVStream 'https://example.test/video' -DryRun -MpvArgument '--speed=1.25'

            Remove-Item Function:\mpv -ErrorAction SilentlyContinue
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
