# AWS Middleware Plugin for Zsh
# This plugin intercepts AWS CLI commands to handle expired tokens by automatically running 'aws sso login' if enabled.

# Configuration variable to enable/disable auto-login on expired tokens
# Set AWS_AUTO_LOGIN=1 to enable, 0 to disable (default: 0)
export AWS_AUTO_LOGIN=${AWS_AUTO_LOGIN:-0}

# Function to detect if the error is due to expired token
function _aws_is_expired_token() {
    local error_msg="$1"
    # Common AWS CLI error messages for expired tokens
    if [[ "$error_msg" =~ "ExpiredToken" ]] || \
       [[ "$error_msg" =~ "Unable to locate credentials" ]] || \
       [[ "$error_msg" =~ "The security token included in the request is expired" ]]; then
        return 0  # True, expired token
    fi
    return 1  # False
}

# Main AWS wrapper function
function aws() {
    # Execute the original AWS command and capture output and error
    local output
    local error
    local exit_code

    # Run the command, capturing stdout and stderr separately
    exec 3>&1  # Save original stdout
    output=$(command aws "$@" 2>&1 >&3)
    exit_code=$?
    exec 3>&-  # Close fd 3

    # If command succeeded, just return the output
    if [[ $exit_code -eq 0 ]]; then
        echo "$output"
        return 0
    fi

    # Check if auto-login is enabled and error is expired token
    if [[ $AWS_AUTO_LOGIN -eq 1 ]] && _aws_is_expired_token "$output"; then
        echo "AWS token expired. Running 'aws sso login'..."
        # Run aws sso login (this will open browser for authentication)
        if command aws sso login; then
            echo "Login successful. Retrying original command..."
            # Retry the original command
            exec 3>&1
            output=$(command aws "$@" 2>&1 >&3)
            exit_code=$?
            exec 3>&-
            echo "$output"
            return $exit_code
        else
            echo "Login failed. Aborting."
            echo "$output"
            return $exit_code
        fi
    else
        # Not expired or auto-login disabled, just output the error
        echo "$output"
        return $exit_code
    fi
}

# Function to enable AWS auto-login
function aws_auto_login_enable() {
    export AWS_AUTO_LOGIN=1
    echo "✅ AWS auto-login enabled. Expired tokens will trigger 'aws sso login'."
}

# Function to disable AWS auto-login
function aws_auto_login_disable() {
    export AWS_AUTO_LOGIN=0
    echo "❌ AWS auto-login disabled."
}

# Function to show AWS auto-login status
function aws_auto_login_status() {
    if [[ $AWS_AUTO_LOGIN -eq 1 ]]; then
        echo "✅ AWS auto-login is enabled."
    else
        echo "❌ AWS auto-login is disabled."
    fi
}
