#!/usr/bin/env zsh

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
