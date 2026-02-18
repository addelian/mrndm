#!/usr/bin/env bash
#
# mrndm - a CLI-first brain dump / jotter analog

# |---------------------------------|
# |--- CONFIG / SETUP MISCELLANY ---|
# |---------------------------------|

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CATEGORIES=(MISC RMND TODO IDEA WORK TECH HOME QUOT EARS EYES FOOD DRNK)

DEFAULT_VIEW_LIMIT=5

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

# if no arguments supplied, show a quick usage summary and exit
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

# if the first arg isn't a known command, treat it as the memo body
if [[ -n $command ]]; then
  case $command in
    -i|init|-v|view|-va|-m|memo|-d|delete|-z|undo|-r|register|-h|help|-s|sync|login|-li|logout|-lo|-fp|forgotpassword|-mv|mv|move|-ls|ls|viewamt|deleteaccount|changeemail|me|self|user|logoutall|-la|linkphone)
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
# |--- HELPER FUNCTIONS ---|
# |------------------------|

require_token() {
  if [[ -z "$token" ]]; then
    echo "Token not present in config file."
    sleep 1
    authenticate
  fi
}

require_config() {
  if [[ -z "$baseApiUrl" ]]; then
    echo "Error retrieving configuration information. Have you run '(path/to/here)/mrndm.sh init' yet?"
    exit 1
  fi
}

write_base_config() {
  printf "baseApiUrl=%s\n" "$baseApiUrl" > "$config"
}

json_escape() {
  printf '%s' "$1" | sed 's/"/\\"/g'
}

api_request() {
  method="$1"
  data="$2"
  endpoint="$3"
  shift 3

  headers=(-s -S -X "$method")

  if [[ -n "$data" ]]; then
    headers+=(-H "Content-Type:application/json" -d "$data")
  fi

  if [[ -n "$token" ]]; then
    headers+=(-H "Authorization: Token $token")
  fi

  for h in "$@"; do
    headers+=(-H "$h")
  done

  response=$(curl "${headers[@]}" -w "\n%{http_code}" "$baseApiUrl$endpoint")
  curl_exit=$?

    if [[ $curl_exit -ne 0 ]]; then
    echo "Network error: curl exited with code $curl_exit" >&2
    return $curl_exit
  fi

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ $http_code -ge 400 ]]; then
    echo "$body" >&2
    return 1
  fi

  echo "$body"
}

api_request_expect_nocontent() {
  method="$1"
  endpoint="$2"

  headers=(-s -S -X "$method")
  if [[ -n "$token" ]]; then
    headers+=(-H "Authorization: Token $token")
  fi
  headers+=(-H "Content-Type:application/json")

  response=$(curl "${headers[@]}" -w "\n%{http_code}" -o /dev/stdout "$baseApiUrl$endpoint")
  curl_exit=$?

  if [[ $curl_exit -ne 0 ]]; then
    echo "Network error: curl exited with code $curl_exit" >&2
    return $curl_exit
  fi

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_code" -ne 204 ]]; then
    echo "$body" >&2
    return 1
  fi

  return 0
}

is_valid_category() {
  for cat in "${CATEGORIES[@]}"; do
    [[ "$1" == "$cat" ]] && return 0
  done
  return 1
}

get_memos() {
  require_token
  if ! response=$(api_request GET "" "$1"); then
    exit 1
  fi
  echo "$response"
}

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
  read -r -p "Choose where you want to install mrndm [default: $HOME/.local/bin]: " installdir
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
        read -r -p "Are you running mrndm in dev mode or user mode? (dev/user) [default: user]: " devmode
        devmode=${devmode:-"user"}
        if [[ "$devmode" == "dev" ]]; then
          echo "Initializing config with a local URL. Run 'mrndm register' to register, or 'mrndm sync' if you already have an account."
          printf "baseApiUrl=http://127.0.0.1:8000/api/v1" > "$config"
        elif [[ "$devmode" == "user" ]]; then
          echo "Initializing config with the default server URL. Run 'mrndm register' to register, or 'mrndm sync' if you already have an account."
          printf "baseApiUrl=https://mrndm.sh/api/v1" > "$config"
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
  require_config
  read -r -p "Enter a username: " newuser
  read -r -s -p "Enter a password: " newpass
  echo ""
  read -r -s -p "Re-enter your password: " newpass2
  echo ""
  read -r -p "Enter your email (optional, for password recovery): " newemail
  registerbody=$(printf '{"username":"%s","password":"%s","password2":"%s","email":"%s"}' \
    "$(json_escape "$newuser")" \
    "$(json_escape "$newpass")" \
    "$(json_escape "$newpass2")" \
    "$(json_escape "$newemail")")
  if ! response=$(api_request POST "$registerbody" "/auth/register/"); then
    echo "Registration request failed."
    exit 1
  fi
  if [[ "$response" == *"Error("* ]]; then
    echo "$response"
    exit 1
  fi
  write_base_config
  echo "$response"
  echo "Retrieving token..."
  get_token "$newuser" "$newpass"
  sleep 1
  echo "Token retrieved successfully and config written to $config."
  sleep 1
  echo -e "You're all set up, ${GREEN}$newuser${NC}. Enjoy mrndm."
  exit 0
}

authenticate() {
  read -r -p "Enter your username: " user
  read -r -s -p "Enter your password: " pass
  echo ""
  echo "Attempting to authenticate..."
  get_token "$user" "$pass"
  echo -e "User ${GREEN}$user${NC} synced back up with the mrndm server."
  sleep 1
  echo "Config written to $config."
  sleep 1
  echo "Welcome back!"
  exit 0
}

get_token() {
  require_config
  authbody=$(printf '{"username":"%s","password":"%s"}' \
  "$(json_escape "$1")" \
  "$(json_escape "$2")")
  if ! response=$(api_request POST "$authbody" "/auth/login/" "Accept: application/json"); then
    echo "Authentication request failed."
    exit 1
  fi
  token=$(printf '%s' "$response" \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  if [[ -z "$token" || "$token" == "null" ]]; then
    echo "Authentication failed. Server response:"
    echo "$response"
    exit 1
  fi
  if date --version >/dev/null 2>&1; then
    # Linux
    expiry_time=$(date -d "+90 days" +"%Y-%m-%d %H:%M:%S")
  else
    # macOS
    expiry_time=$(date -v +90d +"%Y-%m-%d %H:%M:%S")
  fi
  printf "baseApiUrl=%s\ntoken=%s\ntoken_expiry=\"%s\"\n" "$baseApiUrl" "$token" "$expiry_time" > "$config"
}

get_user_info() {
  require_token
  if ! response=$(api_request GET "" "/users/me/"); then
    exit 1
  fi
  echo "$response"
  exit 0
}

change_email() {
  require_token
  read -r -p "Enter the email address you wish to associate with your account: " newemail
  updatebody=$(printf '{"email":"%s"}' \
    "$(json_escape "$newemail")")
  if ! response=$(api_request PATCH "$updatebody" "/users/me/"); then
    exit 1
  fi
  echo "$response"
  exit 0
}

reset_password() {
  read -r -p "Password recovery - enter your email: " email
  resetbody=$(printf '{"email":"%s"}' \
    "$(json_escape "$email")")
  if ! response=$(api_request POST "$resetbody" "/auth/password-reset/"); then
    exit 1
  fi
  echo "$response"
  exit 0
}

logout() {
  require_token
  api_request_expect_nocontent POST "/auth/logout/"
  echo "Logged out."
  write_base_config
  exit 0
}

logout_all() {
  require_token
  api_request_expect_nocontent POST "/auth/logout-all/"
  echo "Logged out of all sessions."
  write_base_config
  exit 0
}

delete_account() {
  require_token
  read -r -p "Are you sure you want to delete your account? This action cannot be undone and all of your memos will be erased. (y/N) " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Account deletion cancelled."
    exit 0
  fi
  if ! response=$(api_request DELETE "" "/users/me/" "Accept: text/plain"); then
    exit 1
  fi
  echo "$response"
  rm -f "$config"
  exit 0
}

linkphone() {
  read -r -p "By linking your phone number, you can send and receive memos as text messages. This is optional and you can opt-out at any time. Do you want to link your phone number now? (y/N) " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Phone number linking cancelled."
    exit 0
  fi
  read -r -p "Enter your phone number (with country code, e.g. +1234567890): " phone
  echo "Text AUTH 7F92KD to +1 586-276-7636 to complete the linking process. This is a one-time code and will expire in 10 minutes."
}

# |-----------------------------|
# |--- MEMO-WRITING COMMANDS ---|
# |-----------------------------|

submit() {
  require_token
  if ! is_valid_category "$category"; then
    echo "Invalid category."
    exit 1
  fi
  postbody=$(printf '{"body":"%s","category":"%s"}' \
  "$(json_escape "$option")" \
  "$(json_escape "$category")")
  if ! response=$(api_request POST "$postbody" "/memos/"); then
    exit 1
  fi
  echo "$response"
  exit 0
}

change_category() {
  require_token
  if [[ -z "$option" ]]; then
    echo "Please provide a memo ID to change its category."
    exit 1
  fi
  if ! [[ "$option" =~ ^[0-9]+$ ]]; then
    echo "Invalid memo ID. Please provide a numeric ID."
    exit 1
  fi
  updatebody=$(printf '{"category":"%s"}' \
  "$(json_escape "$category")")
  if ! response=$(api_request PATCH "$updatebody" "/memos/$option/"); then
    exit 1
  fi
  echo "$response"
  exit 0
}

undo() {
  require_token
  if ! memo_to_delete=$(api_request GET "" "/memos/?latest=true"); then
    exit 1
  fi
  api_request_expect_nocontent DELETE "/memos/undo/"
  echo "Deleted:"
  echo "$memo_to_delete"
  exit 0
}

delete() {
  require_token
  # if no ID provided, undo instead
  if [[ -z "$option" ]]; then
    undo
  fi
  
  # fetch memo for easy return before deletion
  if ! memo_to_delete=$(api_request GET "" "/memos/$option/"); then
    exit 1
  fi
  api_request_expect_nocontent DELETE "/memos/$option/"
  echo "Deleted:"
  echo "$memo_to_delete"
  exit 0
}

# |--------------------------------|
# |--- MEMO-RETRIEVING COMMANDS ---|
# |--------------------------------|

handle_view() {
  # no option -> ls 5 (by default)
  if [[ -z "$option" ]]; then
    get_memos "/memos/?limit=$DEFAULT_VIEW_LIMIT"
    return
  fi

  if [[ $command = "-ls" || $command = "ls" || $command = "viewamt" ]]; then
    get_memos "/memos/?limit=$option"
    return
  fi

  if [[ $option =~ ^[0-9]+$ ]]; then
    get_memos "/memos/$option/"
    return
  fi

  if is_valid_category "$option"; then
    get_memos "/memos/?category=$option"
    return
  fi

  if [[ $option = "all" || $option = "-va" || $option = "--all" || $option = "-a" ]]; then
    get_memos "/memos/"
    return
  fi

  echo "USAGE:"
  echo "view (-v): show your last five memos"
  echo "view <#>: return a single memo with the provided ID number"
  echo "view all (-va): view all written memos"
  echo "view <category>: view memos in the designated category"
  exit 0
}

case $command in

  -h | help)
    show_full_help
    ;;

  -i | init)
    init
    ;;

  -r | register) 
    register
    ;;

  -s | sync | login | -li)
    authenticate
    ;;

  me | self | user | -u)
    get_user_info
    ;;

  changeemail)
    change_email
    ;;

  -fp | forgotpassword)
    reset_password
    ;;

  -lo | logout)
    logout
    ;;

  -la | logoutall)
    logout_all
    ;;

  deleteaccount)
    delete_account
    ;;

  -m | memo)
    submit
    ;;

  -mv | mv | move)
    change_category
    ;;

  -z | undo)
    undo
    ;;

  -d | delete)
    delete
    ;;

  -v | view | -va | viewamt | -ls | ls | --all | -a)
    handle_view
    ;;

  linkphone)
    linkphone
    ;;

esac