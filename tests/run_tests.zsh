#!/usr/bin/env zsh

# =============================================================================
# Dotfiles Test Runner - Master Test Execution System
# =============================================================================
# Purpose: Automated test discovery, parallel execution, and comprehensive reporting
# Version: 1.0.0
# Dependencies: ZSH 5.0+, test_framework.zsh
# =============================================================================

# Test runner configuration
TEST_RUNNER_VERSION="1.0.0"
TEST_ROOT="${0:A:h}"  # Directory containing this script
FRAMEWORK_PATH="${TEST_ROOT}/helpers/test_framework.zsh"

# Global test runner settings
PARALLEL_JOBS=${TEST_PARALLEL_JOBS:-4}
TIMEOUT_SECONDS=${TEST_TIMEOUT:-300}
FAIL_FAST=${TEST_FAIL_FAST:-false}
VERBOSE=${TEST_VERBOSE:-false}
OUTPUT_FORMAT=${TEST_OUTPUT_FORMAT:-"standard"}  # standard, json, junit, html
OUTPUT_DIR="${TEST_ROOT}/results"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Test execution state
declare -A test_results
declare -A test_durations
declare -A test_outputs
declare -a failed_tests
declare -a skipped_tests
total_tests=0
passed_tests=0
failed_test_count=0
skipped_test_count=0
start_time=""
end_time=""

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

show_usage() {
    cat << EOF
${BOLD}Dotfiles Test Runner v${TEST_RUNNER_VERSION}${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS] [TEST_PATTERN]

${BOLD}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -f, --fail-fast         Stop on first test failure
    -j, --jobs NUM          Number of parallel jobs (default: $PARALLEL_JOBS)
    -t, --timeout SECONDS   Test timeout in seconds (default: $TIMEOUT_SECONDS)
    -o, --output FORMAT     Output format: standard, json, junit, html (default: $OUTPUT_FORMAT)
    -d, --output-dir DIR    Output directory for reports (default: $OUTPUT_DIR)
    --list-tests            List all available tests without running
    --unit-only             Run only unit tests
    --integration-only      Run only integration tests
    --performance           Include performance benchmarks

${BOLD}EXAMPLES:${NC}
    $0                      # Run all tests
    $0 --verbose            # Run with verbose output
    $0 --fail-fast          # Stop on first failure
    $0 test_aws*            # Run tests matching pattern
    $0 --unit-only          # Run only unit tests
    $0 --output json        # Output in JSON format

${BOLD}ENVIRONMENT VARIABLES:${NC}
    TEST_PARALLEL_JOBS      Number of parallel jobs
    TEST_TIMEOUT            Test timeout in seconds
    TEST_FAIL_FAST          Fail fast mode (true/false)
    TEST_VERBOSE            Verbose output (true/false)
    TEST_OUTPUT_FORMAT      Output format
EOF
}

# =============================================================================
# Test Discovery Functions
# =============================================================================

discover_tests() {
    local pattern="${1:-test_*.zsh}"
    local test_files=()
    
    log_info "Discovering tests with pattern: $pattern"
    
    # Use find to locate test files
    if [[ -d "$TEST_ROOT/unit" ]]; then
        while IFS= read -r -d '' file; do
            test_files+=("$file")
        done < <(find "$TEST_ROOT/unit" -name "$pattern" -type f -print0 2>/dev/null)
    fi
    
    if [[ -d "$TEST_ROOT/integration" ]]; then
        while IFS= read -r -d '' file; do
            test_files+=("$file")
        done < <(find "$TEST_ROOT/integration" -name "$pattern" -type f -print0 2>/dev/null)
    fi
    
    if [[ -d "$TEST_ROOT/performance" ]]; then
        while IFS= read -r -d '' file; do
            test_files+=("$file")
        done < <(find "$TEST_ROOT/performance" -name "$pattern" -type f -print0 2>/dev/null)
    fi
    
    log_info "Found ${#test_files[@]} test files"
    printf '%s\n' "${test_files[@]}"
}

list_available_tests() {
    echo -e "${BOLD}Available Test Files:${NC}"
    
    local test_files=($(discover_tests))
    
    for file in "${test_files[@]}"; do
        local relative_path="${file#$TEST_ROOT/}"
        local test_type=""
        
        case "$relative_path" in
            unit/*) test_type="${CYAN}[UNIT]${NC}" ;;
            integration/*) test_type="${PURPLE}[INTEGRATION]${NC}" ;;
            performance/*) test_type="${YELLOW}[PERFORMANCE]${NC}" ;;
            *) test_type="${BLUE}[OTHER]${NC}" ;;
        esac
        
        echo -e "  $test_type $relative_path"
        
        # Show test functions in file
        if [[ "$VERBOSE" == "true" ]]; then
            local test_functions=($(grep -o 'test_[a-zA-Z0-9_]*()' "$file" 2>/dev/null | sed 's/()//'))
            for func in "${test_functions[@]}"; do
                echo -e "    └── $func"
            done
        fi
    done
}

# =============================================================================
# Test Execution Functions
# =============================================================================

execute_test_file() {
    local test_file="$1"
    local file_key="${test_file##*/}"  # Just filename for key
    local temp_output=$(mktemp)
    local start_time=$(date +%s.%N)
    
    log_info "Executing test file: $file_key"
    
    # Execute test with timeout
    (
        # Source the test framework
        source "$FRAMEWORK_PATH" 2>/dev/null || {
            echo "ERROR: Failed to source test framework" >&2
            exit 1
        }
        
        # Source and execute the test file
        source "$test_file" 2>&1
    ) > "$temp_output" 2>&1 &
    
    local test_pid=$!
    local timeout_occurred=false
    
    # Implement timeout
    (
        sleep "$TIMEOUT_SECONDS"
        if kill -0 "$test_pid" 2>/dev/null; then
            kill -TERM "$test_pid" 2>/dev/null
            sleep 2
            kill -KILL "$test_pid" 2>/dev/null
            timeout_occurred=true
        fi
    ) &
    local timeout_pid=$!
    
    # Wait for test completion
    local exit_code=0
    if wait "$test_pid" 2>/dev/null; then
        kill "$timeout_pid" 2>/dev/null
    else
        exit_code=$?
        timeout_occurred=true
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Store results
    test_durations[$file_key]="$duration"
    test_outputs[$file_key]=$(cat "$temp_output")
    
    if [[ "$timeout_occurred" == "true" ]]; then
        test_results[$file_key]="TIMEOUT"
        failed_tests+=("$file_key (TIMEOUT)")
        log_error "Test file $file_key timed out after ${TIMEOUT_SECONDS}s"
    elif [[ $exit_code -eq 0 ]]; then
        test_results[$file_key]="PASSED"
        ((passed_tests++))
        log_success "Test file $file_key passed (${duration}s)"
    else
        test_results[$file_key]="FAILED"
        failed_tests+=("$file_key")
        ((failed_test_count++))
        log_error "Test file $file_key failed (exit code: $exit_code)"
        
        if [[ "$VERBOSE" == "true" ]]; then
            echo -e "${RED}--- Test Output ---${NC}"
            cat "$temp_output"
            echo -e "${RED}--- End Output ---${NC}"
        fi
    fi
    
    rm -f "$temp_output"
    return $exit_code
}

run_tests_parallel() {
    local test_files=("$@")
    local job_count=0
    local pids=()
    
    log_info "Running ${#test_files[@]} test files with $PARALLEL_JOBS parallel jobs"
    
    for test_file in "${test_files[@]}"; do
        # Wait if we've hit the job limit
        while [[ $job_count -ge $PARALLEL_JOBS ]]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    wait "${pids[$i]}"
                    unset "pids[$i]"
                    ((job_count--))
                fi
            done
            pids=("${pids[@]}")  # Reindex array
            sleep 0.1
        done
        
        # Start new test
        execute_test_file "$test_file" &
        pids+=($!)
        ((job_count++))
        
        # Check for fail-fast
        if [[ "$FAIL_FAST" == "true" && $failed_test_count -gt 0 ]]; then
            log_warn "Fail-fast enabled, stopping test execution"
            break
        fi
    done
    
    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
}

run_tests_sequential() {
    local test_files=("$@")
    
    log_info "Running ${#test_files[@]} test files sequentially"
    
    for test_file in "${test_files[@]}"; do
        execute_test_file "$test_file"
        
        # Check for fail-fast
        if [[ "$FAIL_FAST" == "true" && $failed_test_count -gt 0 ]]; then
            log_warn "Fail-fast enabled, stopping test execution"
            break
        fi
    done
}

# =============================================================================
# Reporting Functions
# =============================================================================

generate_standard_report() {
    local total_duration=0
    
    echo
    echo -e "${BOLD}=== Test Execution Summary ===${NC}"
    echo
    
    # Calculate total duration
    for file_key in "${!test_durations[@]}"; do
        total_duration=$(echo "$total_duration + ${test_durations[$file_key]}" | bc -l 2>/dev/null || echo "$total_duration")
    done
    
    # Overall statistics
    echo -e "${BOLD}Overall Results:${NC}"
    echo -e "  Total Tests: $total_tests"
    echo -e "  ${GREEN}Passed: $passed_tests${NC}"
    echo -e "  ${RED}Failed: $failed_test_count${NC}"
    echo -e "  ${YELLOW}Skipped: $skipped_test_count${NC}"
    echo -e "  Total Duration: ${total_duration}s"
    echo
    
    # Test file results
    if [[ ${#test_results[@]} -gt 0 ]]; then
        echo -e "${BOLD}Test File Results:${NC}"
        for file_key in "${!test_results[@]}"; do
            local status="${test_results[$file_key]}"
            local duration="${test_durations[$file_key]:-0}"
            local color=""
            
            case "$status" in
                "PASSED") color="$GREEN" ;;
                "FAILED") color="$RED" ;;
                "TIMEOUT") color="$YELLOW" ;;
                *) color="$NC" ;;
            esac
            
            echo -e "  $color[$status]$NC $file_key (${duration}s)"
        done
        echo
    fi
    
    # Failed test details
    if [[ ${#failed_tests[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}Failed Tests:${NC}"
        for failed_test in "${failed_tests[@]}"; do
            echo -e "  ${RED}✗${NC} $failed_test"
        done
        echo
    fi
    
    # Success/failure indicator
    if [[ $failed_test_count -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}✗ Some tests failed!${NC}"
        return 1
    fi
}

generate_json_report() {
    local output_file="${OUTPUT_DIR}/test_results.json"
    
    mkdir -p "$OUTPUT_DIR"
    
    cat > "$output_file" << EOF
{
  "test_run": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "$TEST_RUNNER_VERSION",
    "total_tests": $total_tests,
    "passed": $passed_tests,
    "failed": $failed_test_count,
    "skipped": $skipped_test_count,
    "execution_time": "$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")"
  },
  "test_files": [
EOF
    
    local first=true
    for file_key in "${!test_results[@]}"; do
        [[ "$first" == "false" ]] && echo "," >> "$output_file"
        first=false
        
        cat >> "$output_file" << EOF
    {
      "name": "$file_key",
      "status": "${test_results[$file_key]}",
      "duration": ${test_durations[$file_key]:-0},
      "output": $(printf '%s' "${test_outputs[$file_key]}" | jq -Rs .)
    }
EOF
    done
    
    echo -e "\n  ]\n}" >> "$output_file"
    echo "JSON report generated: $output_file"
}

generate_junit_report() {
    local output_file="${OUTPUT_DIR}/junit_results.xml"
    
    mkdir -p "$OUTPUT_DIR"
    
    cat > "$output_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites tests="$total_tests" failures="$failed_test_count" time="$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")">
  <testsuite name="dotfiles-tests" tests="$total_tests" failures="$failed_test_count" time="$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")">
EOF
    
    for file_key in "${!test_results[@]}"; do
        local status="${test_results[$file_key]}"
        local duration="${test_durations[$file_key]:-0}"
        
        echo "    <testcase name=\"$file_key\" time=\"$duration\">" >> "$output_file"
        
        if [[ "$status" == "FAILED" || "$status" == "TIMEOUT" ]]; then
            echo "      <failure message=\"Test failed\"><![CDATA[" >> "$output_file"
            echo "${test_outputs[$file_key]}" >> "$output_file"
            echo "      ]]></failure>" >> "$output_file"
        fi
        
        echo "    </testcase>" >> "$output_file"
    done
    
    echo -e "  </testsuite>\n</testsuites>" >> "$output_file"
    echo "JUnit report generated: $output_file"
}

# =============================================================================
# Main Execution Function
# =============================================================================

main() {
    local test_pattern=""
    local list_only=false
    local unit_only=false
    local integration_only=false
    local performance_tests=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--fail-fast)
                FAIL_FAST=true
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -d|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --list-tests)
                list_only=true
                shift
                ;;
            --unit-only)
                unit_only=true
                shift
                ;;
            --integration-only)
                integration_only=true
                shift
                ;;
            --performance)
                performance_tests=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                test_pattern="$1"
                shift
                ;;
        esac
    done
    
    # Validate framework availability
    if [[ ! -f "$FRAMEWORK_PATH" ]]; then
        log_error "Test framework not found: $FRAMEWORK_PATH"
        exit 1
    fi
    
    # Handle list-only option
    if [[ "$list_only" == "true" ]]; then
        list_available_tests
        exit 0
    fi
    
    # Adjust test discovery based on options
    local discovery_pattern="${test_pattern:-test_*.zsh}"
    local test_files=()
    
    if [[ "$unit_only" == "true" ]]; then
        log_info "Running unit tests only"
        if [[ -d "$TEST_ROOT/unit" ]]; then
            while IFS= read -r -d '' file; do
                test_files+=("$file")
            done < <(find "$TEST_ROOT/unit" -name "$discovery_pattern" -type f -print0 2>/dev/null)
        fi
    elif [[ "$integration_only" == "true" ]]; then
        log_info "Running integration tests only"
        if [[ -d "$TEST_ROOT/integration" ]]; then
            while IFS= read -r -d '' file; do
                test_files+=("$file")
            done < <(find "$TEST_ROOT/integration" -name "$discovery_pattern" -type f -print0 2>/dev/null)
        fi
    else
        test_files=($(discover_tests "$discovery_pattern"))
    fi
    
    # Validate we have tests to run
    if [[ ${#test_files[@]} -eq 0 ]]; then
        log_error "No test files found matching pattern: $discovery_pattern"
        exit 1
    fi
    
    total_tests=${#test_files[@]}
    
    # Show execution info
    echo -e "${BOLD}Dotfiles Test Runner v${TEST_RUNNER_VERSION}${NC}"
    echo -e "Configuration:"
    echo -e "  Tests to run: $total_tests"
    echo -e "  Parallel jobs: $PARALLEL_JOBS"
    echo -e "  Timeout: ${TIMEOUT_SECONDS}s"
    echo -e "  Fail fast: $FAIL_FAST"
    echo -e "  Output format: $OUTPUT_FORMAT"
    echo
    
    # Record start time
    start_time=$(date +%s.%N)
    
    # Execute tests
    if [[ $PARALLEL_JOBS -gt 1 ]]; then
        run_tests_parallel "${test_files[@]}"
    else
        run_tests_sequential "${test_files[@]}"
    fi
    
    # Record end time
    end_time=$(date +%s.%N)
    
    # Generate reports
    case "$OUTPUT_FORMAT" in
        "json")
            generate_json_report
            ;;
        "junit")
            generate_junit_report
            ;;
        "html")
            # TODO: Implement HTML report generation
            log_warn "HTML reporting not yet implemented, falling back to standard"
            generate_standard_report
            ;;
        *)
            generate_standard_report
            ;;
    esac
    
    # Exit with appropriate code
    exit $failed_test_count
}

# Execute main function if script is run directly
# ZSH-compatible execution check
main "$@"