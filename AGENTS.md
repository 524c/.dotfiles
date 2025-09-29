# Dotfiles Project

## Overview

A comprehensive macOS development environment setup with intelligent shell plugins and configuration management. This project provides automated installation and configuration of essential development tools with advanced shell enhancements.

## Architecture

### Core Components

#### 1. Installation System
- **Location**: `install.sh`
- **Purpose**: Automated macOS development environment setup
- **Features**: Tool detection, dependency management, configuration deployment

#### 2. Shell Configuration
- **Location**: `zsh/` directory
- **Purpose**: Advanced ZSH configuration with intelligent plugins
- **Features**: Plugin system, command middleware, environment management

#### 3. Application Configurations
- **Locations**: Individual application directories
- **Purpose**: Consistent configuration across development tools
- **Applications**: iTerm2, tmux, vim, starship prompt

### Key Features

#### Intelligent AWS CLI Enhancement

**Advanced Command Processing**
- **S3 URI Auto-correction**: Automatically adds `s3://` prefix to bucket references
- **Session Management**: Automatic AWS SSO session refresh and validation
- **Smart Filtering**: Prevents interference with non-AWS commands containing "aws"
- **Complex Command Support**: Works with pipes, compound statements, command substitution

**Smart Filtering Algorithm**
- **Pattern Matching**: Uses `aws* *aws*` pattern with three-layer validation
- **Variable Assignment Detection**: Skips `VAR_NAME=value-with-aws` assignments
- **Search Command Detection**: Ignores `grep "aws"` and similar search operations
- **AWS Command Position Detection**: Finds AWS commands anywhere in complex command lines

#### Plugin System Architecture

**Command Routing**
- **Pattern-Based Registration**: Plugins register with glob patterns for command interception
- **ZLE Integration**: Real-time command processing via Zsh Line Editor
- **Middleware Chain**: Extensible command processing pipeline
- **Debug Support**: Comprehensive logging with `AWS_MIDDLEWARE_DEBUG`

#### Environment Management

**Context-Aware Configuration**
- **Kubernetes Context Display**: Shows current K8s cluster in prompt
- **AWS Profile Integration**: Displays active AWS profile and region
- **Multi-Environment Support**: Seamless switching between development contexts

### File Structure

```
dotfiles/
├── install.sh                    # Main installation script
├── zsh/
│   ├── plugins/
│   │   ├── aws.zsh              # AWS CLI enhancement with smart filtering
│   │   ├── k8s_ctx_toggle.zsh   # Kubernetes context management
│   │   └── k8s_environment_validation.zsh
│   ├── plugins_loader.zsh       # Plugin system core
│   └── utils.zsh               # Common utilities
├── zshrc/.zshrc                # Main ZSH configuration
├── iterm2/iterm2_prefs.xml     # iTerm2 settings
├── tmux/.tmux.conf             # Tmux configuration
├── vim/.vimrc                  # Vim configuration
├── starship/starship.toml      # Starship prompt config
├── p10k/.p10k.zsh             # Powerlevel10k theme
└── ssh/ssh_config             # SSH client configuration
```

### Development Workflow

#### Installation Process

```bash
# Automated setup
bash -c "$(curl -fsSL https://raw.githubusercontent.com/524c/.dotfiles/main/install.sh)"

# Manual configuration (if needed)
./install.sh
```

#### Plugin Development

```bash
# Plugin registration pattern
plugin_register "plugin_name" "command_pattern"

# Example: AWS plugin registration
plugin_register "aws_middleware" "aws* *aws*"
```

#### AWS Enhanced Commands

```bash
# Auto-corrected S3 operations
aws s3 ls bucket-name              # → aws s3 ls s3://bucket-name
aws s3 cp file bucket/path         # → aws s3 cp file s3://bucket/path

# Complex command support
kubectl get pods | aws s3 cp - bucket/output.txt  # Works correctly
export ENV=prod && aws s3 sync ./dist bucket/     # Works correctly

# Smart filtering (ignored)
K8S_CLUSTER_NAME=prd.k8s.multpex.com.br          # Not intercepted
grep "aws" /var/log/system.log                    # Not intercepted
```

## Configuration

### Plugin System Configuration

**Command Pattern Registration**
```bash
# Pattern syntax: glob patterns for command matching
plugin_register "handler_function" "pattern1 pattern2"

# Examples
plugin_register "aws_middleware" "aws* *aws*"      # AWS commands
plugin_register "k8s_handler" "kubectl* k*"       # Kubernetes commands
```

**Middleware Development**
```bash
middleware_function() {
    local command="$1"

    # Smart filtering logic
    if [[ "$command" == *"="* && "$command" != *" aws "* ]]; then
        debug "skipping variable assignment: $command"
        return 0
    fi

    # Command processing logic
    # ... implementation
}
```

### AWS Configuration

**Environment Variables**
```bash
export AWS_PROFILE=your-profile
export AWS_MIDDLEWARE_DEBUG=1        # Enable debug logging
export AWS_DEFAULT_REGION=us-east-1
```

**Session Management**
```bash
# Automatic session handling
aws sso login --profile your-profile   # Auto-detected and cached
aws sts get-caller-identity            # Session validation
```

### Kubernetes Integration

**Context Management**
```bash
# Context switching with validation
kubectx staging                        # Switch context
kubectl config current-context        # Display current
```

**Environment Validation**
```bash
# Automatic cluster validation
source zsh/plugins/k8s_environment_validation.zsh
validate_k8s_environment              # Check cluster health
```

## Safety & Security Rules

### 🚨 Destructive Command Prevention

**CRITICAL: Avoid potentially destructive commands in all development and testing scenarios.**

#### Prohibited Operations
- **AWS Destructive Commands**: No `aws s3 rm`, `aws s3 rb`, `aws ec2 terminate-instances`, or similar deletion operations
- **Kubernetes Destructive Commands**: No `kubectl delete`, `kubectl destroy`, or resource removal operations
- **System File Operations**: No `rm -rf`, `sudo rm`, or filesystem destructive operations
- **Database Operations**: No `DROP`, `DELETE FROM`, `TRUNCATE`, or data destruction commands

#### Safe Testing Alternatives
- **Local Testing**: Use `kind` (Kubernetes in Docker) for K8s testing instead of real clusters
- **Mock Services**: Use local mocks, stubs, or containerized versions of cloud services
- **Read-Only Operations**: Prefer `get`, `list`, `describe`, `show` commands for validation
- **Dry-Run Mode**: Use `--dry-run`, `--simulate`, or equivalent flags when available

#### Implementation Requirements
```bash
# ✅ SAFE: Read-only operations
kubectl get pods
aws s3 ls s3://bucket-name
docker ps

# ✅ SAFE: Local testing with kind
kind create cluster --name test-cluster
kubectl --context kind-test-cluster apply -f test-manifest.yaml

# ❌ FORBIDDEN: Destructive operations
kubectl delete namespace production    # NEVER
aws s3 rm s3://production-bucket --recursive    # NEVER
sudo rm -rf /important/directory    # NEVER
```

#### Environment Protection
- **Production Isolation**: Never execute commands against production environments
- **Context Validation**: Always verify cluster/environment context before any operations
- **Confirmation Prompts**: Implement explicit confirmation for any potentially destructive operations
- **Audit Logging**: Log all commands that could impact infrastructure or data

## Best Practices

### Plugin Development

1. **Pattern Specificity**: Use specific patterns to avoid false matches
2. **Smart Filtering**: Implement filtering logic for edge cases
3. **Debug Support**: Include comprehensive debug logging
4. **Error Handling**: Defensive programming for malformed input
5. **Performance**: Minimize overhead for non-matching commands
6. **🚨 Safety First**: Never implement destructive operations without explicit safeguards

### AWS Usage

1. **Profile Management**: Use AWS profiles for multi-account setups
2. **Session Validation**: Let middleware handle session expiration
3. **Debug Mode**: Enable debugging for troubleshooting
4. **Command Structure**: Leverage enhanced support for complex commands

### Shell Configuration

1. **Modular Design**: Keep configurations in separate files
2. **Environment Specific**: Use conditional loading for different environments
3. **Performance**: Optimize startup time with lazy loading
4. **Compatibility**: Maintain compatibility across ZSH versions

## Troubleshooting

### Common Issues

#### AWS Middleware Not Working

```bash
# Check registration
grep "plugin_register.*aws" zsh/plugins/aws.zsh

# Verify debug output
export AWS_MIDDLEWARE_DEBUG=1
aws s3 ls test-bucket

# Expected output: [debug] middleware invoked with command='aws s3 ls test-bucket'
```

#### Plugin System Issues

```bash
# Check plugin loading
source zsh/plugins_loader.zsh
echo "Plugins loaded: $(declare -F | grep plugin_)"

# Verify pattern matching
match_command_pattern "aws s3 ls" "aws*"  # Should return 0
```

#### False Positive Interceptions

```bash
# Test problematic command
export AWS_MIDDLEWARE_DEBUG=1
K8S_CLUSTER_NAME=prd.k8s.multpex.com.br

# Expected: [debug] skipping variable assignment containing 'aws'
```

### Debug Commands

```bash
# Plugin system status
declare -F | grep plugin_

# AWS middleware test
aws_middleware "test command"

# Pattern matching test
match_command_pattern "command" "pattern"
```

## Development

### Adding New Plugins

1. **Create Plugin File**: `zsh/plugins/new_plugin.zsh`
2. **Implement Handler**: Function with command processing logic
3. **Register Pattern**: Add `plugin_register` call
4. **Test Integration**: Verify with debug mode
5. **Update Loader**: Add to `plugins_loader.zsh` if needed

### Extending AWS Functionality

1. **Identify Use Case**: New AWS command patterns or behaviors
2. **Update Patterns**: Modify registration patterns if needed
3. **Enhance Logic**: Add processing rules to `aws_middleware`
4. **Test Coverage**: Create comprehensive test cases
5. **Document Changes**: Update configuration documentation

### Performance Optimization

1. **Profile Startup**: Use `zsh -xvs` to identify bottlenecks
2. **Lazy Loading**: Defer expensive operations until needed
3. **Pattern Efficiency**: Use specific patterns to reduce false matches
4. **Caching**: Cache expensive computations when possible

## Technical Details

### ZSH Plugin System

**Command Interception Flow**
```
User Input → ZLE Widget → Pattern Matching → Plugin Handler → Command Execution
```

**Pattern Matching Algorithm**
- Uses ZSH glob patterns for flexible command matching
- Supports multiple patterns per plugin registration
- Efficient early termination for non-matching commands

**Middleware Processing**
- Three-layer filtering for smart command detection
- Tokenization with defensive error handling
- Position-independent AWS command detection

### AWS Middleware Implementation

**Smart Filtering Layers**

1. **Variable Assignment Filter**
   ```bash
   # Skip: VAR=value-with-aws (unless contains actual AWS command)
   if [[ "$command" == *"="* && ... ]]; then return 0; fi
   ```

2. **Search Command Filter**
   ```bash
   # Skip: grep "aws" file.txt
   if [[ "$command" == "grep "*"aws"* ]]; then return 0; fi
   ```

3. **AWS Command Detection**
   ```bash
   # Find: aws anywhere in tokenized command
   for word in "${words[@]}"; do
     if [[ "$word" == "aws" ]]; then process_command; fi
   done
   ```

## Project Status

### Current Version
- **Version**: 1.0.0
- **Status**: Production Ready
- **Last Updated**: December 2024

### Recent Enhancements
- ✅ AWS Plugin Smart Filtering Implementation
- ✅ Comprehensive Test Coverage
- ✅ Complex Command Structure Support
- ✅ False Positive Prevention

### Roadmap
- [ ] Additional cloud provider support (GCP, Azure)
- [ ] Enhanced Kubernetes integration
- [ ] Performance optimization
- [ ] Plugin marketplace integration

---

**Maintainer**: Development Team
**License**: MIT
**Platform Support**: macOS (primary), Linux (experimental)

This dotfiles project provides a robust, intelligent development environment with advanced command processing capabilities and comprehensive configuration management.
