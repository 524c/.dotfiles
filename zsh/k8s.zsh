#!/usr/bin/env zsh

# ============================================================================
# K8S CONTEXT MANAGER - CONFIGURATION
# ============================================================================

# General settings
K8S_STATE_FILE="$HOME/.k8s_state"
K8S_SIGNAL_FILE="$HOME/.k8s_signal"
DEFAULT_AWS_REGION="us-east-1"

# Available contexts definition
# Format: "cluster_name|state_store|aws_profile|display_name"
declare -A K8S_CONTEXTS=(
    ["stg"]="stg.k8s.multpex.com.br|s3://state.stg.multpex.com.br|multpex-stg|Staging Cluster"
    ["prd"]="k8s.multpex.com.br|s3://state.multpex.com.br|multpex-prd|Production Cluster"
)

# Context aliases - point to existing context keys
declare -A K8S_ALIASES=(
    ["staging"]="stg"
    ["prod"]="prd"
)

# Alias mapping to main contexts (for state saving)
declare -A K8S_CONTEXT_MAPPING=(
    ["stg"]="staging"
    ["staging"]="staging"
    ["prd"]="production"
    ["prod"]="production"
)

# ============================================================================
# INTERNAL FUNCTIONS
# ============================================================================

# Function to save current context state
_k8s_save_state() {
    local context=$1
    echo "CURRENT_CONTEXT=$context" > "$K8S_STATE_FILE"
    echo "KOPS_CLUSTER_NAME=$KOPS_CLUSTER_NAME" >> "$K8S_STATE_FILE"
    echo "KOPS_STATE_STORE=$KOPS_STATE_STORE" >> "$K8S_STATE_FILE"
    echo "AWS_PROFILE=$AWS_PROFILE" >> "$K8S_STATE_FILE"
    echo "AWS_REGION=$AWS_REGION" >> "$K8S_STATE_FILE"
    echo "TIMESTAMP=$(date +%s)" >> "$K8S_STATE_FILE"

    # Signal other shells to update
    touch "$K8S_SIGNAL_FILE"
}

# Function to load saved context state
_k8s_load_state() {
    if [[ -f "$K8S_STATE_FILE" ]]; then
        source "$K8S_STATE_FILE"

        # Only export if we have a valid context
        if [[ -n "$CURRENT_CONTEXT" ]]; then
            export KOPS_CLUSTER_NAME
            export KOPS_STATE_STORE
            export AWS_PROFILE
            export AWS_REGION

            # Set kubectl context without output
            kubectx "$KOPS_CLUSTER_NAME" >/dev/null 2>&1
        fi
    fi
}

# Function to check for updates from other shells
_k8s_check_updates() {
    if [[ -f "$K8S_SIGNAL_FILE" ]]; then
        local signal_time=$(stat -c %Y "$K8S_SIGNAL_FILE" 2>/dev/null || stat -f %m "$K8S_SIGNAL_FILE" 2>/dev/null)
        local current_time=$(date +%s)

        # Check if signal file is newer than 2 seconds (avoid constant reloading)
        if [[ $((current_time - signal_time)) -lt 2 ]]; then
            # Check if we need to update
            if [[ -f "$K8S_STATE_FILE" ]]; then
                source "$K8S_STATE_FILE"

                # Only update if context changed
                if [[ "$CURRENT_CONTEXT" != "$K8S_CURRENT_LOADED" ]]; then
                    export KOPS_CLUSTER_NAME
                    export KOPS_STATE_STORE
                    export AWS_PROFILE
                    export AWS_REGION
                    export K8S_CURRENT_LOADED="$CURRENT_CONTEXT"

                    # Set kubectl context silently
                    kubectx "$KOPS_CLUSTER_NAME" >/dev/null 2>&1

                    # Show update notification
                    echo "Context auto-updated to: $CURRENT_CONTEXT ($KOPS_CLUSTER_NAME)"
                fi
            fi
        fi
    fi
}

# Function to parse context configuration
_k8s_parse_context() {
    local context_key=$1

    # Check if it's an alias first
    if [[ -n ${K8S_ALIASES[$context_key]} ]]; then
        context_key=${K8S_ALIASES[$context_key]}
    fi

    local context_config=${K8S_CONTEXTS[$context_key]}

    if [[ -z "$context_config" ]]; then
        return 1
    fi

    # Split configuration string
    local config_array=(${(s:|:)context_config})

    export KOPS_CLUSTER_NAME=${config_array[1]}
    export KOPS_STATE_STORE=${config_array[2]}
    export AWS_PROFILE=${config_array[3]}
    export AWS_REGION=${DEFAULT_AWS_REGION}

    return 0
}

# Function to get display name for context
_k8s_get_display_name() {
    local context_key=$1

    # Check if it's an alias first
    if [[ -n ${K8S_ALIASES[$context_key]} ]]; then
        context_key=${K8S_ALIASES[$context_key]}
    fi

    local context_config=${K8S_CONTEXTS[$context_key]}

    if [[ -n "$context_config" ]]; then
        local config_array=(${(s:|:)context_config})
        echo ${config_array[4]}
    else
        echo "Unknown"
    fi
}

# Function to show available contexts
_k8s_show_contexts() {
    echo "Available contexts:"
    for key in ${(ok)K8S_CONTEXTS}; do
        local display_name=$(_k8s_get_display_name $key)
        printf "  %-12s - %s\n" "$key" "$display_name"
    done
    for alias target in ${(kv)K8S_ALIASES}; do
        local display_name=$(_k8s_get_display_name $target)
        printf "  %-12s - %s (alias)\n" "$alias" "$display_name"
    done
    echo "  sync         - Sync with saved context"
    echo "  clear        - Clear saved context"
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

# Function to switch Kubernetes contexts
k8s() {
    local context=$1

    if [[ -z "$context" ]]; then
        echo "Usage: k8s <context>"
        _k8s_show_contexts
        return 1
    fi

    case "$context" in
        "sync")
            _k8s_load_state
            export K8S_CURRENT_LOADED="$CURRENT_CONTEXT"
            echo "Synced with saved context: $CURRENT_CONTEXT"
            ;;
        "clear")
            rm -f "$K8S_STATE_FILE" "$K8S_SIGNAL_FILE"
            unset KOPS_CLUSTER_NAME KOPS_STATE_STORE AWS_PROFILE CURRENT_CONTEXT K8S_CURRENT_LOADED AWS_REGION
            echo "Context state cleared"
            ;;
        *)
            # Check if context exists in our configuration
            if _k8s_parse_context "$context"; then
                # Switch kubectl context
                if kubectx "$KOPS_CLUSTER_NAME" >/dev/null 2>&1; then
                    # Save state using mapped context name
                    local mapped_context=${K8S_CONTEXT_MAPPING[$context]:-$context}
                    _k8s_save_state "$mapped_context"
                    export K8S_CURRENT_LOADED="$mapped_context"

                    echo "Switched to $(_k8s_get_display_name $context) ($KOPS_CLUSTER_NAME)"
                else
                    echo "Failed to switch to context: $KOPS_CLUSTER_NAME"
                    return 1
                fi
            else
                printf "Context '%s' not recognized\n" "$context"
                _k8s_show_contexts
                return 1
            fi
            ;;
    esac
}

# ============================================================================
# AUXILIARY FUNCTIONS
# ============================================================================

# Function to show current context and variables
kstatus() {
    echo "Current Kubernetes status:"
    echo "  Context: $(kubectx -c 2>/dev/null || echo 'None')"
    echo "  KOPS_CLUSTER_NAME: ${KOPS_CLUSTER_NAME:-'Not set'}"
    echo "  KOPS_STATE_STORE: ${KOPS_STATE_STORE:-'Not set'}"
    echo "  AWS_PROFILE: ${AWS_PROFILE:-'Not set'}"
    echo "  AWS_REGION: ${AWS_REGION:-'Not set'}"

    if [[ -f "$K8S_STATE_FILE" ]]; then
        source "$K8S_STATE_FILE"
        echo "  Saved context: ${CURRENT_CONTEXT:-'None'}"
        echo "  Loaded context: ${K8S_CURRENT_LOADED:-'None'}"
    else
        echo "  Saved context: None"
    fi
}

# Function to enable auto-sync (polling mode)
k8s-auto() {
    echo "Auto-sync enabled. Press Ctrl+C to stop."
    while true; do
        _k8s_check_updates
        sleep 1
    done
}

# ============================================================================
# AUTOCOMPLETION
# ============================================================================

_k8s_completion() {
    local -a contexts
    for key in ${(k)K8S_CONTEXTS}; do
        local display_name=$(_k8s_get_display_name $key)
        contexts+=("$key:$display_name")
    done
    for alias in ${(k)K8S_ALIASES}; do
        local display_name=$(_k8s_get_display_name $alias)
        contexts+=("$alias:$display_name")
    done
    contexts+=('sync:Sync with saved context' 'clear:Clear saved context')
    _describe 'contexts' contexts
}

compdef _k8s_completion k8s

# ============================================================================
# INITIALIZATION
# ============================================================================

# Load state on shell startup
_k8s_load_state
