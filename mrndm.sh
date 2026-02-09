#!/usr/bin/env bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

command=$1
option=$2
category="MISC"

config="$HOME/.config/mrndm.conf"

if [[ -f "$config" ]]; then
    source "$config"
fi

if [[ -n "$3" ]]; then
    category=$3
fi

show_full_help() {
        cat <<'FULL'
USAGE
    mrndm <command> <subcommand>

SETUP COMMANDS
    init (-i):              Installs mrndm on your PATH and creates a config file. Run this before you do anything else.
    register (-r):          Registers a username and password and uses them to retrieve a token.
    sync (-sc):             Generates a token for an existing user and saves it to the config file.

MEMO-WRITING COMMANDS
    "Memo text":            Saves a memo (defaults to MISC)
    "Memo text" <category>: Saves a memo under the specified category
    delete (-d):            Deletes your most recent memo (returns it after deletion)
    delete <#>:             Deletes the memo with ID <#>

MEMO-RETRIEVING COMMANDS
    view (-v):              Shows your last five memos (grouped by category)
    view <#>:               Shows the memo with ID <#>
    view <category>:        Shows all memos in the designated category
    view all (-va):         Shows all memos (Grouped by category, sorted newest to oldest)

CATEGORIES
    MISC (default)
    RMND
    TODO
    IDEA
    WORK
    TECH
    HOME
    QUOT
    EARS
    EYES
    FOOD
    DRNK

EXAMPLES
    mrndm "So it goes"
    mrndm view
    mrndm "We're out of coffee" RMND
    mrndm view TODO
    mrndm delete
    mrndm delete 3
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
        -i|init|-v|view|-va|-m|memo|-d|delete|-r|register|-h|help|-s|sync)
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
        responsejson=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/")
        results_count=$(echo "$responsejson" | jq -r '.results | length')
        if [[ "$results_count" -eq 0 ]]; then
            echo "No memos submitted."
            exit 0
        fi
        echo "$responsejson" | jq -r '.results | 
            group_by(.category) | 
            map("| --- " + .[0].category + " --- |\n" + 
                (sort_by(-.id) | 
                 map(.body + " (" + (.id|tostring) + ")") | 
                 join("\n"))) | 
            join("\n\n")'
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    retrieve_memos
}

retrieve_last_five() {
    if [[ -n "$token" ]]; then
        responsejson=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/")
        results=$(echo "$responsejson" | jq -r '.results // empty')
        if [[ "$results" ]]; then
                echo "$responsejson" | jq -r '(.results) as $all | if ($all | length) == 0 then "No memos submitted." else ($all | sort_by(-.id) | .[0:5] | group_by(.category) | map("| --- " + .[0].category + " --- |\n" + (sort_by(-.id)|map(.body + " (" + (.id|tostring) + ")")|join("\n"))) | join("\n\n")) end'
            exit 0
        fi
        echo "error: $responsejson"
        exit 1
    fi
    echo "Token not present in config file."
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
        responsejson=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/")
        results_count=$(echo "$responsejson" | jq -r '.results | length')
        if [[ "$results_count" -eq 0 ]]; then
            echo "No memos submitted."
            exit 0
        fi
        echo "$responsejson" | jq -r --arg cat "$catarg" '.results | map(select(.category==$cat)) |
            sort_by(-.id) | 
            if (.|length)>0 then 
                ("| --- " + .[0].category + " --- |\n" + (map(.body + " (" + (.id|tostring) + ")") |
                join("\n"))) else ("No memos in category: " + $cat) end'
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    retrieve_memos_by_category "$catarg"
}

submit() {
    if [[ -n "$token" ]]; then
        responsejson=$(curl -s -X POST \
        -H "Authorization: Token $token" \
        -H "Content-Type:application/json" \
        -d "$postbody" $baseApiUrl/memos/)
        responsebody=$(echo "$responsejson" | jq -r '.body // empty')
        if [[ -z "$responsebody" ]]; then
            echo "error: $responsejson"
            exit 1
        fi
        echo "$responsejson" | jq -r '"Saved: " + .body + "\nCategory: " + .category'
        exit 0
    fi
    echo "Token not present in config file."
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
    echo "Token not present in config file."
    sleep 1
    authenticate
    delete
}

retrieve_memo() {
    if [[ -n "$token" ]]; then
        responsejson=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/$1/")
        responsebody=$(echo "$responsejson" | jq -r '.body // empty')
        if [[ -z "$responsebody" ]]; then
            echo "Memo not found with ID $1"
            exit 0
        fi
        echo "$responsejson" | jq -r '"| --- " + .category + " --- |\n" + (.body + " (" + (.id|tostring) + ")")'
        exit 0
    fi
    echo "Token not present in config file."
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
    retrieve_token "$user" "$pass"
    echo -e "User ${GREEN}$user${NC} synced back up with the mrndm server."
    sleep 1
    echo "Config written to $config."
    sleep 1
    echo "Welcome back!"
    exit 0
}

retrieve_token() {
    authbody=$(jq --null-input --arg user "$1" --arg pass "$2" '{username: $user, password: $pass}')
    tokenjson=$(curl -s -X POST -H "Content-Type:application/json" -d "$authbody" "$baseApiUrl/login/")
    token=$(echo "$tokenjson" | jq -r '.token')
    if [[ -z "$token" || "$token" == "null" ]]; then
        echo "Authentication failed. Server response:"
        echo "$tokenjson"
        exit 1
    fi
    # Overwrite config with baseApiUrl and token
    printf "baseApiUrl=%s\ntoken=%s\n" "$baseApiUrl" "$token" > $config
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
    if [[ $option = "TODO" || $option = "RMND" || $option = "MISC" ||
        $option = "IDEA" || $option = "WORK" || $option = "TECH" || 
        $option = "HOME" || $option = "QUOT" || $option = "EARS" || 
        $option = "EYES" || $option = "FOOD" || $option = "DRNK"
    ]]; then
        retrieve_memos_by_category "$option"
        exit 0
    fi

    # All memos
    if [[ $option = "all" || $option = "-va" || $option = "--all" || $option = "-a" ]]; then
        retrieve_memos
        exit 0
    fi

    echo "USAGE:"
    echo "view (-v): show your last five memos"
    echo "view <#>: return a single memo with the provided ID number"
    echo "view all (-va): view all written memos"
    echo "view <category>: view memos in the designated category"
    exit 0
}

register() {
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
        printf "baseApiUrl=%s\n" "$baseApiUrl" > $config
        echo "User registered successfully. Retrieving token..."
        retrieve_token "$newuser" "$newpass"
        sleep 1
        echo "Token retrieved successfully and config written to $config."
        sleep 1
        echo -e "You're all set up, ${GREEN}$newuser${NC}. Enjoy mrndm."
        exit 0
    fi
    echo "error: $responsejson"
    exit 1
}

init() {
    read -p "Choose where you want to install mrndm [default: $HOME/.local/bin]: " installdir
    installdir=${installdir:-"$HOME/.local/bin"}
    if [[ -d "$installdir" ]] || mkdir -p "$installdir" 2>/dev/null; then
        dest="$installdir/mrndm"
        if cp "$0" "$dest" 2>/dev/null; then
            chmod +x "$dest"
            echo "Checking config file..."
            if [[ -f "$config" ]]; then
                echo "Config file already exists. Config initialization not needed."
            else
                echo "No config file detected."
                read -p "Are you running mrndm in dev mode or user mode? (dev/user) [default: user]: " devmode
                devmode=${devmode:-"user"}
                if [[ "$devmode" == "dev" ]]; then
                    echo "Initializing config with a local URL. Run 'mrndm register' to register, or 'mrndm sync' if you already have an account."
                    printf "baseApiUrl=http://127.0.0.1:8000" > $config
                elif [[ "$devmode" == "user" ]]; then
                    echo "Initializing config with the default server URL. Run 'mrndm register' to register, or 'mrndm sync' if you already have an account."
                    printf "baseApiUrl=https://our.plots.club" > $config
                else
                    echo "Invalid choice. Exiting installation."
                    exit 1
                fi
            fi
            echo "Installed to $dest"
            echo "Ensure $installdir is on your PATH (add to ~/.profile or ~/.bashrc if needed)."
            exit 0
        fi
    fi
    echo "Failed to install."
    echo "Copy the script to a directory on your PATH, e.g. $HOME/.local/bin or /usr/local/bin"
    exit 1
}

case $command in

    -r | register) 
        register
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

    -i | init)
        init
        ;;

    -h | help)
        show_full_help
        exit 0
        ;;

esac