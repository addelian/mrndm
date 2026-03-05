#!/usr/bin/env bash

set -euo pipefail

SCRIPT="${1:-./mrndm.sh}"

if [[ ! -f "$SCRIPT" ]]; then
  echo "Usage: $0 ./mrndm.sh"
  exit 1
fi

TEST_DIR="$(mktemp -d)"
MOCK_BIN="$TEST_DIR/bin"
MOCK_HOME="$TEST_DIR/home"
CONFIG_DIR="$MOCK_HOME/.config"
CONFIG_FILE="$CONFIG_DIR/mrndm.conf"

mkdir -p "$MOCK_BIN" "$CONFIG_DIR"

PATH="$MOCK_BIN:$PATH"
HOME="$MOCK_HOME"

PASS=0
FAIL=0

############################################
# Fake curl implementation
############################################

cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash

echo "$@" >> "$TEST_TMP/curl.log"

case "$MOCK_CURL_MODE" in

login_success)
  printf '{"token":"abc123"}\n200'
  ;;

register_success)
  printf '{"username":"tester"}\n200'
  ;;

create_memo)
  printf '{"id":1,"body":"memo"}\n201'
  ;;

get_memos)
  printf '[{"id":1},{"id":2}]\n200'
  ;;

get_single)
  printf '{"id":5,"body":"hello"}\n200'
  ;;

latest_memo)
  printf '{"id":9,"body":"latest"}\n200'
  ;;

delete_ok)
  printf '\n204'
  ;;

error_500)
  printf '{"error":"server"}\n500'
  ;;

network_error)
  exit 7
  ;;

*)
  printf '{}\n200'
  ;;

esac
EOF

chmod +x "$MOCK_BIN/curl"

export TEST_TMP="$TEST_DIR"

############################################
# Helpers
############################################

pass() {
  echo "PASS: $1"
  ((++PASS))
}

fail() {
  echo "FAIL: $1"
  ((++FAIL))
}

run() {
  set +e
  output=$("$@" 2>&1)
  code=$?
  set -e
}

write_config() {
cat > "$CONFIG_FILE" <<EOF
baseApiUrl=http://api.test
token=testtoken
token_expiry="2099-01-01 00:00:00"
EOF
}

reset_logs() {
  : > "$TEST_TMP/curl.log"
}

############################################
# TESTS
############################################

test_usage() {
  run bash "$SCRIPT"

  if [[ "$output" == *"Usage:"* ]]; then
    pass "usage shown"
  else
    fail "usage not shown"
  fi
}

test_submit_memo() {

  write_config
  reset_logs

  export MOCK_CURL_MODE=create_memo

  run bash "$SCRIPT" "hello world"

  if grep -q "/memos/" "$TEST_TMP/curl.log"; then
    pass "submit memo endpoint"
  else
    fail "submit memo endpoint"
  fi
}

test_invalid_category() {

  write_config
  reset_logs

  run bash "$SCRIPT" "memo text" BADCAT

  if [[ "$output" == *"Invalid category"* ]]; then
    pass "invalid category rejected"
  else
    fail "invalid category rejected"
  fi
}

test_view_default() {

  write_config
  reset_logs
  export MOCK_CURL_MODE=get_memos

  run bash "$SCRIPT" view

  if grep -q "limit=5" "$TEST_TMP/curl.log"; then
    pass "view default limit"
  else
    fail "view default limit"
  fi
}

test_view_specific_id() {

  write_config
  reset_logs
  export MOCK_CURL_MODE=get_single

  run bash "$SCRIPT" view 5

  if grep -q "/memos/5/" "$TEST_TMP/curl.log"; then
    pass "view memo by id"
  else
    fail "view memo by id"
  fi
}

test_view_category() {

  write_config
  reset_logs
  export MOCK_CURL_MODE=get_memos

  run bash "$SCRIPT" view TODO

  if grep -q "category=TODO" "$TEST_TMP/curl.log"; then
    pass "view category"
  else
    fail "view category"
  fi
}

test_delete_specific() {

  write_config
  reset_logs
  export MOCK_CURL_MODE=get_single

  run bash "$SCRIPT" delete 5

  if grep -q "/memos/5/" "$TEST_TMP/curl.log"; then
    pass "delete memo fetch"
  else
    fail "delete memo fetch"
  fi
}

test_undo() {

  write_config
  reset_logs
  export MOCK_CURL_MODE=latest_memo

  run bash "$SCRIPT" undo

  if grep -q "latest=true" "$TEST_TMP/curl.log"; then
    pass "undo fetch latest"
  else
    fail "undo fetch latest"
  fi
}

test_http_error() {

  write_config
  export MOCK_CURL_MODE=error_500

  run bash "$SCRIPT" view

  if [[ $code -ne 0 ]]; then
    pass "http error handled"
  else
    fail "http error handled"
  fi
}

test_network_error() {

  write_config
  export MOCK_CURL_MODE=network_error

  run bash "$SCRIPT" view

  if [[ "$output" == *"Network error"* ]]; then
    pass "network error handled"
  else
    fail "network error handled"
  fi
}

############################################
# Run all tests
############################################

test_usage
test_submit_memo
test_invalid_category
test_view_default
test_view_specific_id
test_view_category
test_delete_specific
test_undo
test_http_error
test_network_error

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ $FAIL -ne 0 ]]; then
  exit 1
fi

echo "All tests passed"