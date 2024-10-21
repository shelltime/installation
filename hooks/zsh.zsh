#!/usr/bin/env zsh

# Check if malamtime command exists
if ! command -v malamtime &> /dev/null
then
    echo "Warning: malamtime command not found. Please install it to track shell usage."
else
    malamtime gc
fi

# Create a timestamp for the session when the shell starts
MALAM_SESSION_ID=$(date +%Y%m%d%H%M%S)

# Define the preexec function
preexec() {
    # Check if command starts with exit, logout, or reboot
    if [[ $argv =~ ^(exit|logout|reboot) ]]; then
        return
    fi

    malamtime track -s=zsh -id=$MALAM_SESSION_ID -cmd=$argv -p=pre &
}

# Define the postexec function (in zsh, it's called precmd)
precmd() {
    LAST_RESULT=$?
    # Check if command starts with exit, logout, or reboot
    if [[ $argv =~ ^(exit|logout|reboot) ]]; then
        return
    fi
    malamtime track -s=zsh -id=$MALAM_SESSION_ID -cmd=$argv -p=post -r=$LAST_RESULT &
}
