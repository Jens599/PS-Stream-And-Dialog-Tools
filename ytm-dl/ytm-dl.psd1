@{
    RootModule        = 'ytm-dl.psm1'
    ModuleVersion     = '0.0.1'
    GUID              = 'af38257d-2d5f-4aab-a697-1515949efab2'
    Author            = 'workj'
    CompanyName       = 'Unknown'
    Copyright         = '(c) workj. All rights reserved.'
    Description       = 'YouTube Music downloader wrapper'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-YtmDownload')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('ydl', 'ytm-dl')
    PrivateData       = @{
        PSData = @{
    
        } 
    } 
}
