# AWS Middleware - Validates AWS session and corrects S3 URIs
# Configuration:
# - AWS_MIDDLEWARE_DEBUG=1: Enable debug logging

# AWS middleware - Session validation and S3 URI correction (v1.14 - Silent Visual Updates)
aws_middleware() {
  local command="$1"
  debug "middleware invoked with command='$command'"

  # SMART FILTERING: Skip commands that contain "aws" but are not AWS commands  
  # Skip variable assignments that contain "aws" in name or value (but not actual AWS commands)
  # Allow if contains actual AWS command patterns: " aws " or "aws " or "$(aws" or "`aws"
  if [[ "$command" == *"="* && "$command" != *" aws "* && "$command" != "aws "* && "$command" != *'$(aws'* && "$command" != *'`aws'* ]]; then
    debug "skipping variable assignment containing 'aws': $command"
    return 0
  fi
  
  # Skip grep/search commands that contain "aws" as search term
  if [[ "$command" == "grep "*"aws"* || "$command" == "find "*"aws"* || "$command" == "cat "*"aws"* ]]; then
    debug "skipping search command containing 'aws': $command"
    return 0
  fi

  # Split the line into tokens respecting quotes (defensive)
  local -a words
  { words=(${(z)command}) } 2>/dev/null || return 0
  (( ${#words[@]} )) || return 0
  debug "tokenized: ${words[*]}"

  # Find AWS command anywhere in the line (support for pipes, &&, etc.)
  # Enhanced: Also detect AWS commands inside command substitutions
  local aws_cmd_start=0
  local aws_in_substitution=false
  local substitution_token=""
  
  for i in {1..${#words[@]}}; do
    local word="${words[i]}"
    
    # Direct AWS command
    if [[ "$word" == "aws" ]]; then
      aws_cmd_start=$i
      break
    fi
    
    # AWS command inside command substitution: $(aws ...) or `aws ...`
    if [[ "$word" == *'$(aws'* || "$word" == *'`aws'* ]]; then
      aws_cmd_start=$i
      aws_in_substitution=true
      substitution_token="$word"
      debug "detected aws command in substitution: $word"
      break
    fi
  done

  [[ $aws_cmd_start -gt 0 ]] || { debug "no 'aws' command found in: ${words[*]}"; return; }
  debug "detected aws command starting at index=$aws_cmd_start"

  # Detect and handle aws sso logout command - clear all caches
  if (( aws_cmd_start + 2 <= ${#words[@]} )) && 
     [[ "${words[$((aws_cmd_start+1))]}" == "sso" ]] && 
     [[ "${words[$((aws_cmd_start+2))]}" == "logout" ]]; then
    echo "[AWS] Executing SSO logout and clearing all session caches..." >&2
    
    # Temporarily disable Starship AWS module to prevent auto-login (if Starship is present)
    local original_starship_config=""
    local starship_disabled=false
    
    # Check if Starship is available and configured
    if command -v starship >/dev/null 2>&1 && [[ -n "$STARSHIP_CONFIG" || -f "$HOME/.config/starship.toml" ]]; then
      debug "Starship detected - temporarily disabling AWS module during logout"
      original_starship_config="$STARSHIP_CONFIG"
      export STARSHIP_CONFIG=/dev/null
      starship_disabled=true
    else
      debug "Starship not detected or not configured - proceeding with standard logout"
    fi
    
    # Execute logout first
    /opt/homebrew/bin/aws "${words[@]:$aws_cmd_start}"
    local logout_result=$?
    
    # Clear all profile-specific caches after logout completes
    local cache_base="/tmp/aws_session_cache_$(whoami)_"
    local cleared_count=0
    
    # Use a more reliable method to find and remove cache files
    for cache_file in /tmp/aws_session_cache_$(whoami)_*; do
      if [[ -f "$cache_file" ]]; then
        rm -f "$cache_file"
        ((cleared_count++))
        debug "cleared cache: $cache_file"
      fi
    done
    
    if (( cleared_count > 0 )); then
      echo "[commands-middleware][aws] cleared $cleared_count session cache(s) after logout" >&2
    else
      debug "no session caches found to clear"
    fi
    
    # Restore Starship config only if we disabled it
    if [[ "$starship_disabled" == true ]]; then
      if [[ -n "$original_starship_config" ]]; then
        export STARSHIP_CONFIG="$original_starship_config"
        debug "Starship config restored to: $STARSHIP_CONFIG"
      else
        unset STARSHIP_CONFIG
        debug "Starship config unset (was not originally set)"
      fi
    fi
    
    return $logout_result
  fi

  # ALWAYS check session validity first, regardless of URI correction
  local session_refreshed=false
  if ! aws_session_valid; then
    echo "[commands-middleware][aws] expired session – refreshing..." >&2
    debug "session invalid triggering refresh"
    if aws_refresh_session; then
      session_refreshed=true
      debug "session refresh successful"
    else
      echo "[commands-middleware][aws] failed to refresh session" >&2
      debug "session refresh failed"
      return 1
    fi
  fi

   # Check and fix S3 URI format
   local corrected_command
   
   # Handle command substitution case separately
   if [[ "$aws_in_substitution" == true ]]; then
     debug "AWS command in substitution detected, applying substitution-aware processing"
     
     # For command substitutions, we primarily ensure session validity (already done above)
     # S3 URI correction for substitutions would need special handling, but it's rare
     # Most substitutions are for describe/get operations, not S3 operations
     
     # For EC2 describe-instances and similar, no correction needed
     if [[ "$substitution_token" == *"ec2"* || "$substitution_token" == *"sts"* || "$substitution_token" == *"iam"* ]]; then
       debug "AWS service command in substitution (ec2/sts/iam) - no correction needed"
       return 0
     fi
     
      # For S3 commands in substitution, attempt correction (advanced case)
      if [[ "$substitution_token" == *"s3"* ]]; then
        debug "S3 command in substitution detected - attempting correction"
        
        # Use regex-based approach for more reliable extraction
        local aws_part corrected_substitution
        
        # Handle $(...) syntax
        if [[ "$substitution_token" =~ '\$\((.+)\)' ]]; then
          aws_part="$match[1]"
          local -a temp_words=(${(z)aws_part})
          local temp_corrected
          if temp_corrected=$(aws_fix_s3_uri temp_words 1 2>/dev/null); then
            corrected_substitution="\$(${temp_corrected})"
            echo "${command/$substitution_token/$corrected_substitution}"
            return 0
          fi
        # Handle `...` syntax  
        elif [[ "$substitution_token" =~ '`(.+)`' ]]; then
          aws_part="$match[1]"
          local -a temp_words=(${(z)aws_part})
          local temp_corrected
          if temp_corrected=$(aws_fix_s3_uri temp_words 1 2>/dev/null); then
            corrected_substitution="\`${temp_corrected}\`"
            echo "${command/$substitution_token/$corrected_substitution}"
            return 0
          fi
        fi
      fi
     
     # No correction applied to substitution
     return 0
   fi
   
   # Standard case: AWS command as separate tokens
   # Only attempt URI correction for commands that actually supply bucket/objects
   if corrected_command=$(aws_fix_s3_uri words $aws_cmd_start 2>/dev/null); then
     debug "corrected S3 URI - command: '$corrected_command'"
    
    # Return the corrected command - buffer update will be handled by main system
    echo "$corrected_command"
    return 0
   fi
   debug "no URI correction applied"

  # S3 mb / rb guard: ensure we did not erroneously prepend anything
  if (( aws_cmd_start + 1 <= ${#words[@]} )) && [[ "${words[$((aws_cmd_start+1))]}" == "s3" ]]; then
    if (( aws_cmd_start + 2 <= ${#words[@]} )); then
      local _act="${words[$((aws_cmd_start+2))]}"
      if [[ "$_act" == "mb" || "$_act" == "rb" ]]; then
        # Sanity check: show tokens
        debug "sanity guard for action $_act tokens='${words[*]}'"
      fi
    fi
  fi
  
  # No correction needed, do not echo original (noise reduction)
  debug "no correction needed; not echoing original"
  return 0
}

# Check if AWS credentials are valid (with timestamp caching)
aws_session_valid() {
  local profile_suffix="${AWS_PROFILE:-default}"
  local cache_file="/tmp/aws_session_cache_$(whoami)_${profile_suffix}"
  local cache_duration=3600  # 1 hour in seconds

  # Check if cache file exists and is recent
  if [[ -f "$cache_file" ]]; then
    local cache_timestamp=$(cat "$cache_file" 2>/dev/null)
    local current_timestamp=$(date +%s)

    # If cache is valid (within duration), assume session is valid
    if [[ -n "$cache_timestamp" ]] && (( current_timestamp - cache_timestamp < cache_duration )); then
      return 0
    fi
  fi

  # Cache expired or doesn't exist - check actual AWS session
  if /opt/homebrew/bin/aws sts get-caller-identity &>/dev/null; then
    # Session is valid - update cache
    date +%s > "$cache_file"
    return 0
  else
    # Session invalid - remove cache
    rm -f "$cache_file" 2>/dev/null
    return 1
  fi
}

# Refresh AWS session
aws_refresh_session() {
  local profile_suffix="${AWS_PROFILE:-default}"
  local cache_file="/tmp/aws_session_cache_$(whoami)_${profile_suffix}"

  # Remove cache before refresh
  rm -f "$cache_file" 2>/dev/null

  # Simple session refresh - extend as needed
  # CRITICAL FIX: Redirect output to stderr to prevent eval of SSO messages
  if command -v aws-sso >/dev/null 2>&1; then
    aws-sso login >&2
  elif [[ -n "$AWS_PROFILE" ]]; then
    /opt/homebrew/bin/aws sso login --profile "$AWS_PROFILE" >&2
  else
    /opt/homebrew/bin/aws sso login >&2
  fi

  # If refresh was successful, update cache
  if /opt/homebrew/bin/aws sts get-caller-identity &>/dev/null; then
    date +%s > "$cache_file"
  fi
}

# Fix S3 URI format in AWS commands - FIXED: Session validation always runs + SSO output redirect + UX improvements (instrumented v1.12)
# Debug logging now handled by utils.zsh debug() function

aws_fix_s3_uri() {
  # Defensive: require passed array name and start index
  if (( $# < 2 )); then
    return 1
  fi
  # Validate referenced array has content
  local __arr_size
  eval '__arr_size=${#'$1'[@]}'
  (( __arr_size > 0 )) || return 1
  local words_var=$1
  local aws_start=$2

  # Copy array by name reference
  local -a words=("${(@P)words_var}")
  local -a fixed_words=("${words[@]}")
  local changed=false

  debug "entered aws_fix_s3_uri; aws_start=$aws_start raw_command='${words[*]}'"

  # Check if this is an S3 command (zsh arrays are 1-indexed)
  if (( aws_start + 1 <= ${#words[@]} )) && [[ "${words[$((aws_start+1))]}" == "s3" ]]; then
    debug "detected s3 subcommand"
    # S3 commands that typically need URI correction
    if (( aws_start + 2 <= ${#words[@]} )); then
      local s3_action="${words[$((aws_start+2))]}"
      debug "s3_action=$s3_action"

      # NOTE: Previous assumption that mb/rb must not be modified was WRONG.
      # aws s3 mb|rb actually REQUIRE an s3:// URI. We now auto-prefix them.
      case "$s3_action" in
        mb|rb)
          debug "processing bucket create/delete action $s3_action"
          # mb / rb require bucket ARG as s3://bucket
          for i in $(seq $((aws_start + 3)) ${#words[@]}); do
            local arg="${words[i]}"
            debug "$s3_action arg index=$i value='$arg'"
            [[ "$arg" =~ ^- ]] && continue
            [[ "$arg" =~ ^s3:// ]] && continue
            # Strip matching surrounding quotes if present
            local stripped="$arg"
            if [[ "$arg" == \"*\" && "$arg" == *\" ]]; then
              stripped="${arg:1:${#arg}-2}"
            elif [[ "$arg" == '"'*'"' && "$arg" == *'"' ]]; then
              stripped="${arg:1:${#arg}-2}"
            elif [[ "$arg" == "'*'" && "$arg" == *"'" ]]; then
              stripped="${arg:1:${#arg}-2}"
            fi
            # bucket names only (no slashes) using stripped value
            if [[ "$stripped" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] && [[ ${#stripped} -ge 3 ]] && [[ ${#stripped} -le 63 ]]; then
              fixed_words[i]="s3://$stripped"
              debug "added prefix to bucket '$arg' (stripped='$stripped') for $s3_action"
              changed=true
              break
            fi
          done
          ;;
        cp|mv|sync|ls)
          debug "processing action $s3_action"
          # Note: mb/rb handled separately above
          # Check arguments for bucket names that should be s3:// URIs
          for i in $(seq $((aws_start + 3)) ${#words[@]}); do
            local arg="${words[i]}"
            local prev_index=$((i-1))
            local prev="${words[prev_index]}"
            debug "arg index=$i value='$arg' prev='$prev'"

            # Skip if already has s3:// prefix or is a flag itself
            if [[ "$arg" =~ ^s3:// ]]; then debug "skip already prefixed"; continue; fi
            if [[ "$arg" =~ ^- ]]; then debug "skip flag"; continue; fi
            # Skip if this is the value of a preceding flag (e.g. --region us-east-1)
            if [[ "$prev" =~ ^- && "$prev" != *=* ]]; then debug "skip flag value for $prev"; continue; fi

            # Skip local filesystem paths (starts with ./ or /)
            if [[ "$arg" =~ ^\.?/ ]]; then debug "skip local path (starts with ./ or /)"; continue; fi

            # Handle quoted buckets/paths
            local stripped="$arg" had_quotes=0
            if [[ ( "$arg" == \"*\" && "$arg" == *\" ) || ( "$arg" == "'*'" && "$arg" == *"'*'" ) ]]; then
              stripped="${arg:1:${#arg}-2}"
              had_quotes=1
            fi

            # Local file heuristic ONLY if no slash present (bucket/path should still be eligible)
            if [[ "$stripped" != */* ]]; then
              local extension="${stripped##*.}"
              if [[ "$extension" != "$stripped" ]] && [[ ${#extension} -ge 1 ]] && [[ ${#extension} -le 4 ]] && [[ "$extension" =~ ^[a-zA-Z]+$ ]]; then
                debug "skip local file candidate (extension=$extension)"
                continue
              fi
            fi

            # Bare bucket
            if [[ "$stripped" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] && [[ ${#stripped} -ge 3 ]] && [[ ${#stripped} -le 63 ]]; then
              fixed_words[i]="s3://$stripped"
              debug "added prefix to bare bucket '$arg' (stripped='$stripped')"
              changed=true
            # bucket/path
            elif [[ "$stripped" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]/.+ ]]; then
              fixed_words[i]="s3://$stripped"
              debug "added prefix to bucket/path '$arg' (stripped='$stripped')"
              changed=true
            else
              debug "no match rules for '$arg'"
            fi
          done
          ;;
        rm)
          debug "processing action rm"
          # Special handling for 'rm' - add s3:// prefix only for bucket/path, not bare bucket names
          for i in $(seq $((aws_start + 3)) ${#words[@]}); do
            local arg="${words[i]}"
            debug "rm arg index=$i value='$arg'"

            # Skip if already has s3:// prefix or is a flag
            if [[ "$arg" =~ ^s3:// ]]; then debug "skip already prefixed"; continue; fi
            if [[ "$arg" =~ ^- ]]; then debug "skip flag"; continue; fi

            # Reordered logic for rm:
            # 1. Skip explicit filesystem paths starting with ./ or /
            # 2. If bucket/path pattern (contains slash) add prefix (even if object has extension)
            # 3. Apply local file heuristic ONLY when no slash present
            if [[ "$arg" =~ ^\.?/ ]]; then debug "skip path (starts with ./ or /)"; continue; fi

            # bucket/path pattern (must have slash and content after)
            if [[ "$arg" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]/.+ ]]; then
              fixed_words[i]="s3://$arg"
              debug "added prefix to rm target '$arg'"
              changed=true
              continue
            fi

            # Local file heuristic (only if no slash)
            if [[ "$arg" != */* ]]; then
              local extension="${arg##*.}"
              if [[ "$extension" != "$arg" ]] && [[ ${#extension} -ge 1 ]] && [[ ${#extension} -le 4 ]] && [[ "$extension" =~ ^[a-zA-Z]+$ ]]; then
                debug "skip local file (extension=$extension)"
                continue
              fi
            fi

            # At this point leave bare bucket unchanged (could be bucket delete intent)
            debug "rm leaving arg unchanged '$arg'"
            # Do NOT add s3:// for bare bucket names in 'rm' command (could be bucket deletion)
          done
          ;;
      esac
    fi
  fi

  if [[ "$changed" == "true" ]]; then
    # Return corrected command via stdout
    print -n "${fixed_words[*]}"
    debug "final corrected command='${fixed_words[*]}'"
    return 0
  fi
  debug "no changes applied"
  return 1
}

# Lightweight self-test harness (no AWS calls)
# Usage: aws_middleware_selftest [-q]
#   -q : quiet (only summary + failures)
# Exits 0 on success, 1 on any failure.
aws_middleware_selftest() {
  local quiet=0
  [[ "$1" == "-q" ]] && quiet=1
  local -a tests=(
    # Basic mb/rb/ls/cp/rm existing matrix
    "aws s3 mb test-bucket-example || aws s3 mb s3://test-bucket-example"
    "aws s3 rb test-bucket-example --force || aws s3 rb s3://test-bucket-example --force"
    "aws s3 ls test-bucket-example || aws s3 ls s3://test-bucket-example"
    "aws s3 cp file.txt test-bucket-example || aws s3 cp file.txt s3://test-bucket-example"
    "aws s3 cp file.txt test-bucket-example/path/ || aws s3 cp file.txt s3://test-bucket-example/path/"
    "aws s3 rm test-bucket-example/object.txt || aws s3 rm s3://test-bucket-example/object.txt"
    "aws s3 rm test-bucket-example || aws s3 rm test-bucket-example"
    "aws s3 ls --region us-east-1 test-bucket-example || aws s3 ls --region us-east-1 s3://test-bucket-example"
    "aws s3 mb s3://already-prefixed || aws s3 mb s3://already-prefixed"
    # Extended tests
    "aws s3 ls --profile foo --region us-east-1 test-bucket-example || aws s3 ls --profile foo --region us-east-1 s3://test-bucket-example"
    "aws s3 ls \"test-bucket-example\" || aws s3 ls s3://test-bucket-example"  # quoted bucket
    "aws s3 cp file.txt test-bucket-example/path.to/object.json || aws s3 cp file.txt s3://test-bucket-example/path.to/object.json"
    "aws s3 sync ./localdir test-bucket-example/prefix/ || aws s3 sync ./localdir s3://test-bucket-example/prefix/"
    "aws s3 mv file.txt test-bucket-example/dir/file.txt || aws s3 mv file.txt s3://test-bucket-example/dir/file.txt"
  )
  local passed=0 failed=0 idx=0
  for case in "${tests[@]}"; do
    idx=$((idx+1))
    local orig expected
    orig="${case%%||*}"; orig="${orig%% }"; orig="${orig## }"
    expected="${case##*||}"; expected="${expected%% }"; expected="${expected## }"

    # Tokenize like middleware
    local -a words
    words=(${(z)orig})
    local aws_cmd_start=0
    for i in {1..${#words[@]}}; do
      if [[ "${words[i]}" == *"="* ]]; then
        continue
      else
        if [[ "${words[i]}" == "aws" ]]; then
          aws_cmd_start=$i
        fi
        break
      fi
    done

    local corrected=""
    local actual="$orig"
    if corrected=$(aws_fix_s3_uri words $aws_cmd_start); then
      actual="$corrected"
    fi

    if [[ "$actual" == "$expected" ]]; then
      passed=$((passed+1))
      (( quiet == 0 )) && print -u2 "[selftest][PASS] $orig -> $actual"
    else
      failed=$((failed+1))
      print -u2 "[selftest][FAIL] $orig -> $actual (expected: $expected)"
    fi
  done
  local total=$((passed+failed))
  if (( failed == 0 )); then
    print -u2 "[selftest] SUCCESS: $passed/$total passed"
    return 0
  else
    print -u2 "[selftest] FAILURES: $failed of $total (passed=$passed)"
    return 1
  fi
}

# Function to check if command is a delete operation
is_delete_command() {
  local cmd="$1"
  local -a words
  words=(${(z)cmd})
  local aws_start=0
  for i in {1..${#words[@]}}; do
    if [[ "${words[i]}" == *"="* ]]; then
      continue
    else
      if [[ "${words[i]}" == "aws" || "${words[i]}" == "/opt/homebrew/bin/aws" ]]; then
        aws_start=$i
        break
      fi
    fi
  done
  if (( aws_start > 0 && aws_start + 2 <= ${#words[@]} )); then
    if [[ "${words[$((aws_start+1))]}" == "s3" && ("${words[$((aws_start+2))]}" == "rm" || "${words[$((aws_start+2))]}" == "rb") ]]; then
      return 0
    fi
  fi
  return 1
}

# Register with the new plugin system - AWS command patterns
debug "aws.zsh: Registering aws_middleware with routing patterns"
plugin_register "aws_middleware" "aws* *aws s3* *aws ec2*"

# AWS wrapper function disabled - using ZLE integration for visual buffer updates
# aws() {
#   [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][aws][debug] aws wrapper called with: $*" >&2
#
#   # Call middleware with the full command (prepend 'aws')
#   local full_command="aws $*"
#   local middleware_output
#   if middleware_output=$(aws_middleware "$full_command"); then
#     # If middleware returned a corrected command, execute it directly
#     if [[ -n "$middleware_output" && "$middleware_output" != "$full_command" ]]; then
#       # Replace 'aws' with full path to avoid function recursion
#       local corrected_command="${middleware_output/#aws//opt/homebrew/bin/aws}"
#       exec_cmd="$corrected_command"
#     else
#       exec_cmd="/opt/homebrew/bin/aws $@"
#     fi
#   else
#     exec_cmd="/opt/homebrew/bin/aws $@"
#   fi

#   # Check for delete operations and prompt for confirmation
#   if is_delete_command "$exec_cmd"; then
#     echo -n "Are you sure you want to delete? (y/N) "
#     read response
#     if [[ "$response" != "y" && "$response" != "Y" ]]; then
#       return 1
#     fi
#   fi
#
#   # Execute the command
#   [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][aws][debug] executing command: $exec_cmd" >&2
#   eval "$exec_cmd"
# }

# Ensure AWS wrapper function is not active (force use of ZLE integration)
unfunction aws 2>/dev/null || true
