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

# Check if AWS credentials are valid
aws_session_valid() {
  aws sts get-caller-identity &>/dev/null
}

# Refresh AWS session
aws_refresh_session() {
  # Simple session refresh - extend as needed
  if command -v aws-sso >/dev/null 2>&1; then
    aws-sso login
  elif [[ -n "$AWS_PROFILE" ]]; then
    aws sso login --profile "$AWS_PROFILE"
  else
    aws sso login
  fi
}

# Register this middleware
commands_middleware_register "aws_middleware"