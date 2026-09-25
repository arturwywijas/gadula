on run argv
    set sciezkaMontowania to item 1 of argv
    set aliasMontowania to (POSIX file (sciezkaMontowania & "/")) as alias
    set plikTla to (POSIX file (sciezkaMontowania & "/.background/tlo-instalatora.png")) as alias

    tell application "Finder"
        open aliasMontowania
        delay 1
        set okno to front Finder window
        set sciezkaOkna to POSIX path of (target of okno as alias)
        if sciezkaOkna is not (sciezkaMontowania & "/") then
            error "Finder nie otworzył oczekiwanego punktu montowania: " & sciezkaOkna
        end if
        set current view of okno to icon view
        set toolbar visible of okno to false
        set statusbar visible of okno to false
        set sidebar width of okno to 0
        set bounds of okno to {120, 120, 800, 500}

        set opcjeWidoku to icon view options of okno
        set arrangement of opcjeWidoku to not arranged
        set icon size of opcjeWidoku to 128
        set text size of opcjeWidoku to 14
        set background picture of opcjeWidoku to plikTla

        set position of item "Gaduła.app" of okno to {165, 180}
        set position of item "Applications" of okno to {515, 180}
        update (target of okno) without registering applications
        delay 1
        close okno
        delay 1
    end tell
end run
