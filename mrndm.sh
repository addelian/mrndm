#!/usr/bin/env bash

set -e

. ./mrndm.config

command=$1
option=$2
category="MISC"

if [[ -n "$3" ]]; then
    category=$3
fi


# If no arguments supplied, show a short usage summary and exit
# TODO pare this down, add --help flag & put all this there
if [[ -z "$command" ]]; then
        cat <<'USAGE'
Usage: mrndm [command] [options*]

(path/to/package/)mrndm.sh install
    - copies the script into a PATH directory so you can run `mrndm` directly. Otherwise, you'll have to run these all with `bash mrndm.sh` or `./mrndm.sh` from the package directory.

mrndm init (-i)
    - registers a username/password (first run)

mrndm "Your memo text"
    - saves a memo (category defaults to MISC)

mrndm "Buy milk" TODO
    - saves a memo under TODO, RMND, or MISC

mrndm view (-v)
    - shows your last five memos (grouped by category)

mrndm view <#>
    - shows the memo with ID <#>

mrndm view <category>
    - shows all memos in the specified category (TODO, RMND, MISC)

mrndm view all (-va)
    - shows all memos in all categories (grouped and ordered)

mrndm delete
    - deletes your most recent memo (returns it after deletion)

mrndm delete <#>
    - deletes memo with ID <#>

For full help, run: mrndm view --help
USAGE
        exit 0
fi

authbody=$(jq --null-input \
    --arg user "$username" \
    --arg pass "$password" \
    '{username: $user, password: $pass}')

# If the first arg isn't a known command, treat it as the memo body
if [[ -n $command ]]; then
    case $command in
        -i|init|-a|auth|-v|view|-va|-m|memo|-d|delete|install)
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
    authenticate
    retrieve_memos
}

retrieve_last_five() {
    if [[ -n "$token" ]]; then
        curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/" | \
        jq -r '.results | sort_by(-.id) | .[0:5] as $subset |
            $subset as $r | ["TODO","RMND","MISC"] as $order |
            $order | map( . as $cat | ($r | map(select(.category==$cat)) ) as $items |
            if ($items|length)>0 then 
                ("| --- " + $cat + " --- |\n" + 
                ($items|sort_by(-.id)|map(.body + " (" + (.id|tostring) + ")")|join("\n"))) 
            else empty end) | join("\n\n")'
        exit 0
    fi
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
        curl -X POST \
        -H "Authorization: Token $token" \
        -H "Content-Type:application/json" \
        -d "$postbody" $baseApiUrl/memos/
        exit 0
    fi
    authenticate
    submit
}

delete() {
    if [[ -n "$token" ]]; then
        curl -X DELETE \
        -H "Authorization: Token $token" \
        $baseApiUrl/memos/$option/
        exit 0
    fi
    authenticate
    submit
}

retrieve_memo() {
    if [[ -n "$token" ]]; then
        curl -s -H "Authorization: Token $token" "$baseApiUrl/memos/$1/" | \
        jq -r '"| --- " + .category + " --- |\n" + (.body + " (" + (.id|tostring) + ")")'
        exit 0
    fi
    authenticate
    retrieve_memo $1
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

checkauth() {
    if [[ -n "$token" ]]; then
        echo "'token' field already present in config."
        echo "If it's invalid, please remove that line before re-running this command."
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

    -a | auth)
        checkauth
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

    install)
        install_self
        ;;

esac