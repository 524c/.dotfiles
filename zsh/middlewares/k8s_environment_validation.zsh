# K8s Environment Validation Middleware
# Validates kubectl commands with -k flag against current context environment

# Function to get environment from kustomization.yaml
get_kustomization_env() {
  local kustom_file="$1/kustomization.yaml"
  if [[ -f "$kustom_file" ]]; then
    grep "^# Environment:" "$kustom_file" | sed 's/# Environment: //' | tr -d '\n'
  else
    echo ""
  fi
}

# Function to get current context environment
get_current_context_env() {
  local context="$(${KUBECTL_REAL:-kubectl} config current-context 2>/dev/null)"
  if [[ "$context" =~ staging ]] || [[ "$context" =~ stg ]]; then
    echo "staging"
  elif [[ "$context" =~ production ]] || [[ "$context" =~ prod ]]; then
    echo "production"
  else
    echo "unknown"
  fi
}

# Middleware function for commands-middleware system
k8s_environment_validation_middleware() {
  local command="$1"

  # Split the line into tokens respecting quotes
  local -a words
  words=(${(z)command})

  # Find kubectl command
  local kubectl_index=-1
  for i in {1..${#words[@]}}; do
    if [[ "${words[i]}" == "kubectl" ]]; then
      kubectl_index=$i
      break
    fi
  done

  # Not a kubectl command
  [[ $kubectl_index -eq -1 ]] && return

  # Check for -k flag
  local k_flag_index=-1
  for i in {$kubectl_index..${#words[@]}}; do
    if [[ "${words[i]}" == "-k" ]]; then
      k_flag_index=$i
      break
    fi
  done

  # No -k flag
  [[ $k_flag_index -eq -1 ]] && return

  # Get the folder (next argument after -k)
  local folder_index=$((k_flag_index + 1))
  [[ $folder_index -gt ${#words[@]} ]] && return

  local folder="${words[folder_index]}"

  # Check command type (apply, delete, replace)
  local cmd_type=""
  for i in {$kubectl_index..$((k_flag_index - 1))}; do
    case "${words[i]}" in
      apply|delete|replace)
        cmd_type="${words[i]}"
        break
        ;;
    esac
  done

  # Not a relevant command
  [[ -z "$cmd_type" ]] && return

  # Get environments
  local folder_env="$(get_kustomization_env "$folder")"
  local context_env="$(get_current_context_env)"

  # If folder has no environment tag, skip validation
  [[ -z "$folder_env" ]] && return

  # Validate
  if [[ "$folder_env" != "$context_env" ]]; then
    echo "❌ ERROR: Environment mismatch!" >&2
    echo "   Command: kubectl $cmd_type -k $folder" >&2
    echo "   Folder environment: $folder_env" >&2
    echo "   Current context environment: $context_env" >&2
    echo "   Command blocked to prevent accidental deployment to wrong environment." >&2

    # Block the command by replacing it with false
    if [[ -n "$BUFFER" ]]; then
      BUFFER="echo 'kubectl command blocked by environment validation middleware'"
    fi
    echo "echo 'kubectl command blocked by environment validation middleware'"
    return 1
  fi

  # Validation passed
  echo "✅ Environment validation passed: $folder_env" >&2
}

# Override kubectl function to intercept direct calls
# kubectl() {
#   echo "[DEBUG] kubectl wrapper called with: $*" >&2
#
#   # Build the full command
#   local full_command="kubectl $*"
#
#   # Call middleware for validation
#   local middleware_output
#   if middleware_output=$(k8s_environment_validation_middleware "$full_command" 2>/dev/null); then
#     # If middleware returned a corrected command, execute it
#     if [[ -n "$middleware_output" && "$middleware_output" != "$full_command" ]]; then
#       echo "[DEBUG] Executing corrected command: $middleware_output" >&2
#       eval "$middleware_output"
#       return
#     fi
#   else
#     # Middleware returned error (validation failed)
#     echo "[DEBUG] Middleware validation failed, blocking command" >&2
#     return 1
#   fi
#
#   # Execute original command if no correction needed
#   echo "[DEBUG] Executing original command: kubectl $*" >&2
#   command kubectl "$@"
# }

# Register this middleware
commands_middleware_register "k8s_environment_validation_middleware"
