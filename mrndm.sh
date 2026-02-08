#!/usr/bin/env bash

set -e

. ./mrndm.config

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

command=$1
option=$2
category="MISC"

if [[ -n "$3" ]]; then
    category=$3
fi

show_full_help() {
        cat <<'FULL'
Usage: mrndm [command] [options*]

(path/to/package/)mrndm.sh install
    - Copies the script into a PATH directory so you can run `mrndm` directly.
      Otherwise, you'll need to run all the below commands with `./mrndm.sh` instead of `mrndm`

mrndm init (-i)
    - Registers a username and password and saves them to the config file. Only needs to be done once.

mrndm "Your memo text"
    - Saves a memo (defaults to MISC)

mrndm "Buy milk" TODO
    - Saves a memo under TODO, RMND, or MISC

mrndm view (-v)
    - Shows your last five memos (grouped by category)

mrndm view <#>
    - Shows the memo with ID <#>

mrndm view (RMND/TODO/MISC)
    - Shows all memos in the designated category

mrndm view all (-va)
    - Shows all memos (Grouped by category, sorted newest to oldest)

mrndm delete
    - Deletes your most recent memo (returns it after deletion)
    
mrndm delete <#>
    - Deletes the memo with ID <#>

mrndm auth
    - Explicitly generates a new token.
      Only needed if you need to refresh an expired token, or if the token field is missing from the config file
FULL
}

# If no arguments supplied, show a minimal quick usage summary and exit
if [[ -z "$command" ]]; then
        cat <<'USAGE'
Usage:

mrndm "Your memo text"
    - Saves a memo

mrndm view
    - Shows your last five memos (grouped by category)

mrndm delete
    - Deletes your most recent memo (or use an ID: mrndm delete <#>)

Run `mrndm help (mrndm -h)` for full usage information.
USAGE
        exit 0
fi

# If the first arg isn't a known command, treat it as the memo body
if [[ -n $command ]]; then
    case $command in
        -i|init|-v|view|-va|-m|memo|-d|delete|install|-h|help|-s|sync)
            ;; # known commands; leave as-is
        *)
            option=$command
            if [[ -n "$2" ]]; then
                category=$2
            else
                category="MISC"
            fi
            command="-m"
            ;;
    esac
fi

postbody=$(jq --null-input \
    --arg body "$option" \
    --arg category "$category" \
    '{body: $body, category: $category}')

retrieve_memos() {
    if [[ -n "$token" ]]; then
        curl -s -H "Authorization: Token $token" $baseApiUrl/memos/ | \
        jq -r '.results | 
            group_by(.category) | 
            sort_by(.[0].category) | 
            reverse | 
            map("| --- " + .[0].category + " --- |\n" + 
                (sort_by(-.id) | 
                 map(.body + " (" + (.id|tostring) + ")") | 
                 join("\n"))) | 
            join("\n\n")'
        exit 0
    fi
    echo "Token not present in .config file."
    sleep 1
    authenticate
    retrieve_memos
}

retrieve_last_five() {
    if [[ -n "$token" ]]; then
        responsejson=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/")
        results=$(echo "$responsejson" | jq -r '.results // empty')
        if [[ "$results" ]]; then
                echo "$responsejson" | jq -r '(.results) as $all | if ($all | length) == 0 then "No memos submitted." else ($all | sort_by(-.id) | .[0:5] as $subset |
                $subset as $r | ["TODO","RMND","MISC"] as $order |
                $order | map( . as $cat | ($r | map(select(.category==$cat)) ) as $items |
                if ($items|length)>0 then 
                    ("| --- " + $cat + " --- |\n" + 
                    ($items|sort_by(-.id)|map(.body + " (" + (.id|tostring) + ")")|join("\n"))) 
                else empty end) | join("\n\n")) end'
            exit 0
        fi
        echo "error: $responsejson"
        exit 1
    fi
    echo "Token not present in .config file."
    sleep 1
    authenticate
    retrieve_last_five
}

retrieve_memos_by_category() {
    catarg="$1"
    if [[ -z "$catarg" ]]; then
        catarg="$category"
    fi
    if [[ -n "$token" ]]; then
        curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/" | \
        jq -r --arg cat "$catarg" '.results | map(select(.category==$cat)) |
            sort_by(-.id) | 
            if (.|length)>0 then 
                ("| --- " + .[0].category + " --- |\n" + (map(.body + " (" + (.id|tostring) + ")") |
                join("\n"))) else ("No memos in category: " + $cat) end'
        exit 0
    fi
    echo "Token not present in .config file."
    sleep 1
    authenticate
    retrieve_memos_by_category "$catarg"
}

submit() {
    if [[ $category != "MISC" && $category != "RMND" && $category != "TODO" ]]; then
        echo "Invalid category choice."
        echo "Options are MISC, RMND, or TODO (defaults to MISC if excluded)"
        exit 0
    fi
    if [[ -n "$token" ]]; then
        curl -s -X POST \
        -H "Authorization: Token $token" \
        -H "Content-Type:application/json" \
        -d "$postbody" $baseApiUrl/memos/ | \
        jq -r '"Saved: " + .body + "\nCategory: " + .category'
        exit 0
    fi
    echo "Token not present in .config file."
    sleep 1
    authenticate
    submit
}

delete() {
    if [[ -n "$token" ]]; then
        # If no ID provided, find and delete the most recent memo
        if [[ -z "$option" ]]; then
            memo_to_delete=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/" | \
            jq -r '.results | sort_by(-.id) | .[0]')
            
            memo_id=$(echo "$memo_to_delete" | jq -r '.id')
            
            if [[ -z "$memo_id" || "$memo_id" = "null" ]]; then
                echo "No memos to delete."
                exit 0
            fi
            
            # Delete the memo
            curl -s -X DELETE \
            -H "Authorization: Token $token" \
            "$baseApiUrl/memos/$memo_id/" > /dev/null
            
            # Return the deleted memo formatted
            echo "Deleted:"
            echo "$memo_to_delete" | jq -r '.body + " (" + (.id|tostring) + ")"'
            exit 0
        fi
        
        # If ID provided, fetch the memo first, then delete it
        memo_to_delete=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/$option/")
        
        curl -s -X DELETE \
        -H "Authorization: Token $token" \
        "$baseApiUrl/memos/$option/" > /dev/null
        
        # Display the deleted memo
        echo "Deleted:"
        echo "$memo_to_delete" | jq -r '.body + " (" + (.id|tostring) + ")"'
        exit 0
    fi
    echo "Token not present in .config file."
    sleep 1
    authenticate
    delete
}

retrieve_memo() {
    if [[ -n "$token" ]]; then
        curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/$1/" | \
        jq -r '"| --- " + .category + " --- |\n" + (.body + " (" + (.id|tostring) + ")")'
        exit 0
    fi
    echo "Token not present in .config file."
    sleep 1
    authenticate
    retrieve_memo $1
}

authenticate() {
    echo "Enter your username:"
    read user
    echo "Enter your password:"
    read -s pass
    echo
    echo "Attempting to authenticate..."
    retrievetoken "$user" "$pass"
    echo -e "User ${GREEN}$user${NC} synced back up with the mrndm server."
    sleep 1
    echo "Config written to ./mrndm.config."
    sleep 1
    echo "Welcome back!"
    exit 0
}

retrievetoken() {
    authbody=$(jq --null-input --arg user "$1" --arg pass "$2" '{username: $user, password: $pass}')
    tokenjson=$(curl -s -X POST -H "Content-Type:application/json" -d "$authbody" "$baseApiUrl/auth/")
    token=$(echo "$tokenjson" | jq -r '.token')
    if [[ -z "$token" || "$token" == "null" ]]; then
        echo "Authentication failed. Server response:"
        echo "$tokenjson"
        exit 1
    fi
    # Overwrite config with baseApiUrl and token
    printf "baseApiUrl=%s\ntoken=%s\n" "$baseApiUrl" "$token" > mrndm.config
}

view() {
    # No option -> show last five memos
    if [[ -z "$option" ]]; then
        retrieve_last_five
        exit 0
    fi

    # Numeric option -> single memo by ID
    if [[ $option =~ ^[0-9]+$ ]]; then
        retrieve_memo $option
        exit 0
    fi

    # Direct category (e.g. mrndm view TODO)
    if [[ $option = "TODO" || $option = "RMND" || $option = "MISC" ]]; then
        retrieve_memos_by_category "$option"
        exit 0
    fi

    # All memos
    if [[ $option = "all" || $option = "-va" || $option = "--all" || $option = "-a" ]]; then
        retrieve_memos
        exit 0
    fi

    # Category filter: mrndm view --category TODO (fallback)
    if [[ $option = "--category" || $option = "-c" ]]; then
        if [[ -n "$category" ]]; then
            retrieve_memos_by_category "$category"
            exit 0
        fi
        echo "USAGE: mrndm view --category <RMND|TODO|MISC>"
        exit 1
    fi

    echo "USAGE:"
    echo "view (-v): show your last five memos"
    echo "view <#>: return a single memo with the provided ID number"
    echo "view all (-va): view all written memos"
    echo "view --category <RMND|TODO|MISC> or view <RMND|TODO|MISC>: view memos in the designated category"
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
    responsejson=$(curl -s -X POST -H "Content-Type:application/json" -d "$registerbody" "$baseApiUrl/register/")
    message=$(echo "$responsejson" | jq -r '.message // empty')
    if [[ "$message" == "User registered successfully" ]]; then
        printf "baseApiUrl=%s\n" "$baseApiUrl" > mrndm.config
        echo "User registered successfully. Retrieving token..."
        retrievetoken "$newuser" "$newpass"
        sleep 1
        echo "Token retrieved successfully and config written to ./mrndm.config."
        sleep 1
        echo -e "You're all set up, ${GREEN}$newuser${NC}. Enjoy mrndm."
        exit 0
    fi
    echo "error: $responsejson"
    exit 1
}

install_self() {
    target_dirs=("$HOME/.local/bin" "$HOME/bin" "/usr/local/bin")
    for dir in "${target_dirs[@]}"; do
        if [[ -d "$dir" ]] || mkdir -p "$dir" 2>/dev/null; then
            dest="$dir/mrndm"
            if cp "$0" "$dest" 2>/dev/null; then
                chmod +x "$dest"
                echo "Installed to $dest"
                echo "Ensure $dir is on your PATH (add to ~/.profile or ~/.bashrc if needed)."
                exit 0
            else
                if [[ "$dir" = "/usr/local/bin" ]]; then
                    echo "Permission needed to copy to $dir; attempting with sudo..."
                    if sudo cp "$0" "$dest" 2>/dev/null; then
                        sudo chmod +x "$dest"
                        echo "Installed to $dest (with sudo)"
                        exit 0
                    fi
                fi
            fi
        fi
    done
    echo "Failed to install."
    echo "Copy the script to a directory on your PATH, e.g. $HOME/.local/bin or /usr/local/bin"
    exit 1
}

case $command in

    -i | init) 
        init
        ;;

    -v | view)
        view
        ;;

    -va)
        retrieve_memos
        ;;
    
    -m | memo)
        submit
        ;;

    -d | delete)
        delete
        ;;

    -s | sync)
        authenticate
        ;;

    install)
        install_self
        ;;

    -h | help)
        show_full_help
        exit 0
        ;;

esac