function Get-MPVStreamHelpMarkdown {
    @'
# Start-MPVStream

Stream YouTube URLs, searches, homepage recommendations, and history through `mpv` or `mpv.net`.

## Usage

```powershell
play <url> [options]
play <query> -Search [options]
play -Home [options]
play -CookiePath <path>
play -Config
```

## Playback

| Option | Description |
| --- | --- |
| `-Size`, `-sz <mode>` | Window size: `PIP`, `Small`, `Medium`, `Max` |
| `-YtdlFormat`, `-f <mode>` | Quality/format: `480p`, `720p`, `1080p`, `best`, `audio` |
| `-AudioOnly`, `-a` | Stream audio only |
| `-Background`, `-b` | Run player in a background process |
| `-Loop`, `-l` | Loop playback infinitely |
| `-HardwareAccel`, `-h` | Enable hardware acceleration |
| `-MpvArgument`, `-ma <arg>` | Append extra mpv arguments |
| `-DryRun`, `-dr` | Show final command without starting mpv |
| `-PassThru`, `-pt` | Return structured dry-run launch data |
| `-SelectOnly`, `-so` | Return selected item without playing |
| `-CopyUrl`, `-cu` | Copy selected URL without playing |
| `-Open`, `-o` | Open selected URL in browser instead of mpv |
| `-SubtitleLanguage`, `-sl` | Preferred subtitle language(s), e.g. `en,ja` |
| `-NoSubtitles`, `-nosub` | Disable subtitle language preference |

## Discovery

| Option | Description |
| --- | --- |
| `-Search`, `-s` | Search YouTube instead of playing a direct URL |
| `-Home`, `-Homepage` | Pick from YouTube homepage recommendations |
| `-Playlist`, `-p` | Search for playlists only |
| `-First`, `-fi` | Play first result without opening the picker |
| `-Type`, `-t <type>` | Filter mixed results: `Video`, `Playlist`, `Channel` |
| `-MaxResults`, `-max <num>` | Number of results to fetch, from `1` to `50` |
| `-Clipboard`, `-cb` | Play URL from clipboard |
| `-History`, `-hi` | Pick from playback history |
| `-ClearHistory`, `-ch` | Delete playback history |
| `-Last`, `-la` | Replay last history item |
| `-ReversePlaylist`, `-r` | Reverse playlist order |

## Configuration

| Option | Description |
| --- | --- |
| `-Config`, `-cfg` | Interactive persistent configuration |
| `-CookiePath`, `-c <path>` | Path to cookie file, saved persistently |
| `-Doctor`, `-doc` | Check players, tools, cookies, and app paths |
| `-ConfigExport <path>` | Export persistent config JSON |
| `-ConfigImport <path>` | Import persistent config JSON |

Config also supports:

| Setting | Description |
| --- | --- |
| Player Path | `mpv`, `mpvnet.com`, `mpvnet.exe`, or full path |
| Search UI Provider | `fzf`, `ConsoleGuiTools`, or basic prompt fallback |
| Help Renderer | `Auto`, `Glow`, or `Plain` Markdown rendering |

## Examples

```powershell
play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'
play 'never gonna give you up' -Search
play 'never gonna give you up' -Search -MaxResults 20
play 'never gonna give you up' -Search -CopyUrl
play 'never gonna give you up' -Search -Open
play 'never gonna give you up' -Search -First
```

```powershell
play -Home
play -Home -CopyUrl
play -Home -First
```

```powershell
play -Clipboard
play -History
play -History -Type Video
play -ClearHistory
play -Last
```

```powershell
play 'live coding' -Search -Type Playlist
play 'lofi beats' -Search -Playlist -YtdlFormat audio
play 'https://youtu.be/dQw4w9WgXcQ' -SubtitleLanguage en,ja
play 'https://youtu.be/dQw4w9WgXcQ' -MpvArgument '--speed=1.25' -DryRun
play 'https://youtu.be/dQw4w9WgXcQ' -DryRun -PassThru
play 'https://youtu.be/dQw4w9WgXcQ' -Size Small -YtdlFormat 720p
```

```powershell
play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' -CookiePath cookies.txt
play -CookiePath .\Downloads\Compressed\cookies.txt
play -Config
play -Doctor
play -ConfigExport .\start-mpvstream.config.json
play -ConfigImport .\start-mpvstream.config.json
```

## Notes

- `-Home` recommendations are more useful with a valid YouTube cookie file.
- Interactive lists can load more results up to 50.
- If `glow` is installed and Help Renderer is `Auto` or `Glow`, help is rendered as rich Markdown.
'@
}

function Normalize-MPVStreamHelpRenderer {
    param([string]$Renderer)

    switch -Regex ($Renderer) {
        '^Auto$' { return 'Auto' }
        '^Glow$' { return 'Glow' }
        '^Markdown$' { return 'Glow' }
        '^Plain$' { return 'Plain' }
        '^Text$' { return 'Plain' }
        default { return 'Auto' }
    }
}

function Test-MPVStreamGlowRenderer {
    [bool](Get-Command glow -ErrorAction SilentlyContinue)
}

function Write-MPVStreamHelp {
    param([pscustomobject]$Config)

    $markdown = Get-MPVStreamHelpMarkdown
    $renderer = 'Auto'
    if ($Config -and $Config.PSObject.Properties.Name -contains 'helpRenderer') {
        $renderer = Normalize-MPVStreamHelpRenderer $Config.helpRenderer
    }

    $useGlow = ($renderer -eq 'Glow' -or $renderer -eq 'Auto') -and (Test-MPVStreamGlowRenderer)
    if ($useGlow) {
        $markdown | glow -
        return
    }

    Write-Host $markdown
}
