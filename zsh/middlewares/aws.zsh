# AWS Middleware - Validates AWS session and corrects S3 URIs

# AWS middleware - Session validation and S3 URI correction (instrumented v1.7)
aws_middleware() {
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][aws][debug] aws_middleware called with: '$1'" >&2
  local command="$1"
  aws_mw_debug "middleware invoked with command='$command'"

  # Split the line into tokens respecting quotes
  local -a words
  words=(${(z)command})
  aws_mw_debug "tokenized: ${words[*]}"

  # Ignore prefixed environment assignments (FOO=bar AWS_REGION=us-east-1 aws s3 ls)
  local first_word=""
  local aws_cmd_start=0
  for i in {1..${#words[@]}}; do
    if [[ "${words[i]}" == *"="* ]]; then
      continue
    else
      first_word="${words[i]}"
      aws_cmd_start=$i
      break
    fi
  done

  [[ "$first_word" == "aws" ]] || { aws_mw_debug "first word '$first_word' != aws, exiting"; return; }
  aws_mw_debug "detected aws command starting at index=$aws_cmd_start"

  # Check and fix S3 URI format
   local corrected_command
   if corrected_command=$(aws_fix_s3_uri words aws_cmd_start); then
     [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][aws] corrected S3 URI" >&2
     aws_mw_debug "corrected command: '$corrected_command'"
     # In ZLE context, modify BUFFER; otherwise return the command for wrapper
     if [[ -n "$BUFFER" ]]; then
       BUFFER="$corrected_command"
     fi
     # Always return the corrected command for wrapper function
     echo "$corrected_command"
     return 0
   fi
  aws_mw_debug "no URI correction applied"

  # S3 mb / rb guard: ensure we did not erroneously prepend anything
  if (( aws_cmd_start + 1 <= ${#words[@]} )) && [[ "${words[$((aws_cmd_start+1))]}" == "s3" ]]; then
    if (( aws_cmd_start + 2 <= ${#words[@]} )); then
      local _act="${words[$((aws_cmd_start+2))]}"
      if [[ "$_act" == "mb" || "$_act" == "rb" ]]; then
        # Sanity check: show tokens
        aws_mw_debug "sanity guard for action $_act tokens='${words[*]}'"
      fi
    fi
  fi

  # Invalid session -> refresh before executing real command
  if ! aws_session_valid; then
    echo "[commands-middleware][aws] expired session – refreshing..." >&2
    aws_mw_debug "session invalid triggering refresh"
    aws_refresh_session || {
      echo "[commands-middleware][aws] failed to refresh session" >&2
      aws_mw_debug "session refresh failed"
    }
  fi
}

# Check if AWS credentials are valid (with timestamp caching)
aws_session_valid() {
  local cache_file="/tmp/aws_session_cache_$(whoami)"
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
  if aws sts get-caller-identity &>/dev/null; then
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
  local cache_file="/tmp/aws_session_cache_$(whoami)"
  
  # Remove cache before refresh
  rm -f "$cache_file" 2>/dev/null
  
  # Simple session refresh - extend as needed
  if command -v aws-sso >/dev/null 2>&1; then
    aws-sso login
  elif [[ -n "$AWS_PROFILE" ]]; then
    aws sso login --profile "$AWS_PROFILE"
  else
    aws sso login
  fi
  
  # If refresh was successful, update cache
  if aws sts get-caller-identity &>/dev/null; then
    date +%s > "$cache_file"
  fi
}

# Fix S3 URI format in AWS commands - FIXED: rb command excluded from URI correction (instrumented v1.7)
# Debug logging: export AWS_MIDDLEWARE_DEBUG=1 to enable verbose output
aws_mw_debug() { [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && print -u2 "[commands-middleware][aws][debug] $*"; }

aws_fix_s3_uri() {
  local words_var=$1
  local aws_start=$2
  
  # Copy array by name reference
  local -a words=("${(@P)words_var}")
  local -a fixed_words=("${words[@]}")
  local changed=false

  aws_mw_debug "entered aws_fix_s3_uri; aws_start=$aws_start raw_command='${words[*]}'"
  
  # Check if this is an S3 command (zsh arrays are 1-indexed)
  if (( aws_start + 1 <= ${#words[@]} )) && [[ "${words[$((aws_start+1))]}" == "s3" ]]; then
    aws_mw_debug "detected s3 subcommand"
    # S3 commands that typically need URI correction
    if (( aws_start + 2 <= ${#words[@]} )); then
      local s3_action="${words[$((aws_start+2))]}"
      aws_mw_debug "s3_action=$s3_action"

      # NOTE: Previous assumption that mb/rb must not be modified was WRONG.
      # aws s3 mb|rb actually REQUIRE an s3:// URI. We now auto-prefix them.
      case "$s3_action" in
        mb|rb)
          aws_mw_debug "processing bucket create/delete action $s3_action"
          # mb / rb require bucket ARG as s3://bucket
          for i in $(seq $((aws_start + 3)) ${#words[@]}); do
            local arg="${words[i]}"
            aws_mw_debug "$s3_action arg index=$i value='$arg'"
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
              aws_mw_debug "added prefix to bucket '$arg' (stripped='$stripped') for $s3_action"
              changed=true
              break
            fi
          done
          ;;
        cp|mv|sync|ls)
          aws_mw_debug "processing action $s3_action"
          # Note: mb/rb handled separately above
          # Check arguments for bucket names that should be s3:// URIs
          for i in $(seq $((aws_start + 3)) ${#words[@]}); do
            local arg="${words[i]}"
            local prev_index=$((i-1))
            local prev="${words[prev_index]}"
            aws_mw_debug "arg index=$i value='$arg' prev='$prev'"
            
            # Skip if already has s3:// prefix or is a flag itself
            if [[ "$arg" =~ ^s3:// ]]; then aws_mw_debug "skip already prefixed"; continue; fi
            if [[ "$arg" =~ ^- ]]; then aws_mw_debug "skip flag"; continue; fi
            # Skip if this is the value of a preceding flag (e.g. --region us-east-1)
            if [[ "$prev" =~ ^- && "$prev" != *=* ]]; then aws_mw_debug "skip flag value for $prev"; continue; fi
            
            # Skip local filesystem paths (starts with ./ or /)
            if [[ "$arg" =~ ^\.?/ ]]; then aws_mw_debug "skip local path (starts with ./ or /)"; continue; fi
            
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
                aws_mw_debug "skip local file candidate (extension=$extension)"
                continue
              fi
            fi
            
            # Bare bucket
            if [[ "$stripped" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] && [[ ${#stripped} -ge 3 ]] && [[ ${#stripped} -le 63 ]]; then
              fixed_words[i]="s3://$stripped"
              aws_mw_debug "added prefix to bare bucket '$arg' (stripped='$stripped')"
              changed=true
            # bucket/path
            elif [[ "$stripped" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]/.+ ]]; then
              fixed_words[i]="s3://$stripped"
              aws_mw_debug "added prefix to bucket/path '$arg' (stripped='$stripped')"
              changed=true
            else
              aws_mw_debug "no match rules for '$arg'"
            fi
          done
          ;;
        rm)
          aws_mw_debug "processing action rm"
          # Special handling for 'rm' - add s3:// prefix only for bucket/path, not bare bucket names
          for i in $(seq $((aws_start + 3)) ${#words[@]}); do
            local arg="${words[i]}"
            aws_mw_debug "rm arg index=$i value='$arg'"
            
            # Skip if already has s3:// prefix or is a flag
            if [[ "$arg" =~ ^s3:// ]]; then aws_mw_debug "skip already prefixed"; continue; fi
            if [[ "$arg" =~ ^- ]]; then aws_mw_debug "skip flag"; continue; fi
            
            # Reordered logic for rm:
            # 1. Skip explicit filesystem paths starting with ./ or /
            # 2. If bucket/path pattern (contains slash) add prefix (even if object has extension)
            # 3. Apply local file heuristic ONLY when no slash present
            if [[ "$arg" =~ ^\.?/ ]]; then aws_mw_debug "skip path (starts with ./ or /)"; continue; fi

            # bucket/path pattern (must have slash and content after)
            if [[ "$arg" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]/.+ ]]; then
              fixed_words[i]="s3://$arg"
              aws_mw_debug "added prefix to rm target '$arg'"
              changed=true
              continue
            fi

            # Local file heuristic (only if no slash)
            if [[ "$arg" != */* ]]; then
              local extension="${arg##*.}"
              if [[ "$extension" != "$arg" ]] && [[ ${#extension} -ge 1 ]] && [[ ${#extension} -le 4 ]] && [[ "$extension" =~ ^[a-zA-Z]+$ ]]; then
                aws_mw_debug "skip local file (extension=$extension)"
                continue
              fi
            fi

            # At this point leave bare bucket unchanged (could be bucket delete intent)
            aws_mw_debug "rm leaving arg unchanged '$arg'"
            # Do NOT add s3:// for bare bucket names in 'rm' command (could be bucket deletion)
          done
          ;;
      esac
    fi
  fi
  
  if [[ "$changed" == "true" ]]; then
    # Return corrected command via stdout
    print -n "${fixed_words[*]}"
    aws_mw_debug "final corrected command='${fixed_words[*]}'"
    return 0
  fi
  aws_mw_debug "no changes applied"
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

# Register this middleware
[[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[DIAGNOSTIC] aws.zsh: Registering aws_middleware"
commands_middleware_register "aws_middleware"

# Also define an aws wrapper function for direct command interception
aws() {
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][aws][debug] aws wrapper called with: $*" >&2
  
  # Call middleware with the full command (prepend 'aws')
  local full_command="aws $*"
  local middleware_output
  if middleware_output=$(aws_middleware "$full_command"); then
    # If middleware returned a corrected command, execute it directly
    if [[ -n "$middleware_output" && "$middleware_output" != "$full_command" ]]; then
      # Replace 'aws' with full path to avoid function recursion
      local corrected_command="${middleware_output/#aws//opt/homebrew/bin/aws}"
      [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][aws][debug] executing corrected command: $corrected_command" >&2
      eval "$corrected_command"
      return
    fi
  fi
  
  # Execute original command if no correction needed
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][aws][debug] executing original command: /opt/homebrew/bin/aws $*" >&2
  /opt/homebrew/bin/aws "$@"
}