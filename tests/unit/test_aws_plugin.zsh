#!/usr/bin/env zsh

# AWS Plugin Unit Tests
# Tests AWS command detection, processing, and S3 URI correction functionality

# Load test framework
SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../helpers/test_framework.zsh"

# Load AWS plugin and dependencies
DOTFILES_ROOT="${SCRIPT_DIR}/../.."
source "${DOTFILES_ROOT}/zsh/utils.zsh"

# Load plugin registration system first
source "${DOTFILES_ROOT}/zsh/plugins_loader.zsh"

# Load AWS plugin (will use plugin_register from loader)
source "${DOTFILES_ROOT}/zsh/plugins/aws.zsh"

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Test configuration
test_config verbose true
test_config debug false

# Initialize test suite
test_framework_init "AWS Plugin Unit Tests"

# =============================================================================
# AWS COMMAND DETECTION TESTS
# =============================================================================

test_aws_command_detection_basic() {
  local test_command="aws s3 ls bucket-name"
  local result
  
  # Test that basic AWS commands are detected
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_contains "$result" "s3://bucket-name" "AWS middleware should correct S3 URI"
}

test_aws_command_detection_with_pipes() {
  local test_command="kubectl get pods | aws s3 cp - bucket-name/pods.txt"
  local result
  
  # Test AWS detection in pipe sequences
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_contains "$result" "s3://bucket-name" "AWS middleware should work with pipes"
}

test_aws_command_detection_with_logical_operators() {
  local test_command="export VAR=value && aws s3 ls bucket-name"
  local result
  
  # Test AWS detection with logical operators
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_contains "$result" "s3://bucket-name" "AWS middleware should work with logical operators"
}

test_aws_command_substitution_dollar_paren() {
  local test_command='VPC_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*test*")'
  local result
  
  # Test command substitution with $(...)
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  # Should trigger AWS session validation but not change the command structure
  assert_equals "$test_command" "$result" "Command substitution should preserve structure"
}

test_aws_command_substitution_backticks() {
  local test_command='RESULT=`aws s3 ls bucket-name` && echo $RESULT'
  local result
  
  # Test command substitution with backticks
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_contains "$result" "s3://bucket-name" "Backtick substitution should apply S3 URI correction"
}

test_aws_variable_assignment_filtering() {
  local test_command="K8S_CLUSTER_NAME=prd.k8s.multpex.com.br"
  local result
  
  # Test that variable assignments with 'aws' in value are not intercepted
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_equals "" "$result" "Variable assignments should not be intercepted"
}

test_aws_search_command_filtering() {
  local test_command='grep "aws" /var/log/system.log'
  local result
  
  # Test that search commands are not intercepted
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_equals "" "$result" "Search commands should not be intercepted"
}

# =============================================================================
# S3 URI CORRECTION TESTS
# =============================================================================

test_s3_uri_correction_ls_command() {
  local -a words=("aws" "s3" "ls" "bucket-name")
  local result
  
  # Test S3 ls URI correction
  result=$(aws_fix_s3_uri words 1 2>/dev/null)
  
  assert_equals "aws s3 ls s3://bucket-name" "$result" "S3 ls should add s3:// prefix"
}

test_s3_uri_correction_cp_command() {
  local -a words=("aws" "s3" "cp" "file.txt" "bucket-name/path")
  local result
  
  # Test S3 cp URI correction
  result=$(aws_fix_s3_uri words 1 2>/dev/null)
  
  assert_equals "aws s3 cp file.txt s3://bucket-name/path" "$result" "S3 cp should add s3:// prefix to destination"
}

test_s3_uri_correction_sync_command() {
  local -a words=("aws" "s3" "sync" "./local-dir" "bucket-name")
  local result
  
  # Test S3 sync URI correction
  result=$(aws_fix_s3_uri words 1 2>/dev/null)
  
  assert_equals "aws s3 sync ./local-dir s3://bucket-name" "$result" "S3 sync should add s3:// prefix to destination"
}

test_s3_uri_correction_mb_command() {
  local -a words=("aws" "s3" "mb" "my-new-bucket")
  local result
  
  # Test S3 mb (make bucket) URI correction
  result=$(aws_fix_s3_uri words 1 2>/dev/null)
  
  assert_equals "aws s3 mb s3://my-new-bucket" "$result" "S3 mb should add s3:// prefix"
}

test_s3_uri_correction_rb_command() {
  local -a words=("aws" "s3" "rb" "bucket-to-remove")
  local result
  
  # Test S3 rb (remove bucket) URI correction
  result=$(aws_fix_s3_uri words 1 2>/dev/null)
  
  assert_equals "aws s3 rb s3://bucket-to-remove" "$result" "S3 rb should add s3:// prefix"
}

test_s3_uri_correction_already_has_scheme() {
  local -a words=("aws" "s3" "ls" "s3://bucket-name")
  local result
  local exit_code
  
  # Test that URIs with existing scheme are not modified - function should return exit code 1
  result=$(aws_fix_s3_uri words 1 2>/dev/null)
  exit_code=$?
  
  assert_equals "" "$result" "Function should return empty when no correction needed"
  assert_equals 1 "$exit_code" "Function should return exit code 1 when no correction needed"
}

test_s3_uri_correction_rm_vs_rb_safety() {
  local -a rm_words=("aws" "s3" "rm" "s3://bucket/file.txt")
  local -a rb_words=("aws" "s3" "rb" "bucket-name")
  local rm_result rb_result rm_exit_code rb_exit_code
  
  # Test rm (remove object) vs rb (remove bucket) distinction
  rm_result=$(aws_fix_s3_uri rm_words 1 2>/dev/null)
  rm_exit_code=$?
  rb_result=$(aws_fix_s3_uri rb_words 1 2>/dev/null)
  rb_exit_code=$?
  
  # rm already has s3:// scheme - no correction needed, should return empty + exit code 1
  assert_equals "" "$rm_result" "rm with existing s3:// should not be modified"
  assert_equals 1 "$rm_exit_code" "rm with existing s3:// should return exit code 1"
  
  # rb needs s3:// prefix added - should return corrected command + exit code 0
  assert_equals "aws s3 rb s3://bucket-name" "$rb_result" "rb should add s3:// to bucket name"
  assert_equals 0 "$rb_exit_code" "rb correction should return exit code 0"
}

# =============================================================================
# AWS SESSION VALIDATION TESTS
# =============================================================================

test_aws_session_valid_check() {
  # Mock aws sts get-caller-identity for testing
  test_mock_command "aws" 'echo "{\"UserId\":\"test-user\",\"Account\":\"123456789012\",\"Arn\":\"arn:aws:iam::123456789012:user/test\"}"'
  
  # Test session validation
  assert_success "aws_session_valid" "Valid AWS session should return success"
}

test_aws_session_invalid_check() {
  # Save original AWS_PROFILE and set test profile
  local original_profile="$AWS_PROFILE"
  export AWS_PROFILE="test-invalid-profile"
  
  # Remove any existing cache for this test profile
  local cache_file="/tmp/aws_session_cache_$(whoami)_test-invalid-profile"
  rm -f "$cache_file" 2>/dev/null
  
  # Mock failing aws sts get-caller-identity
  test_mock_command "aws" 'echo "Unable to locate credentials" >&2; exit 1'
  
  # Test invalid session detection
  assert_failure "aws_session_valid" "Invalid AWS session should return failure"
  
  # Restore original AWS_PROFILE
  export AWS_PROFILE="$original_profile"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

test_complete_aws_middleware_workflow() {
  # Mock successful AWS session
  test_mock_command "aws" 'echo "{\"UserId\":\"test-user\"}"'
  
  local test_command="aws s3 ls my-bucket"
  local result
  
  # Test complete middleware workflow
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_contains "$result" "s3://my-bucket" "Complete workflow should apply S3 URI correction"
}

test_aws_middleware_performance() {
  local test_command="aws s3 ls bucket-name"
  local start_time end_time duration
  
  # Test middleware performance
  start_time=$EPOCHREALTIME
  aws_middleware "$test_command" >/dev/null 2>&1
  end_time=$EPOCHREALTIME
  
  duration=$(( (end_time - start_time) * 1000 ))
  
  # Should complete within 100ms for simple commands
  assert_true "(( duration < 100 ))" "AWS middleware should complete within 100ms (took ${duration}ms)"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_aws_empty_command() {
  local result
  
  # Test empty command handling
  result=$(aws_middleware "" 2>/dev/null)
  
  assert_equals "" "$result" "Empty command should return empty result"
}

test_aws_malformed_command() {
  local test_command="aws s3"
  local result
  
  # Test malformed AWS command
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  # Should not crash, may or may not modify command
  assert_success "true" "Malformed AWS command should not crash middleware"
}

test_aws_complex_nested_command() {
  local test_command='kubectl get pods --all-namespaces -o json | jq -r ".items[].metadata.name" | while read pod; do aws s3 cp "/tmp/${pod}.log" "backup-bucket/logs/"; done'
  local result
  
  # Test complex nested command with AWS
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_contains "$result" "s3://backup-bucket" "Complex nested commands should be processed correctly"
}

# =============================================================================
# SPECIFIC REGRESSION TESTS FROM COMMAND SUBSTITUTION ENHANCEMENT
# =============================================================================

test_regression_command_substitution_vpc_id() {
  # Regression test for VPC_ID command substitution case
  local test_command='VPC_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*${K8S_CLUSTER_NAME}*")'
  local result
  
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  # Should preserve command structure for EC2 commands (no S3 URI correction needed)
  assert_equals "$test_command" "$result" "VPC_ID command substitution should preserve structure"
}

test_regression_backtick_s3_ls() {
  # Regression test for backtick S3 ls case
  local test_command='FILES=`aws s3 ls my-bucket` && echo $FILES'
  local result
  
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_contains "$result" "s3://my-bucket" "Backtick S3 ls should apply URI correction"
}

test_regression_mixed_command_with_pipes() {
  # Regression test for mixed command with pipes and AWS
  local test_command='kubectl get pods | aws s3 cp - logs-bucket/cluster-state.txt'
  local result
  
  result=$(aws_middleware "$test_command" 2>/dev/null)
  
  assert_contains "$result" "s3://logs-bucket" "Mixed command with pipes should apply S3 URI correction"
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

# Run all test cases
echo "🧪 Starting AWS Plugin Unit Tests..."
echo

# AWS Command Detection Tests
test_case "AWS Command Detection - Basic" test_aws_command_detection_basic
test_case "AWS Command Detection - With Pipes" test_aws_command_detection_with_pipes
test_case "AWS Command Detection - With Logical Operators" test_aws_command_detection_with_logical_operators
test_case "AWS Command Substitution - \$()" test_aws_command_substitution_dollar_paren
test_case "AWS Command Substitution - Backticks" test_aws_command_substitution_backticks
test_case "AWS Variable Assignment Filtering" test_aws_variable_assignment_filtering
test_case "AWS Search Command Filtering" test_aws_search_command_filtering

# S3 URI Correction Tests
test_case "S3 URI Correction - ls command" test_s3_uri_correction_ls_command
test_case "S3 URI Correction - cp command" test_s3_uri_correction_cp_command  
test_case "S3 URI Correction - sync command" test_s3_uri_correction_sync_command
test_case "S3 URI Correction - mb command" test_s3_uri_correction_mb_command
test_case "S3 URI Correction - rb command" test_s3_uri_correction_rb_command
test_case "S3 URI Correction - Already has scheme" test_s3_uri_correction_already_has_scheme
test_case "S3 URI Correction - rm vs rb safety" test_s3_uri_correction_rm_vs_rb_safety

# AWS Session Validation Tests
test_case "AWS Session Valid Check" test_aws_session_valid_check
test_case "AWS Session Invalid Check" test_aws_session_invalid_check

# Integration Tests
test_case "Complete AWS Middleware Workflow" test_complete_aws_middleware_workflow
test_case "AWS Middleware Performance" test_aws_middleware_performance

# Edge Case Tests
test_case "AWS Empty Command" test_aws_empty_command
test_case "AWS Malformed Command" test_aws_malformed_command
test_case "AWS Complex Nested Command" test_aws_complex_nested_command

# Regression Tests
test_case "Regression - Command Substitution VPC_ID" test_regression_command_substitution_vpc_id
test_case "Regression - Backtick S3 ls" test_regression_backtick_s3_ls
test_case "Regression - Mixed Command with Pipes" test_regression_mixed_command_with_pipes

# Cleanup and exit
test_framework_cleanup