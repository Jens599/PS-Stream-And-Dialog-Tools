. (Join-Path $PSScriptRoot 'Shared.Tests.ps1')

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

