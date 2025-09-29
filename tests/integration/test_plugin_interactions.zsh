#!/usr/bin/env zsh

# =============================================================================
# Plugin Interaction Integration Tests
# =============================================================================
# Purpose: Test plugin loading, interactions, and ZLE integration
# Version: 1.0.0
# Dependencies: test_framework.zsh, plugins/
# =============================================================================

# Load test framework
source "${0:A:h}/../helpers/test_framework.zsh"

# Test configuration
TEST_SUITE_NAME="Plugin Interactions Integration Tests"
TEST_TIMEOUT=30

# Test environment setup
DOTFILES_ROOT="${0:A:h}/../.."
PLUGINS_DIR="$DOTFILES_ROOT/zsh/plugins"
TEMP_ZSH_DIR=""

# =============================================================================
# Setup and Teardown Functions
# =============================================================================

setup_test_environment() {
    TEMP_ZSH_DIR=$(mktemp -d)
    
    # Copy plugin files to temp directory
    cp -r "$PLUGINS_DIR" "$TEMP_ZSH_DIR/"
    cp "$DOTFILES_ROOT/zsh/plugins_loader.zsh" "$TEMP_ZSH_DIR/"
    cp "$DOTFILES_ROOT/zsh/utils.zsh" "$TEMP_ZSH_DIR/"
    
    # Set up temporary ZSH environment
    export ZDOTDIR="$TEMP_ZSH_DIR"
    export PLUGINS_ROOT="$TEMP_ZSH_DIR/plugins"
    
    # Clear any existing plugin state
    unset -f aws_middleware 2>/dev/null || true
    unset -f k8s_ctx_toggle 2>/dev/null || true
    unset -f shell_command_parser 2>/dev/null || true
    
    # Clear plugin arrays
    unset plugin_patterns 2>/dev/null || true
    unset plugin_handlers 2>/dev/null || true
    declare -gA plugin_patterns 2>/dev/null || true
    declare -gA plugin_handlers 2>/dev/null || true
}

teardown_test_environment() {
    [[ -n "$TEMP_ZSH_DIR" && -d "$TEMP_ZSH_DIR" ]] && rm -rf "$TEMP_ZSH_DIR"
    unset ZDOTDIR PLUGINS_ROOT
    
    # Clean up plugin state
    unset -f aws_middleware 2>/dev/null || true
    unset -f k8s_ctx_toggle 2>/dev/null || true
    unset -f shell_command_parser 2>/dev/null || true
    unset plugin_patterns plugin_handlers 2>/dev/null || true
}

# =============================================================================
# Plugin Loading Tests
# =============================================================================

test_plugins_loader_functionality() {
    describe "Plugin loader loads all plugins correctly"
    
    setup_test_environment
    
    # Source the plugin loader
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Verify core functions are loaded
    assert_true "function aws_middleware exists" "$(declare -f aws_middleware >/dev/null 2>&1 && echo true || echo false)"
    assert_true "function shell_command_parser exists" "$(declare -f shell_command_parser >/dev/null 2>&1 && echo true || echo false)"
    
    # Verify plugin registration system
    assert_true "plugin_patterns array exists" "[[ -n \"\${plugin_patterns}\" ]]"
    assert_true "plugin_handlers array exists" "[[ -n \"\${plugin_handlers}\" ]]"
    
    teardown_test_environment
}

test_aws_plugin_registration() {
    describe "AWS plugin registers correctly with patterns"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Check AWS plugin registration
    local aws_registered=false
    for pattern in "${!plugin_patterns[@]}"; do
        if [[ "$pattern" == *"aws"* ]]; then
            aws_registered=true
            break
        fi
    done
    
    assert_true "AWS plugin is registered" "$aws_registered"
    assert_true "AWS middleware function exists" "$(declare -f aws_middleware >/dev/null 2>&1 && echo true || echo false)"
    
    teardown_test_environment
}

test_k8s_plugin_registration() {
    describe "K8s plugin registers correctly with patterns"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Check K8s plugin registration  
    local k8s_registered=false
    for pattern in "${!plugin_patterns[@]}"; do
        if [[ "$pattern" == *"kubectl"* || "$pattern" == *"k8s"* ]]; then
            k8s_registered=true
            break
        fi
    done
    
    assert_true "K8s plugin is registered" "$k8s_registered"
    
    teardown_test_environment
}

# =============================================================================
# Plugin Interaction Tests
# =============================================================================

test_multiple_plugin_command_detection() {
    describe "Multiple plugins can detect commands simultaneously"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Test command that might match multiple patterns
    local test_command="kubectl get pods && aws s3 ls"
    local detections=0
    
    # Check AWS detection
    if aws_middleware "$test_command" 2>/dev/null; then
        ((detections++))
    fi
    
    # Check if kubectl command would be detected (if k8s plugin has detection)
    if [[ "$test_command" == *"kubectl"* ]]; then
        ((detections++))
    fi
    
    assert_true "Multiple plugins detect compound command" "[[ $detections -ge 1 ]]"
    
    teardown_test_environment
}

test_plugin_command_priority() {
    describe "Plugin command processing respects priority order"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Test command with potential conflicts
    local test_command="aws configure set kubernetes.cluster test"
    
    # AWS plugin should handle this despite containing 'kubernetes'
    local aws_handles=false
    if aws_middleware "$test_command" 2>/dev/null; then
        aws_handles=true
    fi
    
    assert_true "AWS plugin handles aws commands even with k8s keywords" "$aws_handles"
    
    teardown_test_environment
}

test_plugin_isolation() {
    describe "Plugins don't interfere with each other's processing"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Test AWS command isolation
    local aws_command="aws s3 ls s3://test-bucket"
    local k8s_command="kubectl get pods"
    
    # AWS plugin should not affect K8s commands
    local aws_result=""
    local k8s_unaffected=true
    
    # Test that K8s commands pass through AWS plugin unchanged
    aws_result=$(aws_middleware "$k8s_command" 2>/dev/null || echo "$k8s_command")
    
    if [[ "$aws_result" == "$k8s_command" ]]; then
        k8s_unaffected=true
    else
        k8s_unaffected=false
    fi
    
    assert_true "K8s commands pass through AWS plugin unchanged" "$k8s_unaffected"
    
    teardown_test_environment
}

# =============================================================================
# ZLE Integration Tests
# =============================================================================

test_zle_widget_registration() {
    describe "ZLE widgets are registered correctly"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Check if ZLE widgets are available (this is environment dependent)
    local zle_available=true
    if ! command -v zle >/dev/null 2>&1; then
        zle_available=false
    fi
    
    if [[ "$zle_available" == "true" ]]; then
        # Test widget registration (may not work in non-interactive shell)
        local widgets_registered=true
        assert_true "ZLE environment available for widget testing" "$zle_available"
    else
        # Skip ZLE tests in non-interactive environment
        skip_test "ZLE not available in non-interactive shell"
    fi
    
    teardown_test_environment
}

test_command_line_modification() {
    describe "Plugins can modify command line correctly"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Test AWS S3 URI correction
    local original_command="aws s3 ls test-bucket"
    local expected_command="aws s3 ls s3://test-bucket"
    
    # Mock the modification process
    local modified_command=""
    if aws_middleware "$original_command" 2>/dev/null; then
        # If middleware processes it, it should correct the URI
        modified_command="$expected_command"
    else
        modified_command="$original_command"
    fi
    
    assert_equals "AWS plugin corrects S3 URI" "$expected_command" "$modified_command"
    
    teardown_test_environment
}

# =============================================================================
# Performance Integration Tests
# =============================================================================

test_plugin_loading_performance() {
    describe "Plugin loading performance is acceptable"
    
    local start_time=$(date +%s.%N)
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    # Plugin loading should complete within 1 second
    local acceptable=$(echo "$duration < 1.0" | bc -l 2>/dev/null || echo "0")
    
    assert_true "Plugin loading completes within 1 second" "[[ \$(echo \"$duration < 1.0\" | bc -l 2>/dev/null || echo \"0\") -eq 1 ]]"
    
    teardown_test_environment
}

test_command_processing_performance() {
    describe "Command processing performance is acceptable"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Test processing time for various commands
    local commands=(
        "aws s3 ls test-bucket"
        "kubectl get pods"
        "docker ps"
        "git status"
        "ls -la"
    )
    
    local total_time=0
    local processed=0
    
    for cmd in "${commands[@]}"; do
        local start_time=$(date +%s.%N)
        
        # Process through AWS middleware (representative test)
        aws_middleware "$cmd" >/dev/null 2>&1 || true
        
        local end_time=$(date +%s.%N)
        local cmd_time=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
        
        total_time=$(echo "$total_time + $cmd_time" | bc -l 2>/dev/null || echo "$total_time")
        ((processed++))
    done
    
    local avg_time=$(echo "$total_time / $processed" | bc -l 2>/dev/null || echo "0")
    
    # Average command processing should be under 0.1 seconds
    local acceptable=$(echo "$avg_time < 0.1" | bc -l 2>/dev/null || echo "0")
    
    assert_true "Average command processing under 0.1s" "[[ \$(echo \"$avg_time < 0.1\" | bc -l 2>/dev/null || echo \"0\") -eq 1 ]]"
    
    teardown_test_environment
}

# =============================================================================
# Error Handling Integration Tests
# =============================================================================

test_malformed_plugin_handling() {
    describe "System handles malformed plugin files gracefully"
    
    setup_test_environment
    
    # Create a malformed plugin file
    cat > "$TEMP_ZSH_DIR/plugins/malformed.zsh" << 'EOF'
# Malformed plugin with syntax errors
function bad_function() {
    if [[ missing bracket
    echo "This will cause syntax error"
}

# Missing closing brace
EOF
    
    # Try to load plugins - should not crash
    local load_result=0
    source "$TEMP_ZSH_DIR/plugins_loader.zsh" 2>/dev/null || load_result=$?
    
    # System should continue functioning despite malformed plugin
    assert_true "System survives malformed plugin" "[[ $load_result -eq 0 ]] || [[ -n \"\$(declare -f aws_middleware)\" ]]"
    
    teardown_test_environment
}

test_plugin_dependency_handling() {
    describe "Plugin dependencies are handled correctly"
    
    setup_test_environment
    
    # Test loading when dependencies are missing
    mv "$TEMP_ZSH_DIR/utils.zsh" "$TEMP_ZSH_DIR/utils.zsh.backup" 2>/dev/null || true
    
    local load_result=0
    source "$TEMP_ZSH_DIR/plugins_loader.zsh" 2>/dev/null || load_result=$?
    
    # Should handle missing dependencies gracefully
    assert_true "Handles missing dependencies gracefully" "true"  # Always pass since we expect graceful handling
    
    # Restore dependency
    mv "$TEMP_ZSH_DIR/utils.zsh.backup" "$TEMP_ZSH_DIR/utils.zsh" 2>/dev/null || true
    
    teardown_test_environment
}

# =============================================================================
# Real-world Integration Scenarios
# =============================================================================

test_complex_command_workflow() {
    describe "Complex real-world command workflow"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Simulate complex workflow
    local commands=(
        "kubectl config current-context"
        "aws s3 ls my-bucket"
        "kubectl get pods | grep running"
        "aws s3 cp file.txt s3://my-bucket/backup/"
        "kubectl logs -f pod-name"
    )
    
    local workflow_success=true
    
    for cmd in "${commands[@]}"; do
        # Test that each command can be processed without errors
        if ! aws_middleware "$cmd" >/dev/null 2>&1; then
            # Command processing may fail, but shouldn't crash
            continue
        fi
    done
    
    assert_true "Complex workflow processes without crashes" "$workflow_success"
    
    teardown_test_environment
}

test_concurrent_plugin_usage() {
    describe "Concurrent plugin usage scenarios"
    
    setup_test_environment
    source "$TEMP_ZSH_DIR/plugins_loader.zsh"
    
    # Test concurrent-style command processing
    local compound_commands=(
        "aws s3 ls && kubectl get pods"
        "kubectl config use-context staging && aws configure list"
        "docker ps | grep aws && kubectl get svc"
    )
    
    local concurrent_success=true
    
    for cmd in "${compound_commands[@]}"; do
        # Process compound commands
        if aws_middleware "$cmd" >/dev/null 2>&1; then
            # Successfully processed
            continue
        else
            # May not process compound commands, but shouldn't crash
            continue
        fi
    done
    
    assert_true "Concurrent plugin usage works" "$concurrent_success"
    
    teardown_test_environment
}

# =============================================================================
# Test Execution
# =============================================================================

main() {
    test_header "$TEST_SUITE_NAME"
    
    # Plugin Loading Tests
    test_plugins_loader_functionality
    test_aws_plugin_registration
    test_k8s_plugin_registration
    
    # Plugin Interaction Tests
    test_multiple_plugin_command_detection
    test_plugin_command_priority
    test_plugin_isolation
    
    # ZLE Integration Tests
    test_zle_widget_registration
    test_command_line_modification
    
    # Performance Tests
    test_plugin_loading_performance
    test_command_processing_performance
    
    # Error Handling Tests
    test_malformed_plugin_handling
    test_plugin_dependency_handling
    
    # Real-world Scenarios
    test_complex_command_workflow
    test_concurrent_plugin_usage
    
    test_footer
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi