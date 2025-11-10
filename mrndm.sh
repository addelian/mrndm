#!/usr/bin/env bash

set -e

. ./mrndm.config

authbody=$(jq --null-input \
  --arg user "$username" \
  --arg pass "$password" \
  '{username: $user, password: $pass}')

retrieve_memos() {
    if [[ -n "$token" ]]; then
        curl -u "$username":"$password" -H "Authorization: Token $token" $baseApiUrl/memos/
        exit 0
    fi
    authenticate
    retrieve_memos
}

retrieve_memo() {
    if [[ -n "$token" ]]; then
        curl -u "$username":"$password" -H "Authorization: Token $token" $baseApiUrl/memos/$1/
        exit 0
    fi
    authenticate
    retrieve_memo
}

authenticate() {
    tokenjson=$(curl -X POST -H "Content-Type:application/json" -d "$authbody" "$baseApiUrl/auth/")
    token=$(echo $tokenjson | jq -r '.token')
    echo " " >> ./mrndm.config
    echo "token=$token" >> ./mrndm.config
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
fi

retrieve_memos