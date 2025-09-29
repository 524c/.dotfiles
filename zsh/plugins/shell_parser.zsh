# Generic Shell Command Parser & AST Engine
# High-performance, reusable shell syntax parser for command detection and processing
# Supports any command type with configurable patterns and handlers

# Ensure debug function is available
if ! declare -f debug >/dev/null 2>&1 && ! typeset -f debug >/dev/null 2>&1; then
  debug() { [[ -n "$AWS_MIDDLEWARE_DEBUG" || -n "$SHELL_PARSER_DEBUG" ]] && echo "[parser][debug] $*" >&2; }
fi

# =============================================================================
# CORE SHELL PARSER - Generic shell syntax understanding
# =============================================================================

# Performance cache for parsed results
declare -A SHELL_PARSER_CACHE 2>/dev/null || typeset -A SHELL_PARSER_CACHE
SHELL_PARSER_CACHE[max_size]=200
SHELL_PARSER_CACHE[current_size]=0

# Parser performance statistics
declare -A PARSER_PERF_STATS 2>/dev/null || typeset -A PARSER_PERF_STATS
PARSER_PERF_STATS[l1_rejections]=0
PARSER_PERF_STATS[l2_detections]=0
PARSER_PERF_STATS[l3_parses]=0
PARSER_PERF_STATS[cache_hits]=0

# Shell AST node types
declare -A AST_NODE_TYPES 2>/dev/null || typeset -A AST_NODE_TYPES
AST_NODE_TYPES[SIMPLE_COMMAND]="simple"
AST_NODE_TYPES[COMMAND_SUBSTITUTION]="subst"
AST_NODE_TYPES[PIPE_SEQUENCE]="pipe"  
AST_NODE_TYPES[LOGICAL_SEQUENCE]="logical"
AST_NODE_TYPES[ASSIGNMENT]="assign"

# Generic shell command detection with configurable patterns
# Usage: detect_shell_commands "command line" "pattern1" "pattern2" ...
# Returns: array of command contexts found
detect_shell_commands() {
  local input="$1"
  shift
  local -a target_patterns=("$@")
  local cache_key="${input:0:50}:${target_patterns[*]:0:20}"
  
  # Check cache first
  if [[ -n "${SHELL_PARSER_CACHE[$cache_key]}" ]]; then
    ((PARSER_PERF_STATS[cache_hits]++))
    [[ "${SHELL_PARSER_CACHE[$cache_key]}" != "NONE" ]] && echo "${SHELL_PARSER_CACHE[$cache_key]}"
    return 0
  fi
  
  # Layer 1: Ultra-fast rejection
  if _shell_quick_reject "$input" "${target_patterns[@]}"; then
    _cache_parser_result "$cache_key" "NONE"
    return 1
  fi
  
  # Layer 2: Fast pattern detection  
  local result
  if result=$(_shell_fast_detect "$input" "${target_patterns[@]}"); then
    _cache_parser_result "$cache_key" "$result"
    echo "$result"
    return 0
  fi
  
  # Layer 3: Full AST parsing (rare cases)
  if result=$(_shell_full_parse "$input" "${target_patterns[@]}"); then
    _cache_parser_result "$cache_key" "$result" 
    echo "$result"
    return 0
  fi
  
  # No target commands found
  _cache_parser_result "$cache_key" "NONE"
  return 1
}

# Layer 1: Ultra-fast rejection for any command patterns
_shell_quick_reject() {
  local input="$1"
  shift
  local -a patterns=("$@")
  local pattern
  
  # Check if input contains any target patterns
  local has_target_pattern=0
  for pattern in "${patterns[@]}"; do
    [[ "$input" == *"$pattern"* ]] && { has_target_pattern=1; break; }
  done
  
  [[ $has_target_pattern -eq 0 ]] && {
    ((PARSER_PERF_STATS[l1_rejections]++))
    return 0
  }
  
  # Quick rejection for obvious non-command cases
  case "$input" in
    # Variable assignments (unless they contain command execution)
    *"="*)
      local contains_execution=0
      for pattern in "${patterns[@]}"; do
        [[ "$input" == *"\$($pattern"* || "$input" == *"\`$pattern"* || "$input" == *" $pattern "* || "$input" == "$pattern "* ]] && {
          contains_execution=1
          break
        }
      done
      [[ $contains_execution -eq 0 ]] && {
        ((PARSER_PERF_STATS[l1_rejections]++))
        return 0
      }
      ;;
    # Search/grep commands  
    "grep "*|"find "*|"cat "*|"less "*|"more "*)
      ((PARSER_PERF_STATS[l1_rejections]++))
      return 0
      ;;
  esac
  
  # Passed quick rejection
  return 1
}

# Layer 2: Fast single-pass pattern detection
_shell_fast_detect() {
  local input="$1"
  shift
  local -a patterns=("$@")
  local -a command_contexts=()
  local pos=0 char
  local in_quotes=0 quote_char=""
  local commands_found=0
  
  ((PARSER_PERF_STATS[l2_detections]++))
  
  # Single-pass state machine parser
  while (( pos < ${#input} )); do
    char="${input:$pos:1}"
    
    case "$char" in
      '"'|"'")
        if (( !in_quotes )); then
          in_quotes=1
          quote_char="$char"
        elif [[ "$quote_char" == "$char" ]]; then
          in_quotes=0
          quote_char=""
        fi
        ;;
      '$')
        # Command substitution: $(command ...)
        if (( !in_quotes )) && [[ "${input:$((pos+1)):1}" == "(" ]]; then
          local subst_content
          local subst_end
           local subst_output
           if subst_output=$(_extract_command_substitution "$input" $((pos+2))); then
             local -a subst_parts=(${(f)subst_output})
             subst_content="${subst_parts[1]}"
             subst_end="${subst_parts[2]}"
            
            # Check if substitution contains target commands
            local pattern
            for pattern in "${patterns[@]}"; do
              if [[ "$subst_content" == "$pattern "* ]]; then
                command_contexts+=("SUBST:$pattern:$subst_content")
                commands_found=1
                break
              fi
            done
            
            pos=$subst_end
            continue
          fi
        fi
        ;;
      '`')
        # Backtick substitution: `command ...`
        if (( !in_quotes )); then
          local subst_content
          local subst_end
          local subst_output
          if subst_output=$(_extract_backtick_substitution "$input" $((pos+1))); then
            local -a subst_parts=(${(f)subst_output})
            subst_content="${subst_parts[1]}"
            subst_end="${subst_parts[2]}"
            
            # Check if substitution contains target commands
            local pattern  
            for pattern in "${patterns[@]}"; do
              if [[ "$subst_content" == "$pattern "* ]]; then
                command_contexts+=("SUBST:$pattern:$subst_content")
                commands_found=1
                break
              fi
            done
            
            pos=$subst_end
            continue
          fi
        fi
        ;;
      *)
        # Direct command detection
        if (( !in_quotes )); then
          local pattern
          for pattern in "${patterns[@]}"; do
            local pattern_len=${#pattern}
            if [[ "${input:$pos:$pattern_len}" == "$pattern" ]] &&
               [[ "${input:$((pos+pattern_len)):1}" == " " || $((pos+pattern_len)) -eq ${#input} ]]; then
              
              # Extract complete command segment
              local cmd_start=$pos
              local cmd_end=$(_find_command_end "$input" $pos)
              local cmd_segment="${input:$cmd_start:$((cmd_end-cmd_start))}"
              
              command_contexts+=("DIRECT:$pattern:$cmd_segment")
              commands_found=1
              pos=$cmd_end
              break
            fi
          done
        fi
        ;;
    esac
    ((pos++))
  done
  
  # Special case: Docker containers with AWS CLI
  if (( !commands_found )); then
    local pattern
    for pattern in "${patterns[@]}"; do
      # Check for docker run with AWS CLI image followed by AWS commands
      if [[ "$input" == *"docker run"* && "$input" == *"$pattern-cli"* ]]; then
        # Extract the part after aws-cli
        local after_cli="${input##*$pattern-cli}"
        # Check if it starts with AWS subcommands
        if [[ "$after_cli" =~ ^[[:space:]]+(s3|ec2|iam|lambda|cloudformation|ecs|eks|rds|dynamodb) ]]; then
          command_contexts+=("DOCKER:$pattern:$after_cli")
          commands_found=1
          break
        fi
      fi
    done
  fi
  
  # Return found commands
  if (( commands_found )); then
    printf '%s\n' "${command_contexts[@]}"
    return 0
  else
    return 1
  fi
}

# Layer 3: Full AST parsing for complex cases
_shell_full_parse() {
  local input="$1" 
  shift
  local -a patterns=("$@")
  
  ((PARSER_PERF_STATS[l3_parses]++))
  
  # Use tokenization as fallback
  local -a words
  words=(${(z)input}) 2>/dev/null || return 1
  
  local -a found_commands=()
  local pattern word_idx
  
  for word_idx in {1..${#words[@]}}; do
    for pattern in "${patterns[@]}"; do
      if [[ "${words[$word_idx]}" == "$pattern" ]]; then
        # Build command context from tokens
        local cmd_tokens=("${words[@]:$((word_idx-1))}")
        found_commands+=("TOKENIZED:$pattern:${cmd_tokens[*]}")
        break
      fi
    done
  done
  
  if (( ${#found_commands[@]} > 0 )); then
    printf '%s\n' "${found_commands[@]}"
    return 0
  fi
  
  return 1
}

# =============================================================================
# UTILITY FUNCTIONS - Command parsing helpers
# =============================================================================

# Extract command substitution content: $(...)
_extract_command_substitution() {
  local input="$1"
  local start_pos=$2
  local pos=$start_pos
  local paren_count=1
  local in_quotes=0
  local quote_char=""
  local content=""
  
  while (( pos < ${#input} && paren_count > 0 )); do
    local char="${input:$pos:1}"
    
    case "$char" in
      '"'|"'")
        if (( !in_quotes )); then
          in_quotes=1
          quote_char="$char"
        elif [[ "$quote_char" == "$char" ]]; then
          in_quotes=0
          quote_char=""
        fi
        ;;
      '(') (( !in_quotes )) && ((paren_count++)) ;;
      ')') (( !in_quotes )) && ((paren_count--)) ;;
    esac
    
    (( paren_count > 0 )) && content+="$char"
    ((pos++))
  done
  
  if (( paren_count == 0 )); then
    echo "$content"
    echo $pos
    return 0
  fi
  
  return 1
}

# Extract backtick substitution content: `...`
_extract_backtick_substitution() {
  local input="$1"
  local start_pos=$2
  local pos=$start_pos
  local content=""
  
  while (( pos < ${#input} )); do
    local char="${input:$pos:1}"
    if [[ "$char" == '`' ]]; then
      echo "$content"
      echo $((pos+1))
      return 0
    fi
    content+="$char"
    ((pos++))
  done
  
  return 1
}

# Find end of current command segment (pipe, &&, ||, ;)
_find_command_end() {
  local input="$1"
  local start_pos=$2
  local pos=$start_pos
  local in_quotes=0
  local quote_char=""
  
  while (( pos < ${#input} )); do
    local char="${input:$pos:1}"
    
    case "$char" in
      '"'|"'")
        if (( !in_quotes )); then
          in_quotes=1
          quote_char="$char"
        elif [[ "$quote_char" == "$char" ]]; then
          in_quotes=0
          quote_char=""
        fi
        ;;
      '|'|';')
        (( !in_quotes )) && { echo $pos; return; }
        ;;
      '&')
        if (( !in_quotes )) && [[ "${input:$((pos+1)):1}" == "&" ]]; then
          echo $pos; return
        fi
        ;;
    esac
    ((pos++))
  done
  
  echo ${#input}
}

# Cache management
_cache_parser_result() {
  local key="$1"
  local value="$2"
  
  # Simple cache eviction
  if (( SHELL_PARSER_CACHE[current_size] >= SHELL_PARSER_CACHE[max_size] )); then
    local -a keys=(${(k)SHELL_PARSER_CACHE})
    local half_size=$((${#keys[@]} / 2))
    for key in "${keys[@]:0:$half_size}"; do
      [[ "$key" != "max_size" && "$key" != "current_size" ]] && unset "SHELL_PARSER_CACHE[$key]"
    done
    SHELL_PARSER_CACHE[current_size]=$((${#keys[@]} - half_size))
  fi
  
  SHELL_PARSER_CACHE[$key]="$value"
  ((SHELL_PARSER_CACHE[current_size]++))
}

# =============================================================================
# COMMAND REGISTRY - Plugin system for different commands
# =============================================================================

# Command pattern registry
declare -A COMMAND_PATTERNS 2>/dev/null || typeset -A COMMAND_PATTERNS
declare -A COMMAND_HANDLERS 2>/dev/null || typeset -A COMMAND_HANDLERS

# Register a command pattern and handler
# Usage: register_command_handler "command_name" "pattern" "handler_function"
register_command_handler() {
  local name="$1"
  local pattern="$2" 
  local handler="$3"
  
  COMMAND_PATTERNS[$name]="$pattern"
  COMMAND_HANDLERS[$name]="$handler"
}

# Process detected commands using registered handlers
process_detected_commands() {
  local input="$1"
  local -a command_contexts=("${@:2}")
  local context context_type context_pattern context_cmd
  local handler result
  
  for context in "${command_contexts[@]}"; do
    # Parse context: TYPE:PATTERN:COMMAND
    context_type="${context%%:*}"
    local temp="${context#*:}"
    context_pattern="${temp%%:*}"
    context_cmd="${temp#*:}"
    
    # Find and execute handler
    local name
    for name in "${(k)COMMAND_PATTERNS[@]}"; do
      if [[ "${COMMAND_PATTERNS[$name]}" == "$context_pattern" ]]; then
        handler="${COMMAND_HANDLERS[$name]}"
        if [[ -n "$handler" ]] && typeset -f "$handler" >/dev/null; then
          result=$($handler "$input" "$context_type" "$context_cmd")
          [[ -n "$result" ]] && echo "$result" && return 0
        fi
        break
      fi
    done
  done
  
  return 1
}

# =============================================================================
# PERFORMANCE BENCHMARKING & TESTING
# =============================================================================

# Performance benchmark for the generic parser
benchmark_shell_parser() {
  local -a test_commands=(
    'ls -la'
    'git status' 
    'aws s3 ls bucket-name'
    'kubectl get pods'
    'docker run nginx'
    'VPC_ID=$(aws ec2 describe-instances)'
    'kubectl get pods | grep running'
    'export AWS_PROFILE=prod && aws s3 ls'
    'docker build . && kubectl apply -f k8s/'
    'RESULT=`kubectl get svc` && echo $RESULT'
  )
  
  local -a test_patterns=("aws" "kubectl" "docker")
  local cmd result
  local start_time end_time
  
  echo "Generic Shell Parser Performance Benchmark:" >&2
  echo "==========================================" >&2
  
  for cmd in "${test_commands[@]}"; do
    start_time=$EPOCHREALTIME
    result=$(detect_shell_commands "$cmd" "${test_patterns[@]}")
    end_time=$EPOCHREALTIME
    
    local duration=$(( (end_time - start_time) * 1000 ))
    
    printf "%.2fms: %s\n" "$duration" "$cmd" >&2
    [[ -n "$result" ]] && printf "  → %s\n" "$result" >&2
  done
  
  echo >&2
  echo "Performance Stats:" >&2
  echo "L1 Rejections: ${PARSER_PERF_STATS[l1_rejections]}" >&2
  echo "L2 Detections: ${PARSER_PERF_STATS[l2_detections]}" >&2
  echo "L3 Parses: ${PARSER_PERF_STATS[l3_parses]}" >&2
  echo "Cache Hits: ${PARSER_PERF_STATS[cache_hits]}" >&2
}

# Test the generic parser with multiple command types
test_generic_parser() {
  local -a test_cases=(
    'aws s3 ls bucket-name'
    'kubectl get pods --all-namespaces'
    'docker run -d nginx'
    'VPC_ID=$(aws ec2 describe-instances)'
    'kubectl get pods | grep -v Terminating'
    'export AWS_PROFILE=prod && aws s3 sync . s3://bucket'
    'docker build . && kubectl apply -f deployment.yaml'
    'NODES=`kubectl get nodes` && echo $NODES'
    'terraform plan && terraform apply'
    'export KUBECONFIG=/tmp/config'
  )
  
  echo "Testing Generic Shell Parser:" >&2
  echo "============================" >&2
  
  local test_case result
  for test_case in "${test_cases[@]}"; do
    echo >&2
    echo "Test: $test_case" >&2
    
    # Test individual patterns
    for pattern in "aws" "kubectl" "docker" "terraform"; do
      result=$(detect_shell_commands "$test_case" "$pattern")
      if [[ -n "$result" ]]; then
        echo "  ✅ $pattern: $result" >&2
      fi
    done
    
    # Test multiple patterns at once
    result=$(detect_shell_commands "$test_case" "aws" "kubectl" "docker")
    [[ -z "$result" ]] && echo "  ❌ No commands detected" >&2
  done
  
  echo >&2
}