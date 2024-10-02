#!/usr/bin/env fish

# Create a timestamp for the session when the shell starts
set -g MALAM_SESSION_ID (date +%Y%m%d%H%M%S)

# Define the preexec function
function fish_preexec --on-event fish_preexec
    malamtime track fish $MALAM_SESSION_ID $argv &
    echo "preexec: Executing command: $argv[1]"
    echo "preexec: Session ID: $MALAM_SESSION_ID"
    echo "preexec: All arguments: $argv"
end

# Define the postexec function
function fish_postexec --on-event fish_postexec
    # This event is triggered before each prompt, which is after each command
    malamtime track fish $MALAM_SESSION_ID $argv &
    echo "postexec: Command finished"
    echo "postexec: Session ID: $MALAM_SESSION_ID"
    echo "postexec: All arguments: $argv"
end
