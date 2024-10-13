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
    malamtime track -s=zsh -id=$MALAM_SESSION_ID -cmd=$argv -p=pre &
}

# Define the postexec function (in zsh, it's called precmd)
precmd() {
    malamtime track -s=zsh -id=$MALAM_SESSION_ID -cmd=$argv -p=post -r=$? &
}
