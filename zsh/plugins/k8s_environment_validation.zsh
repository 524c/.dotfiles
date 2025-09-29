# K8s Environment Validation Middleware
# Validates kubectl (or k) commands with -k flag against current context environment
#
# Configuration:
# export K8S_CONTEXT_MAPPINGS="prd.k8s.multpex.com.br=production|stg.k8s.multpex.com.br=staging"
# Optional debug:
# export K8S_ENV_VALIDATION_DEBUG=1
#
# Default patterns (if no custom mappings):
# - staging/stg -> staging
# - production/prod/prd -> production

# Function to get environment from kustomization.yaml
get_kustomization_env() {
  local kustom_file="$1/kustomization.yaml"
  if [[ -f "$kustom_file" ]]; then
    # tolerate leading/trailing spaces
    grep "^# Environment:" "$kustom_file" | sed 's/# Environment: *//' | tr -d '\n'
  else
    echo ""
  fi
}

# Function to get current context environment
get_current_context_env() {
  local context="$(${KUBECTL_REAL:-kubectl} config current-context 2>/dev/null)"
  context="${context%$'\n'}"

  [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: context=[$context]" >&2
  [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: K8S_CONTEXT_MAPPINGS=[$K8S_CONTEXT_MAPPINGS]" >&2

  # Custom mappings have priority
  if [[ -n "$K8S_CONTEXT_MAPPINGS" ]]; then
    local ctx_pattern env
    # Split by | and process each mapping
    local -a mappings
    IFS='|' read -rA mappings <<< "$K8S_CONTEXT_MAPPINGS"

    for mapping in "${mappings[@]}"; do
      ctx_pattern="${mapping%%=*}"
      env="${mapping##*=}"
      [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: testing [$context] == [$ctx_pattern] -> [$env]" >&2
      # Exact match for context
      if [[ "$context" == "$ctx_pattern" ]]; then
        [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: MATCH! returning [$env]" >&2
        printf '%s' "$env"
        return
      fi
    done
    [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: no custom mapping found, trying fallback" >&2
  else
    [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: no K8S_CONTEXT_MAPPINGS, using fallback" >&2
  fi

  # Fallback patterns
  if [[ "$context" == *staging* ]] || [[ "$context" == *stg* ]]; then
    [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: fallback matched staging" >&2
    printf '%s' "staging"
  elif [[ "$context" == *production* ]] || [[ "$context" == *prod* ]] || [[ "$context" == *prd* ]]; then
    [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: fallback matched production" >&2
    printf '%s' "production"
  else
    [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[DEBUG] get_current_context_env: no fallback match, returning unknown" >&2
    printf '%s' "unknown"
  fi
}

# Middleware function for commands-middleware system
k8s_environment_validation_middleware() {
  local command="$1"
  local -a words
  words=(${(z)command})

  # Find kubectl or k token
  local kubectl_index=-1
  local i
  for ((i=1; i<=${#words[@]}; i++)); do
    if [[ "${words[i]}" == "kubectl" || "${words[i]}" == "k" ]]; then
      kubectl_index=$i
      break
    fi
  done
  [[ $kubectl_index -eq -1 ]] && return 0

  # Locate -k flag
  local k_flag_index=-1
  for ((i=kubectl_index; i<=${#words[@]}; i++)); do
    if [[ "${words[i]}" == "-k" ]]; then
      k_flag_index=$i
      break
    fi
  done
  [[ $k_flag_index -eq -1 ]] && return 0

  # Folder after -k
  local folder_index=$((k_flag_index + 1))
  [[ $folder_index -gt ${#words[@]} ]] && return 0
  local folder="${words[folder_index]}"

  # Determine command type between kubectl token and -k
  local cmd_type=""
  for ((i=kubectl_index; i<k_flag_index; i++)); do
    case "${words[i]}" in
      apply|delete|replace)
        cmd_type="${words[i]}"; break ;;
    esac
  done
  [[ -z "$cmd_type" ]] && return 0

  # Environments
  local folder_env="$(get_kustomization_env "$folder")"
  local context_env="$(get_current_context_env)"

  # Skip if folder not tagged
  [[ -z "$folder_env" ]] && return 0

  if [[ "$folder_env" != "$context_env" ]]; then
    {
      echo " ❌ Environment mismatch!" >&2
      echo "   Command: kubectl $cmd_type -k $folder" >&2
      echo "   Folder environment: $folder_env" >&2
      echo "   Current context environment: $context_env" >&2
      echo "   Command blocked to prevent accidental deployment to wrong environment." >&2
      echo "" >&2
    }
    return 1
  fi

  [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "✅ Environment validation passed: $folder_env" >&2
  return 0
}

# Register with the new plugin system - K8s command patterns
plugin_register "k8s_environment_validation_middleware" "kubectl*-k* k*-k* *kubectl*-k* *k*-k*"
