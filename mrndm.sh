#!/usr/bin/env bash

set -e

. ./mrndm.config

retrieve_memos() {
    curl -u "$username":"$password" http://127.0.0.1:8000/memos/
}

retrieve_memo() {
    curl -u "$username":"$password" http://127.0.0.1:8000/memos/$1/
}

echo $1
echo $2

if [ $1 = "view" ] && [[ $2 =~ ^[0-9]+$ ]]; then
    retrieve_memo $2
    exit 0
fi

retrieve_memos