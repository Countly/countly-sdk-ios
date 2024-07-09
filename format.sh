#!/bin/bash

CDP=$(osascript -e '
tell application "Xcode"
    activate
    --wait for Xcode to remove edited flag from filename
    delay 0.3
    set last_word_in_main_window to (word -1 of (get name of window 1))
    set current_document to document 1 whose name ends with last_word_in_main_window
    set current_document_path to path of current_document
    --CDP is assigned last set value: current_document_path
end tell ')

sleep 0.6 ### during save Xcode stops listening for file changes
/usr/local/bin/clang-format -style=file -i ${CDP}

# EOF
