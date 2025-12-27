function Add-Path {
    <#
    .SYNOPSIS
        Permanently adds a path to the PATH environment variable.
    
    .DESCRIPTION
        The Add-Path function adds a specified path to the user's PATH environment variable permanently.
        The modification persists across PowerShell sessions and system reboots.
    
    .PARAMETER Path
        The path to add to the PATH environment variable. Can be absolute or relative.
    
    .PARAMETER Scope
        Determines whether to modify the User or Machine PATH. Defaults to User.
        Valid values: User, Machine
    
    .EXAMPLE
        Add-Path -Path "C:\Tools\MyTool"
        
        Adds C:\Tools\MyTool to the current user's PATH.
    
    .EXAMPLE
        Add-Path -Path "..\Tools\MyTool"
        
        Adds the relative path ..\Tools\MyTool (resolved to absolute) to the current user's PATH.
    
    .EXAMPLE
        Add-Path -Path "C:\Program Files\MyApp" -Scope Machine
        
        Adds C:\Program Files\MyApp to the system PATH (requires admin privileges).
    
    .NOTES
        - Requires administrator privileges for Machine scope
        - Duplicate paths are automatically prevented
        - Changes take effect in new PowerShell sessions
        - Relative paths are converted to absolute paths before being added
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({
            # Convert relative path to absolute for validation
            $testPath = if ([System.IO.Path]::IsPathRooted($_)) {
                $_
            } else {
                [System.IO.Path]::GetFullPath($_)
            }
            
            if (-not (Test-Path -Path $testPath -PathType Container)) {
                throw "Path '$_' does not exist or is not a directory."
            }
            return $true
        })]
        [string]$Path,
        
        [Parameter()]
        [ValidateSet('User', 'Machine')]
        [string]$Scope = 'User'
    )
    
    # Convert relative path to absolute and normalize
    $normalizedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        Write-Verbose "Converting relative path '$Path' to absolute path..."
        [System.IO.Path]::GetFullPath($Path)
    }
    
    # Get current PATH
    $registryKey = if ($Scope -eq 'User') {
        'HKCU:\Environment'
    } else {
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    }
    
    if (-not (Test-Path $registryKey)) {
        throw "Registry key '$registryKey' not found. This should not happen on a normal Windows system."
    }
    
    $currentPath = (Get-ItemProperty -Path $registryKey -Name PATH -ErrorAction SilentlyContinue).PATH
    
    if (-not $currentPath) {
        $currentPath = ''
    }
    
    # Check if path already exists
    $pathEntries = $currentPath -split ';' | Where-Object { $_ -ne '' }
    if ($normalizedPath -in $pathEntries) {
        Write-Warning "Path '$normalizedPath' is already in the PATH environment variable."
        return
    }
    
    # Add the new path
    $newPath = if ($currentPath) {
        "$currentPath;$normalizedPath"
    } else {
        $normalizedPath
    }
    
    # Update registry
    if ($PSCmdlet.ShouldProcess("PATH environment variable ($Scope scope)", "Add '$normalizedPath'")) {
        try {
            Set-ItemProperty -Path $registryKey -Name PATH -Value $newPath -Type ExpandString -Force
            
            # Notify Windows of environment variable change
            if ($Scope -eq 'Machine') {
                # Broadcast system-wide environment change
                [System.Environment]::SetEnvironmentVariable('PATH', $newPath, [System.EnvironmentVariableTarget]::Machine)
            } else {
                # Update current session and broadcast user environment change
                [System.Environment]::SetEnvironmentVariable('PATH', $newPath, [System.EnvironmentVariableTarget]::User)
                $env:PATH = $newPath
            }
            
            Write-Host "Successfully added '$normalizedPath' to PATH ($Scope scope)." -ForegroundColor Green
            Write-Host "Changes will take effect in new PowerShell sessions." -ForegroundColor Yellow
            
        } catch {
            throw "Failed to update PATH environment variable: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Add-Path
