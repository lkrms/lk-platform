#!/usr/bin/osascript

if not application "iTerm" is running then
    activate application "iTerm"
else
    tell application "iTerm"
        create window with default profile
    end tell
end if
