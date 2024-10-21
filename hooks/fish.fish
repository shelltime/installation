#!/usr/bin/env fish

# Check if malamtime CLI exists
if not command -v malamtime &> /dev/null
    echo "Warning: malamtime CLI not found. Please install it to enable time tracking."
else
    malamtime gc
end

# Create a timestamp for the session when the shell starts
set -g MALAM_SESSION_ID (date +%Y%m%d%H%M%S)

# Define the preexec function
function fish_preexec --on-event fish_preexec
    if string match -q 'exit*' -- $argv; or string match -q 'logout*' -- $argv; or string match -q 'reboot*' -- $argv
        return
    end

    malamtime track -s=fish -id=$MALAM_SESSION_ID -cmd="$argv" -p=pre &
end

# Define the postexec function
function fish_postexec --on-event fish_postexec
    set -g LAST_RESULT (echo $status)
    if string match -q 'exit*' -- $argv; or string match -q 'logout*' -- $argv; or string match -q 'reboot*' -- $argv
        return
    end
    # This event is triggered before each prompt, which is after each command
    malamtime track -s=fish -id=$MALAM_SESSION_ID -cmd="$argv" -p=post -r=$LAST_RESULT &
end
