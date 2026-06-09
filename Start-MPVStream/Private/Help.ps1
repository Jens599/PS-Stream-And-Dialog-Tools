function Write-MPVStreamHelp {

    $cCmd = "Cyan"; $cDesc = "Gray"; $cHead = "Yellow"
    
    Write-Host "`nusage: play <url> [options]" -ForegroundColor $cHead 
    Write-Host "   or: play <query> -s [options]" -ForegroundColor $cHead 
    Write-Host "   or: play -c <cookie-path> [config mode]" -ForegroundColor $cHead 
    Write-Host "`nPlayback Control" -ForegroundColor White 
    Write-Host "    $("{0,-22}" -f "-Size, -sz <mode>") Window (PIP, Small, Medium, Max)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-YtdlFormat, -f <mode>") Quality (480p, 720p, 1080p, best, audio)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-AudioOnly, -a") Stream audio only" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Background, -b") Run in background process" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Loop, -l") Loop playback infinitely" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-HardwareAccel, -h") Enable hardware acceleration" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-MpvArgument <arg>") Extra mpv argument(s) appended to launch" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-DryRun") Show final command without starting mpv" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-PassThru, -pt") Return structured dry-run launch data" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-SelectOnly, -so") Return selected item without playing" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-CopyUrl, -cu") Copy selected URL without playing" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Open, -o") Open selected URL in browser instead of mpv" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-SubtitleLanguage") Preferred subtitle language(s), e.g. en,ja" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-NoSubtitles, -nosub") Disable subtitle language preference" -ForegroundColor $cDesc 
    Write-Host "`nSearch Features" -ForegroundColor White 
    Write-Host "    $("{0,-22}" -f "-Search, -s") Search YouTube instead of direct URL" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Playlist, -p") Search for playlists only" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-First, -fi") Play first search result without picker" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Type, -t <type>") Filter mixed results (Video, Playlist, Channel)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-MaxResults, -max <num>") Number of search results (1-50, default: 10)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Clipboard, -cb") Play URL from clipboard" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-History, -hi") Pick from playback history" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Last, -la") Replay last history item" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-ReversePlaylist, -r") Reverse playlist order" -ForegroundColor $cDesc 
    Write-Host "`nConfiguration" -ForegroundColor White 
    Write-Host "    $("{0,-22}" -f "-CookiePath, -c <path>") Path to cookie file (saved persistently)" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "Player Path") Set in -Config; supports mpv, mpvnet.com, or full path" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-Config, -cfg") Interactive persistent configuration" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-ConfigExport <path>") Export persistent config JSON" -ForegroundColor $cDesc 
    Write-Host "    $("{0,-22}" -f "-ConfigImport <path>") Import persistent config JSON" -ForegroundColor $cDesc 
    Write-Host "`nExamples" -ForegroundColor White 
    Write-Host "    play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'" -ForegroundColor $cDesc 
    Write-Host "    play 'never gonna give you up' -s" -ForegroundColor $cDesc 
    Write-Host "    play 'never gonna give you up' -s -MaxResults 20" -ForegroundColor $cDesc 
    Write-Host "    play 'never gonna give you up' -s -CopyUrl" -ForegroundColor $cDesc 
    Write-Host "    play 'never gonna give you up' -s -Open" -ForegroundColor $cDesc 
    Write-Host "    play 'never gonna give you up' -s -First" -ForegroundColor $cDesc 
    Write-Host "    play -Clipboard" -ForegroundColor $cDesc 
    Write-Host "    play -History" -ForegroundColor $cDesc 
    Write-Host "    play -Last" -ForegroundColor $cDesc 
    Write-Host "    play 'live coding' -s -Type Playlist" -ForegroundColor $cDesc 
    Write-Host "    play 'lofi beats' -s -p -f audio" -ForegroundColor $cDesc 
    Write-Host "    play 'https://youtu.be/dQw4w9WgXcQ' -SubtitleLanguage en,ja" -ForegroundColor $cDesc 
    Write-Host "    play 'https://youtu.be/dQw4w9WgXcQ' -MpvArgument '--speed=1.25' -DryRun" -ForegroundColor $cDesc 
    Write-Host "    play 'https://youtu.be/dQw4w9WgXcQ' -DryRun -PassThru" -ForegroundColor $cDesc 
    Write-Host "    play 'https://youtu.be/dQw4w9WgXcQ' -sz Small -f 720p" -ForegroundColor $cDesc 
    Write-Host "    play 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' -c cookies.txt" -ForegroundColor $cDesc 
    Write-Host "    play -c .\Downloads\Compressed\cookies.txt" -ForegroundColor $cDesc 
    Write-Host "    play --config" -ForegroundColor $cDesc 
    Write-Host "    play -ConfigExport .\start-mpvstream.config.json" -ForegroundColor $cDesc 
    Write-Host "    play -ConfigImport .\start-mpvstream.config.json" -ForegroundColor $cDesc 
}
