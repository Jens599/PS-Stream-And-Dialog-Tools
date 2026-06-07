# PowerShell Modules Collection

A collection of custom PowerShell modules for enhanced productivity and media playback capabilities.

## Available Modules

### Add-Path
**Version:** 1.0.0  
**Description:** Permanently add a directory to the user or machine PATH.

```powershell
Add-Path -Path 'C:\Tools\MyTool'
Add-Path -Path 'C:\Tools\MyTool' -Scope Machine
```

### Show-Menu
**Version:** 0.1.0  
**Description:** Interactive menu system for PowerShell with keyboard navigation

An interactive console menu that allows users to navigate options using arrow keys and select with Enter. Perfect for creating user-friendly scripts with multiple choices.

#### Features
- Arrow key navigation (Up/Down)
- Enter to select, Escape to cancel
- Customizable menu titles
- Return selected option or index
- Clean console interface with cursor hiding

#### Usage Examples
```powershell
# Basic usage
$choices = 'Restart Service', 'Stop Service', 'Check Status', 'Exit'
$result = Show-Menu -Options $choices

# With custom title
$result = Show-Menu -Options 'Option 1', 'Option 2', 'Option 3' -Title 'Server Management'

# Return index instead of value
$index = Show-Menu -Options 'Option 1', 'Option 2', 'Option 3' -ReturnIndex
$selectedOption = $choices[$index]
```

### Start-MPVStream
**Version:** 0.1.0  
**Alias:** `play`  
**Description:** PowerShell wrapper for mpv media player with YouTube search capabilities

A comprehensive media player wrapper that provides streamlined playback experience with YouTube search, playlist support, and various playback options.

#### Dependencies
- `mpv` - Required for media playback
- `yt-dlp` - Required for YouTube search functionality
- `Show-Menu` - Optional, for interactive search results selection

#### Features
- Direct URL playback
- YouTube video and playlist search
- Multiple window sizes (PIP, Small, Medium, Max)
- Quality selection (480p, 720p, 1080p, best, audio-only)
- Background playback mode
- Hardware acceleration support
- Playlist control (reverse order)
- Loop playback
- Cookie-based authentication for YouTube
- Persistent cookie path configuration

#### Usage Examples
```powershell
# Direct playback
play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'

# YouTube search
play 'never gonna give you up' -s

# Search for playlists with audio-only
play 'lofi beats' -s -p -f audio

# Custom size and quality
play 'https://youtu.be/dQw4w9WgXcQ' -sz Small -f 720p

# Configure cookie path (saved persistently)
play -c 'C:\Users\username\Downloads\cookies.txt'

# Play with authenticated content using saved cookie path
play 'https://www.youtube.com/playlist?list=PLW8XZTagL0oJhk71Ip3rIzHOFY3Edw2pw'
```

### ytm-dl
**Version:** 0.0.1  
**Aliases:** `ydl`, `ytm-dl`  
**Description:** YouTube Music audio downloader wrapper around `yt-dlp`.

#### Dependencies
- `yt-dlp` - Required for downloads
- `aria2c` - Optional, for faster downloads
- `picard` - Optional, launched after downloads for tagging

#### Usage Examples
```powershell
Invoke-YtmDownload 'https://music.youtube.com/watch?v=...'
Invoke-YtmDownload -Url 'C:\music\urls.txt' -OutputDir 'D:\MyMusic' -Parallel 4
'url1', 'url2' | Invoke-YtmDownload -Parallel 2
```

## Installation

1. Clone this repository, then copy or symlink each module directory into a path listed in `$env:PSModulePath`, such as `$env:USERPROFILE\Documents\PowerShell\Modules`:
   ```powershell
   git clone <repository-url> .\PS-Stream-And-Dialog-Tools
   Copy-Item .\PS-Stream-And-Dialog-Tools\Show-Menu $env:USERPROFILE\Documents\PowerShell\Modules -Recurse
   Copy-Item .\PS-Stream-And-Dialog-Tools\Start-MPVStream $env:USERPROFILE\Documents\PowerShell\Modules -Recurse
   Copy-Item .\PS-Stream-And-Dialog-Tools\Add-Path $env:USERPROFILE\Documents\PowerShell\Modules -Recurse
   Copy-Item .\PS-Stream-And-Dialog-Tools\ytm-dl $env:USERPROFILE\Documents\PowerShell\Modules -Recurse
   ```

2. Load every module from your PowerShell profile by dot-sourcing the project loader:
   ```powershell
   '. C:\path\to\PS-Stream-And-Dialog-Tools\Profile\PS-Stream-And-Dialog-Tools.profile.ps1' | Add-Content -Path $PROFILE
   ```

   Open a new PowerShell session, or run the same dot-source command directly in your current session.

## System Requirements

- PowerShell 5.1 or later
- Windows operating system
- For Start-MPVStream: mpv media player installed and in PATH
- For Start-MPVStream search and ytm-dl downloads: yt-dlp installed and in PATH

## Module Dependencies

### Start-MPVStream Dependencies
- **mpv**: Media player for video/audio playback
- **yt-dlp**: YouTube downloader and search tool
- **Show-Menu**: Optional, for interactive search result selection

## Contributing

Feel free to submit issues and enhancement requests!
