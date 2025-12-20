@{
    RootModule        = 'Show-Menu.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
    Author            = 'PowerShell User'
    CompanyName       = ''
    Copyright         = '(c) 2024 PowerShell User. All rights reserved.'
    Description       = 'Interactive menu system for PowerShell with keyboard navigation'
    
    PowerShellVersion = '5.1'
    
    FunctionsToExport = @('Show-Menu')
    AliasesToExport   = @()
    CmdletsToExport   = @()
    
    RequiredModules   = @()
    
    PrivateData       = @{
        PSData = @{
            Tags       = @('menu', 'interactive', 'ui', 'console', 'navigation', 'selection')
            LicenseUri = ''
            ProjectUri = ''
            ReleaseNotes = 'Initial release with interactive menu navigation and error handling'
        }
    }
}