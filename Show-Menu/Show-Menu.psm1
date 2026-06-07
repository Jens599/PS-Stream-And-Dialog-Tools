
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
            Write-Host "=== $Title ===" -ForegroundColor Cyan
            Write-Host ""  # Add spacing
    
            for ($i = 0; $i -lt $Options.Count; $i++) {
                if ($i -eq $selectedIndex) {
                    # Highlight the selected option
                    Write-Host "> $($Options[$i])" -ForegroundColor Yellow -BackgroundColor Black
                }
                else {
                    Write-Host "  $($Options[$i])"
                }
            }
            
            Write-Host ""  # Add spacing
            Write-Host "[↑↓ Navigate] [Enter Select] [Escape Cancel]" -ForegroundColor Gray
    
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
