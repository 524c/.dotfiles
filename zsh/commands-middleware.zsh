#!/usr/bin/env zsh

# commands-middleware plugin - Command interception and modification system
# Uses ZLE accept-line override with robust widget preservation and restoration

# Middleware directory and registered functions
COMMANDS_MIDDLEWARE_DIR="$HOME/.dotfiles/zsh/middlewares"
COMMANDS_MIDDLEWARE_LOADED=()

# Store original accept-line widget
_ORIGINAL_ACCEPT_LINE=""

# Register middleware function
commands_middleware_register() {
  local func_name="$1"
  [[ -n "$func_name" ]] && COMMANDS_MIDDLEWARE_LOADED+="$func_name"
}

# Main command processing function - intercepts and can modify commands
commands_middleware_accept_line() {
   echo "[DEBUG] commands_middleware_accept_line called with BUFFER='$BUFFER'" >&2
   [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] accept_line called with BUFFER='$BUFFER'" >&2
   [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[commands-middleware][debug] K8S_ENV_VALIDATION_DEBUG active, BUFFER='$BUFFER'" >&2
   local original_buffer="$BUFFER"
   local original_cursor="$CURSOR"
  
  # Skip empty commands
  [[ -z "${original_buffer//[[:space:]]/}" ]] && {
    [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] skipping empty command" >&2
    zle $_ORIGINAL_ACCEPT_LINE
    return
  }
  
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] processing command: '$original_buffer'" >&2
  
   # Process through middlewares - they can modify BUFFER
   local mw
   for mw in $COMMANDS_MIDDLEWARE_LOADED; do
     [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] calling middleware: $mw" >&2
     [[ -n "$K8S_ENV_VALIDATION_DEBUG" ]] && echo "[commands-middleware][debug] K8S calling middleware: $mw" >&2
     # Call middleware with current buffer content; middleware can modify BUFFER directly
     # or return corrected command
     local mw_output
     if mw_output=$($mw "$BUFFER" 2>/dev/null); then
       if [[ -n "$mw_output" && "$mw_output" != "$BUFFER" ]]; then
         BUFFER="$mw_output"
         [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] buffer modified by $mw to '$BUFFER'" >&2
       fi
     fi
   done
  
  # If buffer was modified by middleware, update cursor position
  if [[ "$BUFFER" != "$original_buffer" ]]; then
    [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] buffer modified from '$original_buffer' to '$BUFFER'" >&2
    CURSOR=${#BUFFER}
  fi
  
  # Execute the (possibly modified) command
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] executing final command: '$BUFFER'" >&2
  zle $_ORIGINAL_ACCEPT_LINE
}

# Setup ZLE interception with widget preservation
commands_middleware_setup_zle() {
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] setup_zle: checking current accept-line widget" >&2
  # Check if accept-line widget is already our custom one
  local current_widget=$(zle -l accept-line 2>/dev/null | awk '{print $2}')
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] setup_zle: current widget='$current_widget'" >&2
  
  if [[ "$current_widget" == "commands_middleware_accept_line" ]]; then
    [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] setup_zle: already set up, skipping" >&2
    # Already setup, don't overwrite
    return 0
  fi
  
  # Save current accept-line widget before overriding
  if [[ -n "$current_widget" ]] && [[ "$current_widget" != "undefined-key" ]]; then
    _ORIGINAL_ACCEPT_LINE="$current_widget"
    [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] setup_zle: saved original widget '$_ORIGINAL_ACCEPT_LINE'" >&2
  else
    _ORIGINAL_ACCEPT_LINE=".accept-line"
    [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] setup_zle: using default '.accept-line'" >&2
  fi
  
  # Create our custom widget
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] setup_zle: creating custom widget" >&2
  zle -N accept-line commands_middleware_accept_line
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[commands-middleware][debug] setup_zle: widget created successfully" >&2
}

# Restore original accept-line widget (cleanup function)
commands_middleware_restore() {
  # Only restore if we have a valid original widget and it still exists
  if [[ -n "$_ORIGINAL_ACCEPT_LINE" ]] && [[ "$_ORIGINAL_ACCEPT_LINE" != "commands_middleware_accept_line" ]]; then
    # Check if the widget still exists before trying to restore it
    if zle -l | grep -q "^$_ORIGINAL_ACCEPT_LINE "; then
      zle -A "$_ORIGINAL_ACCEPT_LINE" accept-line 2>/dev/null || true
    else
      # Original widget doesn't exist anymore, restore to builtin
      zle -A ".accept-line" accept-line 2>/dev/null || true
    fi
  fi
}

# Initialize plugin
commands_middleware_init() {
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[DIAGNOSTIC] commands_middleware_init: STARTING"
  # Prevent double initialization
  [[ ${#COMMANDS_MIDDLEWARE_LOADED[@]} -gt 0 ]] && { [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[DIAGNOSTIC] commands_middleware_init: SKIPPING - already loaded."; return 0; }
  
  # Create middlewares directory if needed
  [[ -d "$COMMANDS_MIDDLEWARE_DIR" ]] || mkdir -p "$COMMANDS_MIDDLEWARE_DIR"
  
  # Load all middlewares
  local middleware
  for middleware in "$COMMANDS_MIDDLEWARE_DIR"/*.zsh; do
    if [[ -f "$middleware" ]]; then
      [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[DIAGNOSTIC] commands_middleware_init: Sourcing $middleware"
      source "$middleware"
    fi
  done
  
  # Setup ZLE interception
  commands_middleware_setup_zle
  
  # Register cleanup on shell exit
  trap commands_middleware_restore EXIT
  [[ -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[DIAGNOSTIC] commands_middleware_init: FINISHED. Loaded: ${#COMMANDS_MIDDLEWARE_LOADED[@]} middlewares."
}

# Reload middlewares (hot reload helper)
commands_middleware_reload() {
  COMMANDS_MIDDLEWARE_LOADED=()
  # Unfunction known middleware symbols so updated definitions load cleanly
  unfunction aws_middleware aws_fix_s3_uri aws_session_valid aws_refresh_session aws_mw_debug 2>/dev/null || true
  local middleware
  for middleware in "$COMMANDS_MIDDLEWARE_DIR"/*.zsh; do
    [[ -f "$middleware" ]] && source "$middleware"
  done
  print -u2 "[commands-middleware] reloaded (${#COMMANDS_MIDDLEWARE_LOADED[@]} middleware(s))"
}

# Only initialize if not already done
[[ -z "$COMMANDS_MIDDLEWARE_INITIALIZED" ]] && {
  commands_middleware_init
  export COMMANDS_MIDDLEWARE_INITIALIZED=1
}
