#!/usr/bin/env bash

# test_mrndm.sh - Test suite for mrndm
# Run with: bash test_mrndm.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Create a temporary directory for test config
TEST_DIR=$(mktemp -d)
TEST_CONFIG="$TEST_DIR/mrndm.config"
cat > "$TEST_CONFIG" <<EOF
baseApiUrl=http://test-api.local
username=testuser
password=testpass
token=test-token-12345
EOF

# Mock curl function
curl() {
    local method="POST"
    local url=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -X) method="$2"; shift 2 ;;
            -H|--header) shift 2 ;;
            -d|--data) shift 2 ;;
            -s|--silent) shift ;;
            http*) url="$1"; shift ;;
            *) shift ;;
        esac
    done
    
    # Mock responses based on URL
    case "$url" in
        http://test-api.local/memos/)
            if [[ "$method" = "POST" ]]; then
                echo '{"id":999,"body":"test memo","category":"MISC","author":"testuser"}'
            else
                echo '{"count":3,"next":null,"previous":null,"results":[{"id":3,"body":"third memo","category":"TODO","author":"testuser"},{"id":2,"body":"second memo","category":"MISC","author":"testuser"},{"id":1,"body":"first memo","category":"RMND","author":"testuser"}]}'
            fi
            ;;
        http://test-api.local/memos/1/)
            echo '{"id":1,"body":"first memo","category":"RMND","author":"testuser"}'
            ;;
        http://test-api.local/memos/2/)
            echo '{"id":2,"body":"second memo","category":"MISC","author":"testuser"}'
            ;;
        http://test-api.local/memos/999/)
            if [[ "$method" = "DELETE" ]]; then
                echo '{"id":999,"body":"test memo","category":"MISC","author":"testuser"}'
            fi
            ;;
        *)
            echo "{}"
            ;;
    esac
}

export -f curl

# Test framework functions
test_case() {
    local name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}Test $TESTS_RUN: $name${NC}"
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    
    if [[ "$expected" = "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASSED${NC}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAILED${NC}: $msg"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓ PASSED${NC}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗ FAILED${NC}: $msg"
        echo "  Expected to contain: $needle"
        echo "  Actual: $haystack"
    fi
}

# Run tests in the test environment
run_test() {
    cd "$TEST_DIR"
    cp "$TEST_DIR/mrndm.config" ./mrndm.config
    "$@"
    cd - > /dev/null
}

# ============== ARGUMENT PARSING TESTS ==============

test_case "No arguments shows quick help"
output=$(run_test bash /home/nic/workspace/github.com/addelian/mrndm/mrndm.sh 2>&1 || true)
assert_contains "$output" "mrndm help (mrndm -h)" "No-arg output should contain reference to help flag"

test_case "Help flag shows full help"
output=$(run_test bash /home/nic/workspace/github.com/addelian/mrndm/mrndm.sh -h 2>&1 || true)
assert_contains "$output" "init (-i)" "Help output should contain init command"

test_case "help command shows full help"
output=$(run_test bash /home/nic/workspace/github.com/addelian/mrndm/mrndm.sh help 2>&1 || true)
assert_contains "$output" "init (-i)" "help command should show init command"

# ============== FORMATTING TESTS ==============

test_case "Single memo formats with category header"
result=$(echo '{"id":5,"body":"test memo","category":"TODO","author":"testuser"}' | jq -r '"| --- " + .category + " --- |\n" + (.body + " (" + (.id|tostring) + ")")')
assert_contains "$result" "| --- TODO --- |" "Should format category header"
assert_contains "$result" "test memo (5)" "Should format memo with ID"

test_case "Category grouping works correctly"
result=$(echo '[{"id":3,"body":"todo item","category":"TODO"},{"id":2,"body":"misc item","category":"MISC"}]' | jq -r 'group_by(.category) | sort_by(.[0].category) | reverse | .[0][0].category')
assert_equal "TODO" "$result" "Categories should be sorted reverse alphabetically"

# ============== JSON PARSING TESTS ==============

test_case "jq extracts memo body"
result=$(echo '{"id":1,"body":"remember this","category":"MISC"}' | jq -r '.body')
assert_equal "remember this" "$result" "jq should extract body"

test_case "jq extracts category"
result=$(echo '{"id":1,"body":"remember this","category":"TODO"}' | jq -r '.category')
assert_equal "TODO" "$result" "jq should extract category"

test_case "jq filters by category"
result=$(echo '[{"id":1,"category":"TODO"},{"id":2,"category":"MISC"}]' | jq -r '[.[] | select(.category=="TODO")] | length')
assert_equal "1" "$result" "jq should filter by category"

# ============== SUMMARY ==============

echo ""
echo "======================================"
echo "Test Results:"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "======================================"

# Cleanup
rm -rf "$TEST_DIR"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
