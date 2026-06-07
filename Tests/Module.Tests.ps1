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
            $script:ytdlpArgs[2] | Should Be "%(title)s`t%(id)s`t%(ie_key)s`t%(webpage_url)s"
            $script:menuOptions[0] | Should Be '[Channel] Creator'
            $script:menuOptions[1] | Should Be '[Video] Only Result'
            $script:menuOptions[2] | Should Be '[Playlist] Playlist Result'
            $script:mpvArgs[0] | Should Be 'https://www.youtube.com/watch?v=video123'

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
        $source | Should Match 'if \(-not \$isConfigOnly -and -not \(Get-Command mpv'
        $source | Should Match 'if \(\$Search -and -not \(Get-Command yt-dlp'
    }

    It 'exposes modular persistent config settings' {
        Import-Module (Join-Path $repoRoot 'Start-MPVStream\Start-MPVStream.psd1') -Force

        (Get-Command Start-MPVStream -ErrorAction Stop).Parameters.Keys -contains 'Config' | Should Be $true

        InModuleScope Start-MPVStream {
            $config = Get-MPVStreamDefaultConfig

            $config.menuProvider | Should Be 'fzf'
            $config.size | Should Be 'PIP'
            $config.ytdlFormat | Should Be '480p'
            $config.maxResults | Should Be 10
            Normalize-MPVStreamMenuProvider 'fzf' | Should Be 'fzf'
            Normalize-MPVStreamMenuProvider 'Microsoft.PowerShell.ConsoleGuiTools' | Should Be 'ConsoleGuiTools'
            Normalize-MPVStreamMenuProvider 'Out-ConsoleGridView' | Should Be 'OutConsoleGridView'
            Normalize-MPVStreamMenuProvider 'Show-Menu' | Should Be 'BasicPrompt'
            Normalize-MPVStreamMenuProvider 'Basic Prompt' | Should Be 'BasicPrompt'
            Normalize-MPVStreamMenuProvider 'not-real' | Should Be 'fzf'
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
