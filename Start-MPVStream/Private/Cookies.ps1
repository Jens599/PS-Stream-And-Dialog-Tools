function Resolve-MPVStreamCookiePath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$ConfigData,

        [string]$CookiePath,

        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )

    $configFile = Get-MPVStreamConfigPath
    $legacyConfigFile = Join-Path $env:USERPROFILE '.mpvstream-config.json'
    $finalCookiePath = $null

    if ($ConfigData.cookiePath -and (Test-Path $ConfigData.cookiePath -PathType Leaf)) {
        $finalCookiePath = $ConfigData.cookiePath
    } elseif (-not (Test-Path $configFile -PathType Leaf) -and (Test-Path $legacyConfigFile -PathType Leaf)) {
        try {
            $legacyConfig = Get-Content -LiteralPath $legacyConfigFile -Raw | ConvertFrom-Json
            if ($legacyConfig.cookiePath -and (Test-Path $legacyConfig.cookiePath -PathType Leaf)) {
                $finalCookiePath = $legacyConfig.cookiePath
            }
        } catch {
            Write-Warning "Failed to read config file: $legacyConfigFile"
        }
    }

    if ($CookiePath) {
        $finalCookiePath = $CookiePath
        Write-Host "→ Cookie path provided: $CookiePath" -ForegroundColor Yellow

        try {
            $ConfigData.cookiePath = $finalCookiePath
            Save-MPVStreamConfig -Config $ConfigData
            Write-Host "→ Cookie path saved to: $configFile" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to save config file: $configFile"
        }
    } elseif (-not $finalCookiePath) {
        $defaultCookiePaths = @(
            'cookies.txt',
            "$env:USERPROFILE\cookies.txt",
            "$env:USERPROFILE\Downloads\cookies.txt",
            "$ScriptRoot\cookies.txt"
        )

        foreach ($path in $defaultCookiePaths) {
            if (Test-Path $path -PathType Leaf) {
                $finalCookiePath = $path
                break
            }
        }
    }

    if ($finalCookiePath -and -not [System.IO.Path]::IsPathRooted($finalCookiePath)) {
        try {
            $resolvedPath = Resolve-Path $finalCookiePath -ErrorAction Stop | Select-Object -ExpandProperty Path
            if ($resolvedPath) {
                $finalCookiePath = $resolvedPath
            }
        } catch {
            Write-Warning "Failed to resolve path: $finalCookiePath"
            $finalCookiePath = $null
        }
    }

    if ($finalCookiePath -and (Test-Path $finalCookiePath -PathType Leaf)) {
        Write-Host "→ Using cookies: $finalCookiePath" -ForegroundColor Green
        return $finalCookiePath
    }

    if ($finalCookiePath) {
        Write-Warning "Cookie file not found: $finalCookiePath"
    }

    return $null
}
