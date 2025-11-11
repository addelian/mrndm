#!/usr/bin/env bash

set -e

. ./mrndm.config

authbody=$(jq --null-input \
  --arg user "$username" \
  --arg pass "$password" \
  '{username: $user, password: $pass}')

retrieve_memos() {
    if [[ -n "$token" ]]; then
        curl -H "Authorization: Token $token" $baseApiUrl/memos/
        exit 0
    fi
    authenticate
    retrieve_memos
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

if [ "$1" = "view" ] && [[ $2 =~ ^[0-9]+$ ]]; then
    retrieve_memo $2
    exit 0
fi

if [ "$1" = "auth" ]; then
    if [[ -n "$token" ]]; then
        echo "'token' field already present in config. If it's invalid, please remove that line before re-running this command."
        exit 0
    fi
    authenticate
    exit 0
fi

if [ "$1" = "init" ]; then
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
    curl -X POST -H "Content-Type:application/json" -d "$registerbody" "http://127.0.0.1:8000/register/"
    printf "username=$newuser\npassword=$newpass\nbaseApiUrl=http://127.0.0.1:8000/" > mrndm.config
    exit 0
fi

retrieve_memos