# Kubernetes middleware for destructive command confirmation

function kubectl() {
    local cmd="$*"
    # Check for destructive commands
    if [[ "$cmd" =~ delete ]]; then
        echo -n "This command is destructive. Type 'yes' to confirm: "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            echo "Command aborted."
            return 1
        fi
    fi
    # Use kubecolor for output coloring, except for completion
    if [[ $1 == "completion" ]]; then
        command kubectl "$@"
    else
        kubecolor "$@"
    fi
}

function k() {
    local cmd="$*"
    # Check for destructive commands
    if [[ "$cmd" =~ delete ]]; then
        echo -n "This command is destructive. Type 'yes' to confirm: "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            echo "Command aborted."
            return 1
        fi
    fi
    # Use kubecolor for output coloring, except for completion
    if [[ $1 == "completion" ]]; then
        command kubectl "$@"
    else
        kubecolor "$@"
    fi
}