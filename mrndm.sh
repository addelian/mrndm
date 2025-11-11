#!/usr/bin/env bash

set -e

. ./mrndm.config

command=$1
option=$2
category="MISC"

if [[ -n "$3" ]]; then
    category=$3
fi

authbody=$(jq --null-input \
    --arg user "$username" \
    --arg pass "$password" \
    '{username: $user, password: $pass}')

postbody=$(jq --null-input \
    --arg body "$option" \
    --arg category "$category" \
    '{body: $body, category: $category}')

retrieve_memos() {
    if [[ -n "$token" ]]; then
        curl -H "Authorization: Token $token" $baseApiUrl/memos/
        exit 0
    fi
    authenticate
    retrieve_memos
}

submit() {
    if [[ $category != "MISC" && $category != "RMND" && $category != "TODO" ]]; then
        echo "Invalid category choice - options are MISC, RMND, or TODO (defaults to MISC if excluded)"
        exit 0
    fi
    if [[ -n "$token" ]]; then
        curl -X POST \
        -H "Authorization: Token $token" \
        -H "Content-Type:application/json" \
        -d "$postbody" $baseApiUrl/memos/
        exit 0
    fi
    authenticate
    submit
}

retrieve_memo() {
    if [[ -n "$token" ]]; then
        curl -H "Authorization: Token $token" $baseApiUrl/memos/$1/
        exit 0
    fi
    authenticate
    retrieve_memo
}

authenticate() {
    echo "token not present in .config file. attempting to generate..."
    tokenjson=$(curl -X POST -H "Content-Type:application/json" -d "$authbody" "$baseApiUrl/auth/")
    token=$(echo $tokenjson | jq -r '.token')
    echo " " >> ./mrndm.config
    echo "token=$token" >> ./mrndm.config
    echo "token successfully generated and added to config file"
}

view() {
    if [[ $option =~ ^[0-9]+$ ]]; then
        retrieve_memo $option
        exit 0
    fi
    if [[ $option = "--all" || $option = "-a" ]]; then
        retrieve_memos
        exit 0
    fi
    echo "USAGE:"
    echo "view <#>: return a single memo with the provided ID number"
    echo "view -a / --all: view all written memos"
    exit 0
}

checkauth() {
    if [[ -n "$token" ]]; then
        echo "'token' field already present in config. If it's invalid, please remove that line before re-running this command."
        exit 0
    fi
    authenticate
    exit 0
}

init() {
    echo "Creating a new user. Enter a username:"
    read newuser
    echo "Enter a password:"
    read -s newpass
    echo "Re-enter your password:"
    read -s newpass2
    registerbody=$(jq --null-input \
    --arg user "$newuser" \
    --arg pass "$newpass" \
    --arg pass2 "$newpass2" \
    '{username: $user, password: $pass, password2: $pass2}')
    curl -X POST -H "Content-Type:application/json" -d "$registerbody" "$baseApiUrl/register/"
    printf "baseApiUrl=$baseApiUrl\nusername=$newuser\npassword=$newpass" > mrndm.config
    exit 0
}

case $command in

    init) 
        init
        ;;

    auth)
        checkauth
        ;;

    view)
        view
        ;;
    
    -m)
        submit
        ;;

esac

retrieve_memos