# Kubernetes middleware for destructive command confirmation

function confirm_destructive_command() {
    local cmd="$1"
    if [[ "$cmd" =~ delete ]]; then
        echo -n "This command is destructive. Type 'yes' to confirm: "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            echo "Command aborted."
            return 1
        fi
    fi
    return 0
}

function kubectl() {
  if [[ $1 == "completion" ]]; then
    command kubectl "$@"
  else
    # K8s Environment Validation
    local args=("$@")
    local has_k_flag=false
    local k_folder=""

    # Parse arguments to find -k flag
    for ((i=1; i<=$#; i++)); do
      if [[ "${args[$i-1]}" == "-k" && $i -le $# ]]; then
        has_k_flag=true
        k_folder="${args[$i]}"
        break
      fi
    done

    if [[ "$has_k_flag" == true ]]; then
      # Check command type (apply, delete, replace)
      local cmd_type=""
      for arg in "$@"; do
        case "$arg" in
          apply|delete|replace)
            cmd_type="$arg"
            break
            ;;
        esac
      done

      if [[ -n "$cmd_type" ]]; then
        # Get environments
        local folder_env=""
        local kustom_file="$k_folder/kustomization.yaml"
        if [[ -f "$kustom_file" ]]; then
          folder_env=$(grep "^# Environment:" "$kustom_file" | sed 's/# Environment: //' | tr -d '\n')
        fi

        local context_env=""
        local context=$(command kubectl config current-context 2>/dev/null)
        context="${context%$'\n'}"

        # Custom mappings have priority
        if [[ -n "$K8S_CONTEXT_MAPPINGS" ]]; then
          local ctx_pattern env
          # Split by | and process each mapping
          local -a mappings
          IFS='|' read -rA mappings <<< "$K8S_CONTEXT_MAPPINGS"

          for mapping in "${mappings[@]}"; do
            ctx_pattern="${mapping%%=*}"
            env="${mapping##*=}"
            # Exact match for context
            if [[ "$context" == "$ctx_pattern" ]]; then
              context_env="$env"
              break
            fi
          done
        fi

        # Fallback patterns
        if [[ -z "$context_env" ]]; then
          if [[ "$context" == *staging* ]] || [[ "$context" == *stg* ]]; then
            context_env="staging"
          elif [[ "$context" == *production* ]] || [[ "$context" == *prod* ]] || [[ "$context" == *prd* ]]; then
            context_env="production"
          fi
        fi

        # Validate
        if [[ -n "$folder_env" && "$folder_env" != "$context_env" ]]; then
          echo "❌ ERROR: Environment mismatch!"
          echo "   Current context environment: $context_env"
          echo "   Command blocked to prevent accidental deployment to wrong environment."
          return 1
        fi

        # Validation passed
        #if [[ -n "$folder_env" ]]; then
        #  echo "✅ Environment validation passed: $folder_env"
        #fi
      fi
    fi

    # Check for destructive commands
    confirm_destructive_command "$*" || return 1

    kubecolor "$@"
  fi
}

function k() {
    local cmd="$*"
    # Check for destructive commands
    confirm_destructive_command "$cmd" || return 1
    # Use kubecolor for output coloring, except for completion
    if [[ $1 == "completion" ]]; then
        command kubectl "$@"
    else
        kubecolor "$@"
    fi
}
