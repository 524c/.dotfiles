#!/usr/bin/env zsh

# Shell Parser Unit Tests
# Tests generic shell command detection, AST parsing, and pattern matching

# Load test framework
SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/../helpers/test_framework.zsh"

# Load shell parser and dependencies
DOTFILES_ROOT="${SCRIPT_DIR}/../.."
source "${DOTFILES_ROOT}/zsh/utils.zsh"

# Load plugin registration system first
source "${DOTFILES_ROOT}/zsh/plugins_loader.zsh"

# Load shell parser (will use plugin_register from loader)
source "${DOTFILES_ROOT}/zsh/plugins/shell_parser.zsh"

# =============================================================================
# TEST SETUP AND CONFIGURATION
# =============================================================================

# Test configuration
test_config verbose true
test_config debug false

# Initialize test suite
test_framework_init "Shell Parser Unit Tests"

# =============================================================================
# BASIC COMMAND DETECTION TESTS
# =============================================================================

test_shell_parser_aws_detection() {
  local test_command="aws s3 ls bucket-name"
  local result
  
  # Test basic AWS command detection
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_not_equals "" "$result" "AWS command should be detected"
  assert_contains "$result" "aws s3 ls bucket-name" "Result should contain the AWS command"
}

test_shell_parser_kubectl_detection() {
  local test_command="kubectl get pods --all-namespaces"
  local result
  
  # Test kubectl command detection
  result=$(detect_shell_commands "$test_command" "kubectl")
  
  assert_not_equals "" "$result" "kubectl command should be detected"
  assert_contains "$result" "kubectl get pods" "Result should contain the kubectl command"
}

test_shell_parser_docker_detection() {
  local test_command="docker run -d nginx"
  local result
  
  # Test docker command detection
  result=$(detect_shell_commands "$test_command" "docker")
  
  assert_not_equals "" "$result" "docker command should be detected"
  assert_contains "$result" "docker run" "Result should contain the docker command"
}

test_shell_parser_multiple_patterns() {
  local test_command="kubectl get pods | aws s3 cp - bucket/output.txt"
  local result
  
  # Test detection with multiple patterns
  result=$(detect_shell_commands "$test_command" "aws" "kubectl")
  
  assert_not_equals "" "$result" "Multiple commands should be detected"
  # Should detect both kubectl and aws
  assert_true '[[ "$result" == *"kubectl"* && "$result" == *"aws"* ]]' "Should detect both kubectl and aws"
}

# =============================================================================
# COMMAND SUBSTITUTION DETECTION TESTS
# =============================================================================

test_shell_parser_dollar_paren_substitution() {
  local test_command='VPC_ID=$(aws ec2 describe-instances)'
  local result
  
  # Test $(command) substitution detection
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_not_equals "" "$result" "AWS in command substitution should be detected"
  assert_contains "$result" "SUBST" "Result should indicate command substitution"
}

test_shell_parser_backtick_substitution() {
  local test_command='RESULT=`kubectl get nodes` && echo $RESULT'
  local result
  
  # Test `command` substitution detection
  result=$(detect_shell_commands "$test_command" "kubectl")
  
  assert_not_equals "" "$result" "kubectl in backtick substitution should be detected"
  assert_contains "$result" "SUBST" "Result should indicate command substitution"
}

test_shell_parser_nested_substitution() {
  local test_command='echo $(kubectl get pods | grep $(aws ecs list-tasks --output text))'
  local result
  
  # Test nested command substitution
  result=$(detect_shell_commands "$test_command" "aws" "kubectl")
  
  assert_not_equals "" "$result" "Nested substitutions should be detected"
  # Should detect both aws and kubectl
  assert_true '[[ "$result" == *"kubectl"* && "$result" == *"aws"* ]]' "Should detect both commands in nested substitution"
}

# =============================================================================
# SMART FILTERING TESTS (Layer 1)
# =============================================================================

test_shell_parser_variable_assignment_rejection() {
  local test_command="K8S_CLUSTER_NAME=prd.k8s.multpex.com.br"
  local result
  
  # Test that variable assignments are rejected
  result=$(detect_shell_commands "$test_command" "k8s")
  
  assert_equals "" "$result" "Variable assignments should be rejected"
}

test_shell_parser_search_command_rejection() {
  local test_command='grep "aws" /var/log/system.log'
  local result
  
  # Test that search commands are rejected
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_equals "" "$result" "Search commands should be rejected"
}

test_shell_parser_assignment_with_execution() {
  local test_command='BUCKET_LIST=$(aws s3 ls) && echo $BUCKET_LIST'
  local result
  
  # Test that assignments with command execution are NOT rejected
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_not_equals "" "$result" "Assignments with command execution should be detected"
}

# =============================================================================
# COMPLEX COMMAND STRUCTURE TESTS
# =============================================================================

test_shell_parser_pipe_sequences() {
  local test_command="kubectl get pods | grep running | aws s3 cp - bucket/status.txt"
  local result
  
  # Test pipe sequence handling
  result=$(detect_shell_commands "$test_command" "kubectl" "aws")
  
  assert_not_equals "" "$result" "Pipe sequences should be detected"
  assert_true '[[ "$result" == *"kubectl"* && "$result" == *"aws"* ]]' "Should detect commands in pipe sequence"
}

test_shell_parser_logical_operators() {
  local test_command="docker build . && kubectl apply -f deployment.yaml || echo 'Failed'"
  local result
  
  # Test logical operator handling
  result=$(detect_shell_commands "$test_command" "docker" "kubectl")
  
  assert_not_equals "" "$result" "Logical operators should be handled"
  assert_true '[[ "$result" == *"docker"* && "$result" == *"kubectl"* ]]' "Should detect commands with logical operators"
}

test_shell_parser_semicolon_sequences() {
  local test_command="export AWS_PROFILE=prod; aws s3 ls; kubectl get pods"
  local result
  
  # Test semicolon-separated commands
  result=$(detect_shell_commands "$test_command" "aws" "kubectl")
  
  assert_not_equals "" "$result" "Semicolon sequences should be handled"
  assert_true '[[ "$result" == *"aws"* && "$result" == *"kubectl"* ]]' "Should detect commands in semicolon sequence"
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

test_shell_parser_layer1_rejection_performance() {
  local test_command="completely_unrelated_command with no target patterns"
  local start_time end_time duration
  local result
  
  # Measure Layer 1 rejection performance
  start_time=$EPOCHREALTIME
  result=$(detect_shell_commands "$test_command" "aws" "kubectl" "docker")
  end_time=$EPOCHREALTIME
  
  duration=$(( (end_time - start_time) * 1000 ))
  
  assert_equals "" "$result" "Unrelated command should be rejected"
  assert_true "(( duration < 10 ))" "Layer 1 rejection should be fast (took ${duration}ms)"
}

test_shell_parser_cache_performance() {
  local test_command="aws s3 ls bucket-name"
  local start_time end_time duration1 duration2
  local result1 result2
  
  # First call (no cache)
  start_time=$EPOCHREALTIME
  result1=$(detect_shell_commands "$test_command" "aws" 2>/dev/null | grep -v "^pattern=")
  end_time=$EPOCHREALTIME
  duration1=$(( (end_time - start_time) * 1000 ))
  
  # Second call (cached)
  start_time=$EPOCHREALTIME
  result2=$(detect_shell_commands "$test_command" "aws" 2>/dev/null | grep -v "^pattern=")
  end_time=$EPOCHREALTIME
  duration2=$(( (end_time - start_time) * 1000 ))
  
  assert_equals "$result1" "$result2" "Cached result should match original"
  assert_true "(( duration2 <= duration1 ))" "Cached call should be faster or equal (${duration2}ms vs ${duration1}ms)"
}

# =============================================================================
# COMMAND REGISTRY TESTS
# =============================================================================

test_shell_parser_command_registration() {
  # Test command pattern registration
  register_command_handler "test_handler" "test_pattern" "test_function"
  
  assert_equals "test_pattern" "${COMMAND_PATTERNS[test_handler]}" "Pattern should be registered"
  assert_equals "test_function" "${COMMAND_HANDLERS[test_handler]}" "Handler should be registered"
}

test_shell_parser_handler_execution() {
  # Create a test handler function
  test_handler_function() {
    local input="$1"
    local context_type="$2"
    local command="$3"
    echo "PROCESSED:$context_type:$command"
  }
  
  # Register the handler
  register_command_handler "test_cmd" "test" "test_handler_function"
  
  # Test handler execution
  local result
  result=$(process_detected_commands "test command" "DIRECT:test:test command")
  
  assert_equals "PROCESSED:DIRECT:test command" "$result" "Handler should be executed correctly"
}

# =============================================================================
# AST PARSING TESTS
# =============================================================================

test_shell_parser_simple_command_tokenization() {
  local test_command="aws s3 ls bucket-name"
  local result
  
  # Test that simple commands are tokenized correctly
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_contains "$result" "aws s3 ls bucket-name" "Simple command should be tokenized correctly"
}

test_shell_parser_quoted_arguments() {
  local test_command='aws s3 cp "file with spaces.txt" bucket-name'
  local result
  
  # Test handling of quoted arguments
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_not_equals "" "$result" "Commands with quoted arguments should be detected"
  assert_contains "$result" "aws s3 cp" "Should detect AWS command with quoted args"
}

test_shell_parser_complex_quoting() {
  local test_command="kubectl get pods -o jsonpath='{.items[*].metadata.name}'"
  local result
  
  # Test complex quoting scenarios
  result=$(detect_shell_commands "$test_command" "kubectl")
  
  assert_not_equals "" "$result" "Commands with complex quoting should be detected"
  assert_contains "$result" "kubectl get pods" "Should detect kubectl with complex quotes"
}

# =============================================================================
# EDGE CASE TESTS
# =============================================================================

test_shell_parser_empty_input() {
  local result
  
  # Test empty input handling
  result=$(detect_shell_commands "" "aws")
  
  assert_equals "" "$result" "Empty input should return empty result"
}

test_shell_parser_whitespace_only() {
  local result
  
  # Test whitespace-only input
  result=$(detect_shell_commands "   \t\n   " "aws")
  
  assert_equals "" "$result" "Whitespace-only input should return empty result"
}

test_shell_parser_special_characters() {
  local test_command="aws s3 cp file.txt s3://bucket-name/path/with/special-chars_123"
  local result
  
  # Test handling of special characters
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_not_equals "" "$result" "Commands with special characters should be detected"
}

test_shell_parser_very_long_command() {
  # Create a very long command line
  local long_args=""
  for i in {1..100}; do
    long_args+=" --arg${i}=value${i}"
  done
  local test_command="aws s3 ls bucket-name${long_args}"
  local result
  
  # Test very long command handling
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_not_equals "" "$result" "Very long commands should be handled"
  assert_contains "$result" "aws s3 ls" "Should detect AWS command in long input"
}

# =============================================================================
# REGRESSION TESTS FROM EXISTING IMPLEMENTATIONS
# =============================================================================

test_regression_kubernetes_context_variable() {
  # Regression test: K8S context variable should not trigger detection
  local test_command="export KUBECONFIG=/path/to/kubectl/config"
  local result
  
  result=$(detect_shell_commands "$test_command" "kubectl")
  
  assert_equals "" "$result" "kubectl in path should not trigger detection"
}

test_regression_terraform_with_aws() {
  # Regression test: terraform commands mentioning AWS should not trigger AWS detection
  local test_command="terraform plan -var aws_region=us-east-1"
  local result
  
  result=$(detect_shell_commands "$test_command" "aws")
  
  assert_equals "" "$result" "AWS in terraform vars should not trigger detection"
}

test_regression_docker_with_aws_image() {
  # Regression test: docker commands with AWS image names
  local test_command="docker run amazon/aws-cli s3 ls"
  local result
  
  result=$(detect_shell_commands "$test_command" "aws")
  
  # This should detect the 'aws' command within the docker run
  assert_not_equals "" "$result" "AWS command in docker run should be detected"
}

# =============================================================================
# TEST EXECUTION
# =============================================================================

# Run all test cases
echo "🧪 Starting Shell Parser Unit Tests..."
echo

# Basic Command Detection Tests
test_case "Shell Parser - AWS Detection" test_shell_parser_aws_detection
test_case "Shell Parser - kubectl Detection" test_shell_parser_kubectl_detection
test_case "Shell Parser - docker Detection" test_shell_parser_docker_detection
test_case "Shell Parser - Multiple Patterns" test_shell_parser_multiple_patterns

# Command Substitution Tests
test_case "Shell Parser - \$() Substitution" test_shell_parser_dollar_paren_substitution
test_case "Shell Parser - Backtick Substitution" test_shell_parser_backtick_substitution
test_case "Shell Parser - Nested Substitution" test_shell_parser_nested_substitution

# Smart Filtering Tests
test_case "Shell Parser - Variable Assignment Rejection" test_shell_parser_variable_assignment_rejection
test_case "Shell Parser - Search Command Rejection" test_shell_parser_search_command_rejection
test_case "Shell Parser - Assignment with Execution" test_shell_parser_assignment_with_execution

# Complex Command Structure Tests
test_case "Shell Parser - Pipe Sequences" test_shell_parser_pipe_sequences
test_case "Shell Parser - Logical Operators" test_shell_parser_logical_operators
test_case "Shell Parser - Semicolon Sequences" test_shell_parser_semicolon_sequences

# Performance Tests
test_case "Shell Parser - Layer1 Rejection Performance" test_shell_parser_layer1_rejection_performance
test_case "Shell Parser - Cache Performance" test_shell_parser_cache_performance

# Command Registry Tests
test_case "Shell Parser - Command Registration" test_shell_parser_command_registration
test_case "Shell Parser - Handler Execution" test_shell_parser_handler_execution

# AST Parsing Tests
test_case "Shell Parser - Simple Command Tokenization" test_shell_parser_simple_command_tokenization
test_case "Shell Parser - Quoted Arguments" test_shell_parser_quoted_arguments
test_case "Shell Parser - Complex Quoting" test_shell_parser_complex_quoting

# Edge Case Tests
test_case "Shell Parser - Empty Input" test_shell_parser_empty_input
test_case "Shell Parser - Whitespace Only" test_shell_parser_whitespace_only
test_case "Shell Parser - Special Characters" test_shell_parser_special_characters
test_case "Shell Parser - Very Long Command" test_shell_parser_very_long_command

# Regression Tests
test_case "Regression - Kubernetes Context Variable" test_regression_kubernetes_context_variable
test_case "Regression - Terraform with AWS" test_regression_terraform_with_aws
test_case "Regression - Docker with AWS Image" test_regression_docker_with_aws_image

# Cleanup and exit
test_framework_cleanup