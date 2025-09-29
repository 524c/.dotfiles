#!/usr/bin/env zsh

# Professional Test Framework for Dotfiles Project
# Provides standardized testing utilities, assertions, and reporting

# =============================================================================
# TEST FRAMEWORK CONFIGURATION
# =============================================================================

# Test framework globals
typeset -g TEST_FRAMEWORK_VERSION="1.0.0"
typeset -g TEST_FRAMEWORK_LOADED=true

# Test statistics
typeset -gA TEST_STATS
TEST_STATS[total_tests]=0
TEST_STATS[passed_tests]=0
TEST_STATS[failed_tests]=0
TEST_STATS[skipped_tests]=0
TEST_STATS[start_time]=0
TEST_STATS[end_time]=0

# Test configuration
typeset -gA TEST_CONFIG
TEST_CONFIG[verbose]=false
TEST_CONFIG[debug]=false
TEST_CONFIG[fail_fast]=false
TEST_CONFIG[output_format]="standard"  # standard, json, junit
TEST_CONFIG[test_timeout]=30
TEST_CONFIG[temp_dir]="/tmp/dotfiles_tests_$$"

# Current test context
typeset -gA TEST_CONTEXT
TEST_CONTEXT[current_suite]=""
TEST_CONTEXT[current_test]=""
TEST_CONTEXT[setup_done]=false
TEST_CONTEXT[teardown_needed]=false

# Test result storage
typeset -ga TEST_RESULTS
TEST_RESULTS=()

# =============================================================================
# COLOR DEFINITIONS FOR OUTPUT
# =============================================================================

# Only define colors if not already defined (prevent readonly variable errors)
if [[ -z "${_TEST_FRAMEWORK_COLORS_INITIALIZED:-}" ]]; then
  if [[ -t 1 ]] && [[ "${TERM}" != "dumb" ]]; then
    typeset -gr COLOR_RED='\033[0;31m'
    typeset -gr COLOR_GREEN='\033[0;32m'
    typeset -gr COLOR_YELLOW='\033[1;33m'
    typeset -gr COLOR_BLUE='\033[0;34m'
    typeset -gr COLOR_PURPLE='\033[0;35m'
    typeset -gr COLOR_CYAN='\033[0;36m'
    typeset -gr COLOR_WHITE='\033[1;37m'
    typeset -gr COLOR_RESET='\033[0m'
    typeset -gr COLOR_BOLD='\033[1m'
    typeset -gr COLOR_DIM='\033[2m'
  else
    typeset -gr COLOR_RED=''
    typeset -gr COLOR_GREEN=''
    typeset -gr COLOR_YELLOW=''
    typeset -gr COLOR_BLUE=''
    typeset -gr COLOR_PURPLE=''
    typeset -gr COLOR_CYAN=''
    typeset -gr COLOR_WHITE=''
    typeset -gr COLOR_RESET=''
    typeset -gr COLOR_BOLD=''
    typeset -gr COLOR_DIM=''
  fi
  
  # Mark colors as initialized to prevent redefinition
  typeset -gr _TEST_FRAMEWORK_COLORS_INITIALIZED=1
fi

# =============================================================================
# CORE FRAMEWORK FUNCTIONS
# =============================================================================

# Initialize test framework
test_framework_init() {
  local suite_name="$1"
  
  TEST_STATS[start_time]=$EPOCHREALTIME
  TEST_CONTEXT[current_suite]="$suite_name"
  
  # Create temporary directory for test artifacts
  mkdir -p "${TEST_CONFIG[temp_dir]}"
  
  # Print test suite header
  _test_print_header "Starting Test Suite: $suite_name"
}

# Cleanup test framework
test_framework_cleanup() {
  TEST_STATS[end_time]=$EPOCHREALTIME
  
  # Clean up temporary directory
  [[ -d "${TEST_CONFIG[temp_dir]}" ]] && rm -rf "${TEST_CONFIG[temp_dir]}"
  
  # Print final results
  _test_print_summary
  
  # Exit with proper code
  local exit_code=0
  (( TEST_STATS[failed_tests] > 0 )) && exit_code=1
  
  return $exit_code
}

# Set test configuration
test_config() {
  local key="$1"
  local value="$2"
  
  case "$key" in
    verbose|debug|fail_fast)
      TEST_CONFIG[$key]="$value"
      ;;
    output_format)
      case "$value" in
        standard|json|junit)
          TEST_CONFIG[$key]="$value"
          ;;
        *)
          _test_error "Invalid output format: $value. Use: standard, json, junit"
          return 1
          ;;
      esac
      ;;
    test_timeout)
      [[ "$value" =~ '^[0-9]+$' ]] || {
        _test_error "test_timeout must be numeric: $value"
        return 1
      }
      TEST_CONFIG[$key]="$value"
      ;;
    *)
      _test_error "Unknown configuration key: $key"
      return 1
      ;;
  esac
}

# =============================================================================
# TEST EXECUTION FUNCTIONS
# =============================================================================

# Define a test case
test_case() {
  local test_name="$1"
  local test_function="$2"
  
  TEST_CONTEXT[current_test]="$test_name"
  ((TEST_STATS[total_tests]++))
  
  _test_verbose "Running test: $test_name"
  
  # Setup test environment
  _test_setup_environment
  
  # Run the test with timeout
  local test_result="passed"
  local error_message=""
  local start_time=$EPOCHREALTIME
  
  if ! _test_run_with_timeout "$test_function" "${TEST_CONFIG[test_timeout]}"; then
    test_result="failed"
    error_message="Test function failed or timed out"
  fi
  
  local end_time=$EPOCHREALTIME
  local duration=$(( (end_time - start_time) * 1000 ))
  
  # Cleanup test environment
  _test_teardown_environment
  
  # Record result
  _test_record_result "$test_name" "$test_result" "$error_message" "$duration"
  
  # Update statistics
  case "$test_result" in
    passed) ((TEST_STATS[passed_tests]++)) ;;
    failed) ((TEST_STATS[failed_tests]++)) ;;
    skipped) ((TEST_STATS[skipped_tests]++)) ;;
  esac
  
  # Print result
  _test_print_result "$test_name" "$test_result" "$error_message" "$duration"
  
  # Fail fast if configured
  if [[ "$test_result" == "failed" && "${TEST_CONFIG[fail_fast]}" == "true" ]]; then
    _test_error "Failing fast due to test failure: $test_name"
    test_framework_cleanup
    exit 1
  fi
  
  return $(( test_result == "failed" ? 1 : 0 ))
}

# Skip a test case
test_skip() {
  local test_name="$1"
  local reason="${2:-No reason provided}"
  
  ((TEST_STATS[total_tests]++))
  ((TEST_STATS[skipped_tests]++))
  
  _test_record_result "$test_name" "skipped" "$reason" "0"
  _test_print_result "$test_name" "skipped" "$reason" "0"
}

# =============================================================================
# ASSERTION FUNCTIONS
# =============================================================================

# Assert equality
assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values are not equal}"
  
  if [[ "$expected" != "$actual" ]]; then
    _test_assertion_failed "$message" "Expected: '$expected'" "Actual: '$actual'"
    return 1
  fi
  
  _test_debug "✓ assert_equals passed: '$actual'"
  return 0
}

# Assert not equal
assert_not_equals() {
  local expected="$1"
  local actual="$2"
  local message="${3:-Values should not be equal}"
  
  if [[ "$expected" == "$actual" ]]; then
    _test_assertion_failed "$message" "Both values: '$actual'"
    return 1
  fi
  
  _test_debug "✓ assert_not_equals passed"
  return 0
}

# Assert string contains
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-String does not contain expected substring}"
  
  if [[ "$haystack" != *"$needle"* ]]; then
    _test_assertion_failed "$message" "String: '$haystack'" "Expected to contain: '$needle'"
    return 1
  fi
  
  _test_debug "✓ assert_contains passed"
  return 0
}

# Assert string does not contain
assert_not_contains() {
  local haystack="$1"
  local needle="$2"  
  local message="${3:-String should not contain substring}"
  
  if [[ "$haystack" == *"$needle"* ]]; then
    _test_assertion_failed "$message" "String: '$haystack'" "Should not contain: '$needle'"
    return 1
  fi
  
  _test_debug "✓ assert_not_contains passed"
  return 0
}

# Assert true condition
assert_true() {
  local condition="$1"
  local message="${2:-Condition should be true}"
  
  if ! eval "$condition"; then
    _test_assertion_failed "$message" "Condition: '$condition'" "Result: false"
    return 1
  fi
  
  _test_debug "✓ assert_true passed: '$condition'"
  return 0
}

# Assert false condition  
assert_false() {
  local condition="$1"
  local message="${2:-Condition should be false}"
  
  if eval "$condition"; then
    _test_assertion_failed "$message" "Condition: '$condition'" "Result: true"
    return 1
  fi
  
  _test_debug "✓ assert_false passed: '$condition'"
  return 0
}

# Assert command success
assert_success() {
  local command="$1"
  local message="${2:-Command should succeed}"
  
  if ! eval "$command" >/dev/null 2>&1; then
    _test_assertion_failed "$message" "Command: '$command'" "Exit code: $?"
    return 1
  fi
  
  _test_debug "✓ assert_success passed: '$command'"
  return 0
}

# Assert command failure
assert_failure() {
  local command="$1"
  local message="${2:-Command should fail}"
  
  if eval "$command" >/dev/null 2>&1; then
    _test_assertion_failed "$message" "Command: '$command'" "Expected failure but succeeded"
    return 1
  fi
  
  _test_debug "✓ assert_failure passed: '$command'"
  return 0
}

# Assert file exists
assert_file_exists() {
  local file_path="$1"
  local message="${2:-File should exist}"
  
  if [[ ! -f "$file_path" ]]; then
    _test_assertion_failed "$message" "File: '$file_path'" "File does not exist"
    return 1
  fi
  
  _test_debug "✓ assert_file_exists passed: '$file_path'"
  return 0
}

# Assert file does not exist
assert_file_not_exists() {
  local file_path="$1"
  local message="${2:-File should not exist}"
  
  if [[ -f "$file_path" ]]; then
    _test_assertion_failed "$message" "File: '$file_path'" "File exists but shouldn't"
    return 1
  fi
  
  _test_debug "✓ assert_file_not_exists passed: '$file_path'"
  return 0
}

# Assert array length
assert_array_length() {
  local -n array_ref=$1
  local expected_length="$2"
  local message="${3:-Array length mismatch}"
  
  local actual_length=${#array_ref[@]}
  
  if [[ "$actual_length" != "$expected_length" ]]; then
    _test_assertion_failed "$message" "Expected length: $expected_length" "Actual length: $actual_length"
    return 1
  fi
  
  _test_debug "✓ assert_array_length passed: $actual_length"
  return 0
}

# =============================================================================
# TEST UTILITIES
# =============================================================================

# Create temporary file for test
test_temp_file() {
  local suffix="${1:-.tmp}"
  local temp_file="${TEST_CONFIG[temp_dir]}/test_${RANDOM}${suffix}"
  
  touch "$temp_file"
  echo "$temp_file"
}

# Create temporary directory for test
test_temp_dir() {
  local suffix="${1:-}"
  local temp_dir="${TEST_CONFIG[temp_dir]}/test_dir_${RANDOM}${suffix}"
  
  mkdir -p "$temp_dir"
  echo "$temp_dir"
}

# Mock a command for testing
test_mock_command() {
  local command_name="$1"
  local mock_script="$2"
  local mock_path="${TEST_CONFIG[temp_dir]}/mock_${command_name}"
  
  # Ensure temp directory exists
  mkdir -p "${TEST_CONFIG[temp_dir]}"
  
  cat > "$mock_path" << EOF
#!/usr/bin/env zsh
$mock_script
EOF
  
  chmod +x "$mock_path"
  
  # Add to PATH temporarily
  export PATH="${TEST_CONFIG[temp_dir]}:$PATH"
  
  _test_debug "Mocked command: $command_name at $mock_path"
}

# Capture command output for testing
test_capture_output() {
  local command="$1"
  local output_file="${TEST_CONFIG[temp_dir]}/capture_output_${RANDOM}"
  
  eval "$command" > "$output_file" 2>&1
  local exit_code=$?
  
  cat "$output_file"
  return $exit_code
}

# =============================================================================
# INTERNAL HELPER FUNCTIONS
# =============================================================================

# Print test header
_test_print_header() {
  local message="$1"
  
  echo
  echo "${COLOR_BOLD}${COLOR_BLUE}═══════════════════════════════════════════════════════════════${COLOR_RESET}"
  echo "${COLOR_BOLD}${COLOR_WHITE}  $message${COLOR_RESET}"
  echo "${COLOR_BOLD}${COLOR_BLUE}═══════════════════════════════════════════════════════════════${COLOR_RESET}"
  echo
}

# Print test result
_test_print_result() {
  local test_name="$1"
  local result="$2"
  local message="$3"
  local duration="$4"
  
  local status_color result_icon
  
  case "$result" in
    passed)
      status_color="$COLOR_GREEN"
      result_icon="✅"
      ;;
    failed)
      status_color="$COLOR_RED" 
      result_icon="❌"
      ;;
    skipped)
      status_color="$COLOR_YELLOW"
      result_icon="⏭️ "
      ;;
  esac
  
  printf "${status_color}%s %s${COLOR_RESET} ${COLOR_DIM}(%.2fms)${COLOR_RESET}" \
    "$result_icon" "$test_name" "$duration"
  
  if [[ -n "$message" && "$result" != "passed" ]]; then
    printf " - ${COLOR_DIM}%s${COLOR_RESET}" "$message"
  fi
  
  echo
}

# Print test summary
_test_print_summary() {
  local duration=$(( (TEST_STATS[end_time] - TEST_STATS[start_time]) * 1000 ))
  local total=${TEST_STATS[total_tests]}
  local passed=${TEST_STATS[passed_tests]}
  local failed=${TEST_STATS[failed_tests]}
  local skipped=${TEST_STATS[skipped_tests]}
  
  echo
  echo "${COLOR_BOLD}${COLOR_WHITE}Test Results Summary${COLOR_RESET}"
  echo "${COLOR_BOLD}${COLOR_BLUE}━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  
  printf "Total Tests:   ${COLOR_BOLD}%d${COLOR_RESET}\n" "$total"
  printf "Passed:        ${COLOR_GREEN}%d${COLOR_RESET}\n" "$passed"
  printf "Failed:        ${COLOR_RED}%d${COLOR_RESET}\n" "$failed"
  printf "Skipped:       ${COLOR_YELLOW}%d${COLOR_RESET}\n" "$skipped"
  printf "Duration:      ${COLOR_CYAN}%.2fms${COLOR_RESET}\n" "$duration"
  
  echo
  
  local success_rate=0
  (( total > 0 )) && success_rate=$(( (passed * 100) / total ))
  
  if (( failed == 0 )); then
    printf "${COLOR_GREEN}${COLOR_BOLD}🎉 All tests passed! (%.0f%% success rate)${COLOR_RESET}\n" "$success_rate"
  else
    printf "${COLOR_RED}${COLOR_BOLD}💥 %d test(s) failed (%.0f%% success rate)${COLOR_RESET}\n" "$failed" "$success_rate"
  fi
  
  echo
}

# Handle assertion failures
_test_assertion_failed() {
  local message="$1"
  shift
  local details=("$@")
  
  echo >&2
  echo "${COLOR_RED}${COLOR_BOLD}❌ Assertion Failed:${COLOR_RESET} $message" >&2
  
  for detail in "${details[@]}"; do
    echo "${COLOR_DIM}   $detail${COLOR_RESET}" >&2
  done
  
  echo >&2
  
  return 1
}

# Record test result
_test_record_result() {
  local test_name="$1"
  local result="$2"
  local message="$3"
  local duration="$4"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
  
  TEST_RESULTS+=("$timestamp|${TEST_CONTEXT[current_suite]}|$test_name|$result|$duration|$message")
}

# Setup test environment
_test_setup_environment() {
  TEST_CONTEXT[setup_done]=true
  TEST_CONTEXT[teardown_needed]=true
  
  # Save current PATH
  export TEST_ORIGINAL_PATH="$PATH"
  
  _test_debug "Test environment setup complete"
}

# Teardown test environment
_test_teardown_environment() {
  if [[ "${TEST_CONTEXT[teardown_needed]}" == "true" ]]; then
    # Restore original PATH
    [[ -n "${TEST_ORIGINAL_PATH:-}" ]] && export PATH="$TEST_ORIGINAL_PATH"
    
    # Clean up any test-specific temporary files
    find "${TEST_CONFIG[temp_dir]}" -name "test_*" -type f -mtime 0 -delete 2>/dev/null || true
    
    TEST_CONTEXT[teardown_needed]=false
    
    _test_debug "Test environment teardown complete"
  fi
}

# Run function with timeout
_test_run_with_timeout() {
  local function_name="$1"
  local timeout_seconds="$2"
  
  # Simple timeout implementation using background process
  (
    eval "$function_name"
  ) &
  
  local pid=$!
  local timeout_reached=false
  
  # Wait for completion or timeout
  for (( i=0; i<timeout_seconds; i++ )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      # Process completed
      wait "$pid"
      return $?
    fi
    sleep 1
  done
  
  # Timeout reached
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  
  _test_error "Test timed out after ${timeout_seconds}s"
  return 1
}

# Debug output
_test_debug() {
  [[ "${TEST_CONFIG[debug]}" == "true" ]] && echo "${COLOR_DIM}[DEBUG] $*${COLOR_RESET}" >&2
}

# Verbose output
_test_verbose() {
  [[ "${TEST_CONFIG[verbose]}" == "true" ]] && echo "${COLOR_CYAN}[INFO] $*${COLOR_RESET}" >&2
}

# Error output
_test_error() {
  echo "${COLOR_RED}[ERROR] $*${COLOR_RESET}" >&2
}

# =============================================================================
# FRAMEWORK VALIDATION
# =============================================================================

# Validate framework is properly loaded
_test_validate_framework() {
  local missing_functions=()
  
  local required_functions=(
    "test_framework_init"
    "test_framework_cleanup"
    "test_case"
    "assert_equals"
    "assert_true"
    "assert_false"
  )
  
  for func in "${required_functions[@]}"; do
    if ! typeset -f "$func" >/dev/null; then
      missing_functions+=("$func")
    fi
  done
  
  if (( ${#missing_functions[@]} > 0 )); then
    _test_error "Missing required functions: ${missing_functions[*]}"
    return 1
  fi
  
  return 0
}

# Export framework version for verification
test_framework_version() {
  echo "$TEST_FRAMEWORK_VERSION"
}

# Validate framework on load
_test_validate_framework || {
  echo "❌ Test framework validation failed" >&2
  return 1
}

echo "✅ Professional Test Framework v${TEST_FRAMEWORK_VERSION} loaded successfully"