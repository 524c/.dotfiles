#!/usr/bin/env zsh

# utils.zsh - Shared utilities for ZSH plugins system
# Provides common functions used across multiple plugins

# === DEBUG UTILITIES ===

# Main debug function - replaces aws_mw_debug and other scattered debug functions
debug() {
    [[ -n "$AWS_MIDDLEWARE_DEBUG" || -n "$PLUGINS_DEBUG" ]] && echo "[debug] $*" >&2
}

# Plugin-specific info messages (only when debug enabled)
info() {
    [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "$*" >&2
}

# Error messaging utility
error() {
    echo "[error] $*" >&2
}

# Warning messaging utility
warn() {
    echo "[warn] $*" >&2
}

# === STRING UTILITIES ===

# Check if string contains pattern
contains() {
    local string="$1"
    local pattern="$2"
    [[ "$string" == *"$pattern"* ]]
}

# Trim whitespace from string
trim() {
    local string="$1"
    echo "${string##*( )}"
}

# === VALIDATION UTILITIES ===

# Check if function exists
function_exists() {
    declare -f "$1" >/dev/null 2>&1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# === PLUGIN UTILITIES ===

# Safe plugin loading with error handling
load_plugin() {
    local plugin_file="$1"
    if [[ -f "$plugin_file" ]]; then
        source "$plugin_file"
        debug "loaded plugin: $plugin_file"
    else
        warn "plugin not found: $plugin_file"
        return 1
    fi
}

# Plugin registration helper
register_plugin() {
    local plugin_name="$1"
    local patterns="$2"
    
    if function_exists plugin_register; then
        plugin_register "$plugin_name" "$patterns"
        debug "registered plugin: $plugin_name with patterns: $patterns"
    else
        error "plugin_register function not available"
        return 1
    fi
}