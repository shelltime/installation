#!/usr/bin/env zsh

# Check if shelltime command exists
if ! command -v shelltime &> /dev/null
then
    echo "Warning: shelltime command not found. Please install it to track shell usage."
else
    shelltime gc
fi

# Create a timestamp for the session when the shell starts
SESSION_ID=$(date +%Y%m%d%H%M%S)

# Define the preexec function
preexec() {
    # Check if command starts with exit, logout, or reboot
    if [[ $argv =~ ^(exit|logout|reboot) ]]; then
        return
    fi

    shelltime track -s=zsh -id=$SESSION_ID -cmd=$argv -p=pre &> /dev/null
}

# Define the postexec function (in zsh, it's called precmd)
precmd() {
    LAST_RESULT=$?
    # Check if command starts with exit, logout, or reboot
    if [[ $argv =~ ^(exit|logout|reboot) ]]; then
        return
    fi
    shelltime track -s=zsh -id=$SESSION_ID -cmd=$argv -p=post -r=$LAST_RESULT &> /dev/null
}
