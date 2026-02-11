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

ACCOUNT COMMANDS
    init (-i):                Installs mrndm on your PATH and creates a config file. Run this before you do anything else.
    register (-r):            Registers a username and password and uses them to retrieve a token.
    sync (-sc):               Generates a token for an existing user and saves it to the config file. (Alias: login)
    logout (-l):              Deletes the token from the config file and logs out of the current session.
    password (-fp):           Initiates the password reset process (sends an email with instructions)
    user (me):                Shows information about your account (username, email if present)
    changeemail               Changes the email associated with your account (used for password recovery)
    deleteaccount (-da):      Deletes your account and all associated memos.

MEMO-WRITING COMMANDS
    "Memo text":              Saves a memo (defaults to MISC)
    "Memo text" <category>:   Saves a memo under the specified category
    move <#> <category> (mv): Moves the memo with ID <#> to the specified category
    delete (-d):              Deletes your most recent memo (returns it after deletion)
    delete <#>:               Deletes the memo with ID <#>

MEMO-RETRIEVING COMMANDS
    view (-v):                Shows your last five memos (grouped by category)
    view <#>:                 Shows the memo with ID <#>
    view <category>:          Shows all memos in the designated category
    view all (-va):           Shows all memos (Grouped by category, sorted newest to oldest)

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

(path/to/here)/mrndm.sh init
    - Do this if nothing else is working

Run `mrndm help (mrndm -h)` for full usage information.
USAGE
        exit 0
fi

# If the first arg isn't a known command, treat it as the memo body
if [[ -n $command ]]; then
    case $command in
        -i|init|-v|view|-va|-m|memo|-d|delete|-r|register|-h|help|-s|sync|login|-l|logout|-fp|password|-mv|mv|move|-ls|ls|viewamt|deleteaccount|changeemail|me|self|user)
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
        results_count=$(echo "$responsejson" | jq -r 'length')
        if [[ "$results_count" -eq 0 ]]; then
            echo "No memos submitted."
            exit 0
        fi
        echo "$responsejson" | jq -r '
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

retrieve_given_amount() {
    if [[ -n "$token" ]]; then
        responsejson=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/")
        results=$(echo "$responsejson" | jq -r '. // empty')
        if [[ "$results" ]]; then
                echo "$responsejson" | jq -r --arg amt "$option" '(.) as $all | if ($all | length) == 0 then "No memos submitted." else ($all | sort_by(-.id) | .[0:(($amt|tonumber))] | group_by(.category) | map("| --- " + .[0].category + " --- |\n" + (sort_by(-.id)|map(.body + " (" + (.id|tostring) + ")")|join("\n"))) | join("\n\n")) end'
            exit 0
        fi
        echo "error: $responsejson"
        exit 1
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    retrieve_given_amount
}

retrieve_memos_by_category() {
    catarg="$1"
    if [[ -z "$catarg" ]]; then
        catarg="$category"
    fi
    if [[ -n "$token" ]]; then
        responsejson=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/")
        results_count=$(echo "$responsejson" | jq -r 'length')
        if [[ "$results_count" -eq 0 ]]; then
            echo "No memos submitted."
            exit 0
        fi
        echo "$responsejson" | jq -r --arg cat "$catarg" 'map(select(.category==$cat)) |
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

logout() {
    if [[ -n "$token" ]]; then
        responsejson=$(curl --write-out "%{http_code}\n" --output /dev/null -s -X POST \
        -H "Authorization: Token $token" \
        -H "Content-Type:application/json" \
        -d "" $baseApiUrl/auth/logout/)
        if [[ "$responsejson" -ne 204 ]]; then
            echo "Logout failed. Server response code: $responsejson"
            exit 1
        fi
        echo "Logged out."
        printf "baseApiUrl=%s\n" "$baseApiUrl" > $config
        exit 0
    fi
    echo "No token in the config file."
    sleep 1
    echo "Options:"
    echo "    mrndm sync - you meant to login, not logout"
    echo "    mrndm register - you don't have an account yet"
    echo "    mrndm logout all - you want to logout of all sessions everywhere"
    exit 1
}

delete() {
    if [[ -n "$token" ]]; then
        # If no ID provided, find and delete the most recent memo
        if [[ -z "$option" ]]; then
            memo_to_delete=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/" | \
            jq -r '. | sort_by(-.id) | .[0]')
            
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
        memo_response=$(echo "$memo_to_delete" | jq -r '.body // empty')
        if [[ -z "$memo_response" ]]; then
            echo "Memo not found with ID $option"
            exit 1
        fi
        response=$(curl --write-out "%{http_code}\n" --output /dev/null -s -X DELETE \
        -H "Authorization: Token $token" \
        "$baseApiUrl/memos/$option/")
        if [[ "$response" -ne 204 ]]; then
            echo "Delete failed. Server response code: $response"
            exit 1
        fi
        echo "Deleted:"
        echo "$memo_to_delete" | jq -r '.body + " (" + (.id|tostring) + ")"'
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    delete
}

delete_account() {
    if [[ -n "$token" ]]; then
        read -p "Are you sure you want to delete your account? This action cannot be undone and all of your memos will be erased. (y/N) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Account deletion cancelled."
            exit 0
        fi
        responsejson=$(curl --write-out "%{http_code}\n" --output /dev/null -s -X DELETE \
        -H "Authorization: Token $token" \
        -H "Content-Type:application/json" \
        -d "" $baseApiUrl/users/me/)
        if [[ "$responsejson" -ne 204 ]]; then
            echo "Account deletion failed. Server response code: $responsejson"
            exit 1
        fi
        echo "Account deleted. Thanks for trying mrndm!"
        rm $config
        exit 0
    fi
    echo "No token in the config file."
    sleep 1
    echo "Options:"
    echo "    mrndm login - you need to login and retrieve a token before you can delete your account"
    echo "    mrndm logout all - you want to logout of all sessions everywhere (need to be logged in first)"
    exit 1
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
    if [[ -z $baseApiUrl ]]; then
        echo "Error retrieving configuration information. Have you run '(path/to/here)/mrndm.sh init' yet?"
        exit 1
    fi
    authbody=$(jq --null-input --arg user "$1" --arg pass "$2" '{username: $user, password: $pass}')
    tokenjson=$(curl -s -X POST -H "Content-Type:application/json" -d "$authbody" "$baseApiUrl/auth/login/")
    token=$(echo "$tokenjson" | jq -r '.token')
    if [[ -z "$token" || "$token" == "null" ]]; then
        echo "Authentication failed. Server response:"
        echo "$tokenjson"
        exit 1
    fi
    # Overwrite config with baseApiUrl and token
    expiry_time=$(date -d "+90 days" +"%Y-%m-%d %H:%M:%S")
    printf "baseApiUrl=%s\ntoken=%s\ntoken_expiry=\"%s\"\n" "$baseApiUrl" "$token" "$expiry_time" > $config
}

change_category() {
    if [[ -n "$token" ]]; then
        if [[ -z "$option" ]]; then
            echo "Please provide a memo ID to change its category."
            exit 1
        fi
        re='^[0-9]+$'
        if ! [[ "$option" =~ $re ]]; then
            echo "Invalid memo ID. Please provide a numeric ID."
            exit 1
        fi
        updatebody=$(jq --null-input --arg category "$category" '{category: $category}')
        responsejson=$(curl -s -X PATCH \
        -H "Authorization: Token $token" \
        -H "Content-Type:application/json" \
        -d "$updatebody" "$baseApiUrl/memos/$option/")
        responsecategory=$(echo "$responsejson" | jq -r '.category // empty')
        responsebody=$(echo "$responsejson" | jq -r '.body // empty')
        if [[ -z $responsebody ]]; then
            echo "Failed to update category. Server response:"
            echo "$responsejson"
            exit 1
        fi
        echo "Memo ID $option: '$responsebody' category updated to $responsecategory."
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    change_category
}

change_email() {
    if [[ -n "$token" ]]; then
        read -p "Enter the email address you wish to associate with your account: " newemail
        updatebody=$(jq --null-input --arg email "$newemail" '{email: $email}')
        responsejson=$(curl -s -X PATCH \
        -H "Authorization: Token $token" \
        -H "Content-Type:application/json" \
        -d "$updatebody" "$baseApiUrl/users/me/")
        responsemessage=$(echo "$responsejson" | jq -r '.message // empty')
        if [[ -z $responsemessage ]]; then
            echo "Failed to update email. Server response:"
            echo "$responsejson"
            exit 1
        fi
        echo "$responsemessage"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    change_email
}

view() {
    # No option -> show last five memos
    if [[ -z "$option" ]]; then
        option=5
        retrieve_given_amount
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
    read -p "Enter a username: " newuser
    read -s -p "Enter a password: " newpass
    echo ""
    # read -s newpass
    read -s -p "Re-enter your password: " newpass2
    # read -s newpass2
    echo ""
    read -p "Enter your email (optional, for password recovery): " newemail
    registerbody=$(jq --null-input \
    --arg user "$newuser" \
    --arg pass "$newpass" \
    --arg pass2 "$newpass2" \
    --arg email "$newemail" \
    '{username: $user, password: $pass, password2: $pass2, email: $email}')
    responsejson=$(curl -s -X POST -H "Content-Type:application/json" -d "$registerbody" "$baseApiUrl/auth/register/")
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
                    printf "baseApiUrl=http://127.0.0.1:8000/api/v1" > $config
                elif [[ "$devmode" == "user" ]]; then
                    echo "Initializing config with the default server URL. Run 'mrndm register' to register, or 'mrndm sync' if you already have an account."
                    printf "baseApiUrl=https://our.plots.club/api/v1" > $config
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

reset_password() {
    read -p "Password recovery - enter your email: " email
    resetbody=$(jq --null-input --arg email "$email" '{email: $email}')
    responsejson=$(curl -s -X POST -H "Content-Type:application/json" -d "$resetbody" "$baseApiUrl/auth/password-reset/")
    message=$(echo "$responsejson" | jq -r '.message // empty')
    if [[ "$message" ]]; then
        echo "$message"
        exit 0
    else
        message=$(echo "$responsejson" | jq -r '.error // empty')
    fi
    echo "$message"
    exit 0
}

get_user_info() {
    if [[ -n "$token" ]]; then
        responsejson=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/users/me/")
        message=$(echo "$responsejson" | jq -r '.message // empty')
        if [[ -n "$message" ]]; then
            echo "$message"
            exit 0
        fi
        echo "error: $responsejson"
        exit 1
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    get_user_info
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

    -s | sync | login)
        authenticate
        ;;

    -l | logout)
        logout
        ;;

    -i | init)
        init
        ;;

    -h | help)
        show_full_help
        exit 0
        ;;

    -fp | password)
        reset_password
        ;;

    -mv | mv | move)
        change_category
        ;;

    -ls | ls | viewamt)
        retrieve_given_amount
        ;;

    deleteaccount)
        delete_account
        ;;

    changeemail)
        change_email
        ;;

    me | self | user)
        get_user_info
        ;;

esac