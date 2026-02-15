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

    -z | undo)
        undo
        ;;

    -s | sync | login | -li)
        authenticate
        ;;

    -lo | logout)
        logout
        ;;

    -la | logoutall)
        logout_all
        ;;

    -i | init)
        init
        ;;

    -h | help)
        show_full_help
        exit 0
        ;;

    -fp | forgotpassword)
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
        retrieve_user_info
        ;;

esac

# If the first arg isn't a known command, treat it as the memo body
if [[ -n $command ]]; then
    case $command in
        -i|init|-v|view|-va|-m|memo|-d|delete|-z|undo|-r|register|-h|help|-s|sync|login|-li|logout|-lo|-fp|forgotpassword|-mv|mv|move|-ls|ls|viewamt|deleteaccount|changeemail|me|self|user|logoutall|-la)
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

# |------------------------|
# |--- ACCOUNT COMMANDS ---|
# |------------------------|

show_full_help() {
        cat <<'FULL'
USAGE
    mrndm <command> <subcommand>

ACCOUNT COMMANDS
    init (-i):                Installs mrndm on your PATH and creates a config file. Run this before you do anything else
    register (-r):            Registers a username and password and uses them to retrieve a token
    sync (-s):                Generates a token for an existing user and saves it to the config file (Alias: login / -li)
    logout (-lo):             Deletes the token from the config file and logs out of the current session
    logoutall (-la):          Logs out of all sessions everywhere (including the current one) and stales all existing tokens
    forgotpassword (-fp):     Initiates the password reset process (sends an email with instructions)
    user (me):                Shows information about your account (username, email if present)
    changeemail:              Changes the email associated with your account (used for password recovery)
    deleteaccount:            Deletes your account and all associated memos. This is irreversible

MEMO-WRITING COMMANDS
    "Memo text":              Saves a memo (defaults to MISC)
    "Memo text" <category>:   Saves a memo under the specified category
    move <#> <category> (mv): Moves the memo with ID <#> to the specified category
    undo (-z):                Deletes your most recent memo (returns it after deletion)
    delete <#> (-d):          Deletes the memo with ID <#> (returns it after deletion)

MEMO-RETRIEVING COMMANDS
    view (-v):                Shows your last five memos (grouped by category, newest to oldest)
    view <#>:                 Shows the memo with ID <#>
    view <category>:          Shows all memos in the designated category
    viewamt <#> (-ls):        Shows the last <#> memos (grouped by category, newest to oldest)
    view all (-va):           Shows all memos (grouped by category, newest to oldest)

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

register() {
    if [[ -z $baseApiUrl ]]; then
        echo "Error retrieving configuration information. Have you run '(path/to/here)/mrndm.sh init' yet?"
        exit 1
    fi
    read -p "Enter a username: " newuser
    read -s -p "Enter a password: " newpass
    echo ""
    read -s -p "Re-enter your password: " newpass2
    echo ""
    read -p "Enter your email (optional, for password recovery): " newemail
    registerbody=$(printf '{"username":"%s","password":"%s","password2":"%s","email":"%s"}' \
    "$(printf '%s' "$newuser" | sed 's/"/\\"/g')" \
    "$(printf '%s' "$newpass" | sed 's/"/\\"/g')" \
    "$(printf '%s' "$newpass2" | sed 's/"/\\"/g')" \
    "$(printf '%s' "$newemail" | sed 's/"/\\"/g')")
    response=$(curl -s -X POST -H "Content-Type:application/json" -d "$registerbody" "$baseApiUrl/auth/register/")
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        if [[ "$response" == *"Error("* ]]; then
            echo "$response"
            exit 1
        fi
    printf "baseApiUrl=%s\n" "$baseApiUrl" > $config
    echo $response
    echo "Retrieving token..."
    retrieve_token "$newuser" "$newpass"
    sleep 1
    echo "Token retrieved successfully and config written to $config."
    sleep 1
    echo -e "You're all set up, ${GREEN}$newuser${NC}. Enjoy mrndm."
    exit 0
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
    authbody=$(printf '{"username":"%s","password":"%s"}' \
    "$(printf '%s' "$1" | sed 's/"/\\"/g')" \
    "$(printf '%s' "$2" | sed 's/"/\\"/g')")
    response=$(curl -s -X POST \
        -H "Content-Type:application/json" \
        -H "Accept: application/json" \
        -d "$authbody" "$baseApiUrl/auth/login/")
    token=$(printf '%s' "$response" \
    | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
    if [[ -z "$token" || "$token" == "null" ]]; then
        echo "Authentication failed. Server response:"
        echo "$response"
        exit 1
    fi
    # Overwrite config with baseApiUrl and token
    expiry_time=$(date -d "+90 days" +"%Y-%m-%d %H:%M:%S")
    printf "baseApiUrl=%s\ntoken=%s\ntoken_expiry=\"%s\"\n" "$baseApiUrl" "$token" "$expiry_time" > $config
}

retrieve_user_info() {
    if [[ -n "$token" ]]; then
        response=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/users/me/")
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    retrieve_user_info
}

change_email() {
    if [[ -n "$token" ]]; then
        read -p "Enter the email address you wish to associate with your account: " newemail
        updatebody=$(printf '{"email":"%s"}' \
            "$(printf '%s' "$newemail" | sed 's/"/\\"/g')")
        response=$(curl -s -X PATCH \
            -H "Authorization: Token $token" \
            -H "Content-Type:application/json" \
            -d "$updatebody" "$baseApiUrl/users/me/")
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    change_email
}

reset_password() {
    read -p "Password recovery - enter your email: " email
    resetbody=$(printf '{"email":"%s"}' \
        "$(printf '%s' "$email" | sed 's/"/\\"/g')")
    response=$(curl -s -X POST -H "Content-Type:application/json" -d "$resetbody" "$baseApiUrl/auth/password-reset/")
    echo "$response"
    exit 0
}

logout() {
    if [[ -n "$token" ]]; then
        response=$(curl --write-out "%{http_code}\n" --output /dev/null -s -X POST \
            -H "Authorization: Token $token" \
            -H "Content-Type:application/json" \
            -d "" $baseApiUrl/auth/logout/)
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        if [[ "$response" -ne 204 ]]; then
            echo "Logout failed. Server response code: $response"
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

logout_all() {
    if [[ -n "$token" ]]; then
        response=$(curl -s -X POST \
            --write-out "%{http_code}\n" --output /dev/null \
            -H "Authorization: Token $token" \
            -H "Content-Type:application/json" \
            -d "" $baseApiUrl/auth/logout-all/)
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        if [[ "$response" -ne 204 ]]; then
            echo "Logout failed. Server response code: $response"
            exit 1
        fi
        echo "Logged out of all sessions."
        printf "baseApiUrl=%s\n" "$baseApiUrl" > $config
        exit 0
    fi
    echo "Token not present in config file. You need to be logged in before you can logout of all other sessions (including this one)."
    sleep 1
    authenticate
    logout_all
}

delete_account() {
    if [[ -n "$token" ]]; then
        read -p "Are you sure you want to delete your account? This action cannot be undone and all of your memos will be erased. (y/N) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Account deletion cancelled."
            exit 0
        fi
        response=$(curl -s -X DELETE \
            -H "Authorization: Token $token" \
            -H "Accept: text/plain" \
            -H "Content-Type:application/json" \
            -d "" $baseApiUrl/users/me/)
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
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

# |-----------------------------|
# |--- MEMO-WRITING COMMANDS ---|
# |-----------------------------|

submit() {
    if [[ -n "$token" ]]; then
        postbody=$(printf '{"body":"%s","category":"%s"}' \
        "$(printf '%s' "$option" | sed 's/"/\\"/g')" \
        "$(printf '%s' "$category" | sed 's/"/\\"/g')")
        response=$(curl -s -X POST \
            -H "Authorization: Token $token" \
            -H "Content-Type:application/json" \
            -d "$postbody" $baseApiUrl/memos/)
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    submit
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
        updatebody=$(printf '{"category":"%s"}' \
        "$(printf '%s' "$category" | sed 's/"/\\"/g')")
        response=$(curl -s -X PATCH \
            -H "Authorization: Token $token" \
            -H "Content-Type:application/json" \
            -d "$updatebody" "$baseApiUrl/memos/$option/")
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    change_category
}

undo() {
    if [[ -n "$token" ]]; then
        memo_to_delete=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/?latest=true")
        if [[ -z "$memo_to_delete" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        curl -s -X DELETE -H "Authorization: Token $token" "$baseApiUrl/memos/undo/"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    submit
}

delete() {
    if [[ -n "$token" ]]; then
        # If no ID provided, deletes the most recent memo (undo)
        if [[ -z "$option" ]]; then
            undo
        fi
        
        # If ID provided, fetch the memo first, then delete it
        memo_to_delete=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/$option/")
        if [[ -z "$memo_to_delete" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
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
        echo "$memo_to_delete"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    delete
}

# |--------------------------------|
# |--- MEMO-RETRIEVING COMMANDS ---|
# |--------------------------------|

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

retrieve_memo() {
    if [[ -n "$token" ]]; then
        response=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/$1/")
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    retrieve_memo $1
}

retrieve_memos() {
    if [[ -n "$token" ]]; then
        response=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/")
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    retrieve_memos
}

retrieve_given_amount() {
    if [[ -n "$token" ]]; then
        response=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/?limit=$option")
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
        exit 0
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
        response=$(curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/?category=$catarg")
        if [[ -z "$response" ]]; then
            echo "Error: No response from the server. Did you run 'mrndm.sh init'?"
            exit 1
        fi
        echo "$response"
        exit 0
    fi
    echo "Token not present in config file."
    sleep 1
    authenticate
    retrieve_memos_by_category "$catarg"
}
