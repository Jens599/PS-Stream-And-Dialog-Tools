
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

    # Show help if no parameters provided
    if (-not $Options -or $Options.Count -eq 0) {
        Write-Host "`n=== Show-Menu Help ===" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "USAGE:" -ForegroundColor Yellow
        Write-Host "    Show-Menu -Options <string[]> [-Title <string>] [-ReturnIndex]"
        Write-Host ""
        Write-Host "PARAMETERS:" -ForegroundColor Yellow
        Write-Host "    -Options    Array of menu options to display"
        Write-Host "    -Title      Menu title (default: 'Use Up/Down arrows and press Enter:')"
        Write-Host "    -ReturnIndex If specified, returns the index (0-based) instead of the option value"
        Write-Host ""
        Write-Host "EXAMPLES:" -ForegroundColor Yellow
        Write-Host "    # Basic usage"
        Write-Host "    `$choices = 'Restart Service', 'Stop Service', 'Check Status', 'Exit'"
        Write-Host "    `$result = Show-Menu -Options `$choices"
        Write-Host ""
        Write-Host "    # With custom title"
        Write-Host "    `$choices = 'Option 1', 'Option 2', 'Option 3'"
        Write-Host "    `$result = Show-Menu -Options `$choices -Title 'Server Management'"
        Write-Host ""
        Write-Host "    # Direct usage"
        Write-Host "    `$result = Show-Menu -Options 'Yes', 'No', 'Cancel' -Title 'Confirm Action'"
        Write-Host ""
        Write-Host "    # Return index instead of value"
        Write-Host "    `$choices = 'Option 1', 'Option 2', 'Option 3'"
        Write-Host "    `$index = Show-Menu -Options `$choices -ReturnIndex"
        Write-Host "    `$selectedOption = `$choices[`$index]"
        Write-Host ""
        Write-Host "DESCRIPTION:" -ForegroundColor Yellow
        Write-Host "    Displays an interactive menu where users can navigate using arrow keys"
        Write-Host "    and select an option by pressing Enter. Returns the selected option as a string"
        Write-Host "    or the index (0-based) if -ReturnIndex is specified."
        Write-Host ""
        return
    }

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
