#!/bin/bash

# Conservative Test Script for Crypto Data Azure Function
# This version is designed to work within CoinGecko's rate limits
# and properly test the enhanced functionality

BASE_URL="${1:-http://localhost:7071/api/CryptoDataFunction}"
PASSED=0
FAILED=0

# Enhanced argument parsing
DEBUG_MODE=false
QUICK_MODE=false
EXTENDED_MODE=false

for arg in "$@"; do
    case $arg in
        --debug)
            DEBUG_MODE=true
            ;;
        --quick)
            QUICK_MODE=true
            ;;
        --extended)
            EXTENDED_MODE=true
            ;;
    esac
done

# Set conservative delays to respect rate limits
if [ "$QUICK_MODE" = true ]; then
    DELAY=5
    echo "Quick mode: Using 5-second delays (minimum recommended)"
else
    DELAY=15
    echo "Conservative mode: Using 15-second delays to avoid rate limits"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "==========================================="
echo "Crypto Function Test Suite"
echo "Target: $BASE_URL"
echo "Mode: $(if [ "$QUICK_MODE" = true ]; then echo "Quick"; elif [ "$EXTENDED_MODE" = true ]; then echo "Extended"; else echo "Conservative"; fi)"
echo "Debug: $(if [ "$DEBUG_MODE" = true ]; then echo "ENABLED"; else echo "DISABLED"; fi)"
echo "==========================================="

# Enhanced test function with better analysis
test_endpoint() {
    local url="$1"
    local description="$2"
    local expected_status="${3:-200}"

    echo ""
    echo -e "${BLUE}Testing: $description${NC}"
    echo -n "Request: "

    if [ "$DEBUG_MODE" = true ]; then
        echo ""
        echo "  URL: $url"
        echo "  Expected Status: $expected_status"
    fi

    # Make request with comprehensive error handling
    local response
    local http_code
    local time_total

    response=$(curl -s -w "%{http_code}|%{time_total}|%{size_download}" \
                   --max-time 45 \
                   --retry 0 \
                   "$url" 2>/dev/null)

    # Parse response components
    local curl_exit_code=$?
    if [ $curl_exit_code -ne 0 ]; then
        echo -e "${RED}CURL ERROR${NC} (exit code: $curl_exit_code)"
        ((FAILED++))
        return
    fi

    # Extract metrics
    time_total="${response##*|}"
    temp="${response%|*}"
    size_download="${temp##*|}"
    temp="${temp%|*}"
    http_code="${temp: -3}"
    response_body="${temp%???}"

    # Display request result
    echo -e "${GREEN}HTTP $http_code${NC} (${time_total}s, ${size_download} bytes)"

    if [ "$DEBUG_MODE" = true ]; then
        echo "  Response preview: ${response_body:0:100}..."
    fi

    # Evaluate response
    local test_passed=false

    if [[ "$http_code" == "$expected_status" ]]; then
        if [[ "$expected_status" == "200" ]]; then
            # Check for successful response structure
            if command -v jq >/dev/null 2>&1; then
                if echo "$response_body" | jq . >/dev/null 2>&1; then
                    local success_flag=$(echo "$response_body" | jq -r '.success // false')
                    if [[ "$success_flag" == "true" ]]; then
                        test_passed=true
                        echo -e "Result: ${GREEN}PASS${NC}"
                        ((PASSED++))

                        # Enhanced data analysis
                        analyze_response_data "$response_body"
                    else
                        echo -e "Result: ${RED}FAIL${NC} (success=false)"
                        ((FAILED++))
                        show_error_details "$response_body"
                    fi
                else
                    echo -e "Result: ${RED}FAIL${NC} (invalid JSON)"
                    ((FAILED++))
                fi
            else
                # No jq available, basic check
                if echo "$response_body" | grep -q '"success".*true'; then
                    test_passed=true
                    echo -e "Result: ${GREEN}PASS${NC}"
                    ((PASSED++))
                else
                    echo -e "Result: ${RED}FAIL${NC}"
                    ((FAILED++))
                fi
            fi
        else
            # Non-200 expected status
            test_passed=true
            echo -e "Result: ${GREEN}PASS${NC} (correctly returned $expected_status)"
            ((PASSED++))
        fi
    else
        echo -e "Result: ${RED}FAIL${NC} (expected $expected_status, got $http_code)"
        ((FAILED++))

        # Special handling for common issues
        if [[ "$http_code" == "429" ]]; then
            echo -e "  ${YELLOW}WARNING: Rate limited - this is expected with frequent testing${NC}"
        elif [[ "$http_code" == "500" ]]; then
            echo -e "  ${YELLOW}WARNING: Server error - may be temporary${NC}"
        fi
    fi

    # Add delay between tests to respect rate limits
    if [ "$test_passed" = true ] && [ "$expected_status" == "200" ]; then
        echo "Waiting ${DELAY}s to respect rate limits..."
        sleep $DELAY
    else
        sleep 2  # Short delay for failed requests
    fi
}

# Function to analyze successful response data
analyze_response_data() {
    local response_body="$1"

    if ! command -v jq >/dev/null 2>&1; then
        return
    fi

    # Check if it's single coin or top coins
    local coin_name=$(echo "$response_body" | jq -r '.data.name // empty')
    local coin_count=$(echo "$response_body" | jq -r '.data.total_results // empty')

    if [[ -n "$coin_name" ]]; then
        # Single coin response
        local symbol=$(echo "$response_body" | jq -r '.data.symbol // ""')
        local price=$(echo "$response_body" | jq -r '.data.current_price // 0')
        local rank=$(echo "$response_body" | jq -r '.data.market_cap_rank // 0')
        local currency_upper=$(echo "$response_body" | jq -r '.request_info.currency // "USD"' | tr '[:lower:]' '[:upper:]')

        echo "  Coin: $coin_name ($symbol)"
        echo "  Price: $price $currency_upper"
        echo "  Rank: #$rank"

        if [[ "$price" == "0" ]]; then
            echo -e "  ${YELLOW}WARNING: Price is 0 - may indicate data extraction issue${NC}"
        fi
    elif [[ -n "$coin_count" ]]; then
        # Top coins response
        local currency=$(echo "$response_body" | jq -r '.data.currency // "USD"')
        echo "  Coins: $coin_count results in $currency"

        # Show top 3 coins if available
        local top_coins=$(echo "$response_body" | jq -r '.data.results[0:3][] | "  " + (.market_cap_rank | tostring) + ". " + .name + " (" + .symbol + "): " + (.current_price | tostring)' 2>/dev/null)
        if [[ -n "$top_coins" ]]; then
            echo "$top_coins"
        fi
    fi
}

# Function to show error details
show_error_details() {
    local response_body="$1"

    if ! command -v jq >/dev/null 2>&1; then
        echo "  Error details: $response_body"
        return
    fi

    local error_msg=$(echo "$response_body" | jq -r '.error // "Unknown error"')
    local error_type=$(echo "$response_body" | jq -r '.debug_info.error_type // ""')

    echo -e "  ${RED}Error: $error_msg${NC}"
    if [[ -n "$error_type" ]]; then
        echo "  Type: $error_type"
    fi
}

# Pre-flight checks
echo ""
echo -e "${PURPLE}=== Pre-flight Checks ===${NC}"

echo -n "Function endpoint connectivity: "
if curl -s --connect-timeout 10 --max-time 15 "$BASE_URL" >/dev/null 2>&1; then
    echo -e "${GREEN}Reachable${NC}"
else
    echo -e "${RED}Failed${NC}"
    echo "Cannot reach function endpoint. Ensure 'func start' is running."
    exit 1
fi

echo -n "CoinGecko API availability: "
ping_response=$(curl -s --max-time 10 "https://api.coingecko.com/api/v3/ping" 2>/dev/null)
if echo "$ping_response" | grep -q "gecko_says"; then
    gecko_msg=$(echo "$ping_response" | grep -o '"gecko_says":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}Available${NC} (${gecko_msg})"
else
    echo -e "${YELLOW}Limited or rate limited${NC}"
fi

echo ""

# Core functionality tests
echo -e "${PURPLE}=== Core Functionality Tests ===${NC}"

# Test 1: Top coins (most reliable, least likely to hit rate limits)
test_endpoint "$BASE_URL?action=top&limit=3&currency=usd" "Top 3 cryptocurrencies in USD"

# Test 2: Bitcoin (most important single coin)
test_endpoint "$BASE_URL?action=coin&coin=bitcoin&currency=usd" "Bitcoin price data"

# Test 3: Different currency
test_endpoint "$BASE_URL?action=top&limit=2&currency=eur" "Top 2 coins in EUR"

# Input validation tests (these don't hit external APIs)
echo ""
echo -e "${PURPLE}=== Input Validation Tests ===${NC}"

test_endpoint "$BASE_URL?action=invalid" "Invalid action parameter" "400"
test_endpoint "$BASE_URL?action=coin" "Missing coin parameter" "400"
test_endpoint "$BASE_URL?action=top&limit=999" "Invalid limit parameter" "400"

# Extended tests (only if requested)
if [ "$EXTENDED_MODE" = true ]; then
    echo ""
    echo -e "${PURPLE}=== Extended Tests ===${NC}"

    test_endpoint "$BASE_URL?action=coin&coin=ethereum&currency=usd" "Ethereum price data"
    test_endpoint "$BASE_URL?action=coin&coin=bitcoin&currency=gbp" "Bitcoin in GBP"
    test_endpoint "$BASE_URL?action=top&limit=5&currency=jpy" "Top 5 coins in JPY"

    # Test edge cases
    test_endpoint "$BASE_URL?action=coin&coin=nonexistent-coin-12345" "Non-existent coin" "404"
fi

# Performance test
echo ""
echo -e "${PURPLE}=== Performance Analysis ===${NC}"
start_time=$(date +%s)
test_endpoint "$BASE_URL?action=top&limit=1" "Performance measurement"
end_time=$(date +%s)
total_duration=$((end_time - start_time))
echo "Total test execution time: ${total_duration}s"

# Results summary
echo ""
echo "============================================="
echo -e "${PURPLE}FINAL TEST RESULTS${NC}"
echo "============================================="

TOTAL=$((PASSED + FAILED))
if [[ $TOTAL -gt 0 ]]; then
    PASS_RATE=$((PASSED * 100 / TOTAL))
    echo -e "Passed: ${GREEN}$PASSED${NC}"
    echo -e "Failed: ${RED}$FAILED${NC}"
    echo -e "Success Rate: ${BLUE}$PASS_RATE%${NC}"
else
    echo "No tests executed"
fi

echo ""

# Detailed results analysis
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed successfully!${NC}"
    echo ""
    echo "Your crypto function is working correctly with:"
    echo "  - Proper API integration with CoinGecko"
    echo "  - Comprehensive error handling"
    echo "  - Multiple currency support"
    echo "  - Rate limit compliance"
    echo "  - Input validation"
elif [[ $PASS_RATE -ge 80 ]]; then
    echo -e "${YELLOW}Most tests passed with minor issues${NC}"
    echo ""
    echo "Common causes of failures:"
    echo "  - Rate limiting from CoinGecko (429 errors)"
    echo "  - Temporary network issues"
    echo "  - API maintenance periods"
    echo ""
    echo "Recommendations:"
    echo "  - Wait 10-15 minutes before retesting"
    echo "  - Consider CoinGecko Pro for higher rate limits"
    echo "  - Monitor function logs for details"
elif [[ $PASS_RATE -ge 50 ]]; then
    echo -e "${YELLOW}Mixed results detected${NC}"
    echo ""
    echo "This typically indicates:"
    echo "  - Heavy rate limiting"
    echo "  - Function code issues"
    echo "  - Network connectivity problems"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check Azure Function logs"
    echo "  2. Verify API endpoints in code"
    echo "  3. Test individual requests manually"
else
    echo -e "${RED}Significant issues detected${NC}"
    echo ""
    echo "Immediate actions needed:"
    echo "  1. Check if 'func start' is running"
    echo "  2. Review function code for errors"
    echo "  3. Verify network connectivity"
    echo "  4. Check Azure Functions Core Tools installation"
fi

echo ""
echo "Testing tips:"
echo "  - Use --quick for faster testing with 5s delays"
echo "  - Use --extended for comprehensive testing"
echo "  - Use --debug for detailed request/response info"
echo "  - Wait at least 15 minutes between full test runs"

# Exit with appropriate code
exit $([[ $FAILED -eq 0 ]] && echo 0 || echo 1)