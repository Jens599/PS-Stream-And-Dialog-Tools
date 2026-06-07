
function Show-Menu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Options,
        
        [Parameter()]
        [string]$Title = "Use Up/Down arrows and press Enter:",
        
        [Parameter()]
        [switch]$ReturnIndex
    )

    $selectedIndex = 0
    $key = $null
    $cursorVisible = $false
    $width = [Math]::Min([Math]::Max(56, (($Options | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum + 12)), 100)
    $rule = '─' * ($width - 2)
    
    try {
        # Hide the cursor for a cleaner look
        $cursorVisible = [Console]::CursorVisible
        [Console]::CursorVisible = $false
    }
    catch {
        Write-Warning "Could not hide console cursor. Menu will still work but may be less clean."
    }
    
    try {
        while ($key -ne "Enter") {
            Clear-Host
            Write-Host "╭$rule╮" -ForegroundColor DarkCyan

            $header = " $Title "
            if ($header.Length -gt ($width - 4)) {
                $header = $header.Substring(0, $width - 7) + '...'
            }
            Write-Host '│' -NoNewline -ForegroundColor DarkCyan
            Write-Host $header.PadRight($width - 2) -NoNewline -ForegroundColor Cyan
            Write-Host '│' -ForegroundColor DarkCyan

            $countLabel = if ($Title -match 'Results') { 'results' } else { 'items' }
            $countText = " $($Options.Count) $countLabel "
            Write-Host '│' -NoNewline -ForegroundColor DarkCyan
            Write-Host $countText.PadRight($width - 2) -NoNewline -ForegroundColor DarkGray
            Write-Host '│' -ForegroundColor DarkCyan

            Write-Host "├$rule┤" -ForegroundColor DarkCyan
    
            for ($i = 0; $i -lt $Options.Count; $i++) {
                $selected = $i -eq $selectedIndex
                $option = $Options[$i]
                $badge = $null
                $titleText = $option

                if ($option -match '^\[(?<type>[^\]]+)\]\s*(?<title>.*)$') {
                    $badge = $Matches.type.ToUpperInvariant()
                    $titleText = $Matches.title
                }

                $number = '{0:00}' -f ($i + 1)
                $prefix = if ($selected) { ' > ' } else { '   ' }
                $badgeText = if ($badge) { $badge.PadRight(8) } else { ''.PadRight(8) }
                $availableTitleWidth = $width - 18
                if ($titleText.Length -gt $availableTitleWidth) {
                    $titleText = $titleText.Substring(0, [Math]::Max(0, $availableTitleWidth - 3)) + '...'
                }

                Write-Host '│' -NoNewline -ForegroundColor DarkCyan
                Write-Host $prefix -NoNewline -ForegroundColor $(if ($selected) { 'Yellow' } else { 'DarkGray' })
                Write-Host $number -NoNewline -ForegroundColor DarkGray
                Write-Host '  ' -NoNewline

                $badgeColor = switch ($badge) {
                    'CHANNEL' { 'Magenta' }
                    'PLAYLIST' { 'Yellow' }
                    'VIDEO' { 'Green' }
                    default { 'Cyan' }
                }
                Write-Host $badgeText -NoNewline -ForegroundColor $badgeColor
                Write-Host ' ' -NoNewline

                if ($i -eq $selectedIndex) {
                    Write-Host $titleText.PadRight($availableTitleWidth) -NoNewline -ForegroundColor Yellow
                }
                else {
                    Write-Host $titleText.PadRight($availableTitleWidth) -NoNewline -ForegroundColor Gray
                }

                Write-Host '│' -ForegroundColor DarkCyan
            }
            
            Write-Host "├$rule┤" -ForegroundColor DarkCyan
            Write-Host '│' -NoNewline -ForegroundColor DarkCyan
            Write-Host ' ↑/↓ move   Enter select   Esc cancel '.PadRight($width - 2) -NoNewline -ForegroundColor DarkGray
            Write-Host '│' -ForegroundColor DarkCyan
            Write-Host "╰$rule╯" -ForegroundColor DarkCyan
    
            # Wait for user input
            try {
                $key = [Console]::ReadKey($true).Key
            }
            catch {
                Write-Error "Failed to read console input. Make sure you're running in a console that supports interactive input."
                return $null
            }
    
            if ($key -eq "UpArrow") {
                $selectedIndex = if ($selectedIndex -gt 0) { $selectedIndex - 1 } else { $Options.Count - 1 }
            }
            elseif ($key -eq "DownArrow") {
                $selectedIndex = if ($selectedIndex -lt $Options.Count - 1) { $selectedIndex + 1 } else { 0 }
            }
            elseif ($key -eq "Escape") {
                Write-Host "Menu cancelled by user." -ForegroundColor Yellow
                return $null
            }
        }
    }
    finally {
        # Always restore cursor visibility
        try {
            [Console]::CursorVisible = $cursorVisible
        }
        catch {
            # Silently fail if we can't restore cursor visibility
        }
    }
    
    if ($ReturnIndex) {
        return $selectedIndex
    }
    else {
        return $Options[$selectedIndex]
    }
}

Export-ModuleMember -Function Show-Menu
