#!/usr/bin/env zsh

# AWS Middleware - Validates AWS session before executing AWS commands

aws_middleware() {
  local command="$1"

  # Split the line into tokens respecting quotes
  local -a words
  words=(${(z)command})

  # Ignore prefixed environment assignments (FOO=bar AWS_REGION=us-east-1 aws s3 ls)
  local first_word=""
  for w in "${words[@]}"; do
    if [[ "$w" == *"="* ]]; then
      continue
    else
      first_word="$w"
      break
    fi
  done

  [[ "$first_word" == "aws" ]] || return

  # Invalid session -> refresh before executing real command
  if ! aws_session_valid; then
    echo "[commands-middleware][aws] expired session – refreshing..." >&2
    aws_refresh_session || {
      echo "[commands-middleware][aws] failed to refresh session" >&2
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

# Register this middleware
commands_middleware_register "aws_middleware"