@{
    RootModule        = 'Start-MPVStream.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'ec55bab7-93a5-4e9f-b244-6a9f56ff58a4'
    Author            = 'PowerShell User'
    CompanyName       = ''
    Copyright         = '(c) 2024 PowerShell User. All rights reserved.'
    Description       = 'PowerShell wrapper for mpv media player with YouTube search capabilities'
    
    PowerShellVersion = '5.1'
    
    FunctionsToExport = @('Start-MPVStream')
    AliasesToExport   = @('play')
    CmdletsToExport   = @()
    
    RequiredModules   = @()
    
    PrivateData       = @{
        PSData = @{
            Tags         = @('mpv', 'media', 'player', 'youtube', 'video', 'audio', 'stream')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = 'Initial release with mpv wrapper and YouTube search functionality'
        }
    }
}
