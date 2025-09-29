#!/usr/bin/env zsh

# plugins-loader - ZSH Plugin Management System
# Unified command interception and plugin management for ZSH
# Successor to commands-middleware system

# === UTILS IMPORT ===
# Load shared utilities first
source "$HOME/.dotfiles/zsh/utils.zsh"

# === DEBUG CONFIGURATION ===
# Production mode: disable debug output by default  
# To enable debug: export AWS_MIDDLEWARE_DEBUG=1 before sourcing this file
# To enable via alias: aws_middleware_test (defined in .zshrc)
[[ -z "$AWS_MIDDLEWARE_DEBUG" ]] && unset AWS_MIDDLEWARE_DEBUG

# Plugin directory and registered functions
PLUGINS_DIR="$HOME/.dotfiles/zsh/plugins"
PLUGINS_LOADED=()

# Plugin routing table - associative arrays for pattern matching
# PLUGIN_PATTERNS stores the raw (space-separated) pattern string per plugin
# PATTERN_PLUGIN_MAP maps each individual pattern -> space separated list of plugins providing it
# PATTERN_LIST is an ordered array of unique patterns to preserve deterministic iteration order
# PLUGIN_FUNCTIONS maps plugin name -> function symbol (currently same)
declare -A PLUGIN_PATTERNS
declare -A PLUGIN_FUNCTIONS
declare -A PATTERN_PLUGIN_MAP
PATTERN_LIST=()

# Store original accept-line widget
_ORIGINAL_ACCEPT_LINE=""

# Pattern matching function (generic)
# NOTE: All patterns come EXCLUSIVAMENTE dos plugins via plugin_register.
# Sem casos especiais codificados aqui. Qualquer lógica especial deve ser implementada no próprio plugin
# ajustando seu set de padrões ou validando internamente o BUFFER.
match_command_pattern() {
  local cmd="$1"
  local pattern="$2"
  # Use zsh pattern matching with proper expansion
  if [[ "$cmd" == ${~pattern} ]]; then
    return 0
  fi
  return 1
}

# Internal helper: append value to space-separated list in PATTERN_PLUGIN_MAP
_append_to_list() {
  # $1 = array name (must be "PATTERN_PLUGIN_MAP")
  # $2 = key
  # $3 = value to append (if not already present)
  local arr_name="$1" key="$2" value="$3"
  
  # Only support PATTERN_PLUGIN_MAP to avoid eval issues
  if [[ "$arr_name" != "PATTERN_PLUGIN_MAP" ]]; then
    warn "_append_to_list: only PATTERN_PLUGIN_MAP supported, got: $arr_name"
    return 1
  fi
  
  local current="${PATTERN_PLUGIN_MAP[$key]}"
  if [[ -z "$current" ]]; then
    PATTERN_PLUGIN_MAP[$key]="$value"
  else
    # Avoid duplicate plugin entries for same pattern
    case " $current " in
      *" $value "*) ;; # already present
      *) PATTERN_PLUGIN_MAP[$key]="$current $value" ;;
    esac
  fi
}

# Internal helper: register individual patterns into PATTERN_PLUGIN_MAP / PATTERN_LIST
_register_patterns_for_plugin() {
  local plugin="$1"
  local patterns_raw="$2"
  local remaining="$patterns_raw" token
  while [[ -n "$remaining" ]]; do
    if [[ "$remaining" == *" "* ]]; then
      token="${remaining%% *}"
      remaining="${remaining#* }"
    else
      token="$remaining"
      remaining=""
    fi
    [[ -z "$token" ]] && continue
    _append_to_list PATTERN_PLUGIN_MAP "$token" "$plugin"
    # Maintain ordered unique list - handle empty array case
    local found=false
    if [[ ${#PATTERN_LIST[@]} -gt 0 ]]; then
      for existing_pattern in "${PATTERN_LIST[@]}"; do
        if [[ "$existing_pattern" == "$token" ]]; then
          found=true; break
        fi
      done
    fi
    if ! $found; then
      PATTERN_LIST+=("$token")
    fi
  done
}

# Rebuild full pattern index (used on reload)
_rebuild_pattern_index() {
  PATTERN_PLUGIN_MAP=()
  PATTERN_LIST=()
  local plugin
  for plugin in "${PLUGINS_LOADED[@]}"; do
    local raw="${PLUGIN_PATTERNS[$plugin]}"
    [[ -n "$raw" ]] && _register_patterns_for_plugin "$plugin" "$raw"
  done
}

# Diagnostic function - for major checkpoints  
plugin_diagnostic() {
  [[ -n "$PLUGINS_DEBUG" || -n "$AWS_MIDDLEWARE_DEBUG" ]] && echo "[DIAGNOSTIC] $*" >&2
}

# Register plugin function with routing patterns
# Usage: plugin_register <function_name> "pattern1 pattern2 ..."
# Regras:
#  - Padrões são glob patterns ZSH (case $BUFFER in pattern) semantics
#  - Vários plugins podem declarar o MESMO padrão → todos serão acionados
#  - Padrão '*' só deve ser usado de forma explícita (warning se omitido)
plugin_register() {
  local func_name="$1"
  local patterns="$2"  # Space-separated patterns for routing
  if [[ -z "$func_name" ]]; then
    warn "plugin_register: missing function name"
    return 1
  fi
  if ! declare -f "$func_name" >/dev/null 2>&1; then
    warn "plugin_register: function '$func_name' not defined yet (source order issue?)"
  fi

  PLUGINS_LOADED+=("$func_name")
  PLUGIN_FUNCTIONS[$func_name]="$func_name"

  if [[ -z "$patterns" ]]; then
    # Guardrail: require explicit '*' if plugin wants global interception
    warn "plugin_register: plugin '$func_name' no patterns supplied. Use '*' explicitly if you intend global match. Registering '*' by default (backward compatibility)."
    patterns="*"
  fi

  PLUGIN_PATTERNS[$func_name]="$patterns"
  _register_patterns_for_plugin "$func_name" "$patterns"
  debug "registered plugin: $func_name with patterns: $patterns"
}

# Main command processing function - intercepts and can modify commands
plugins_accept_line() {
   debug "accept_line called with BUFFER='$BUFFER'"
   # Skip commands containing pipes to avoid corruption right now
   if [[ "$BUFFER" == *"|"* ]]; then
     debug "skipping pipe command: '$BUFFER'"
     zle $_ORIGINAL_ACCEPT_LINE
     return 0
    fi

   # Prevent infinite recursion
   local recursion_count=0 func
   for func in "${funcstack[@]}"; do
     [[ "$func" == "plugins_accept_line" ]] && ((recursion_count++))
   done
   if [[ $recursion_count -gt 1 ]]; then
     debug "preventing recursion - count: $recursion_count"
     zle $_ORIGINAL_ACCEPT_LINE
     return 0
   fi

   # Detect AI shell context
   local from_ai=false
   if [[ "${funcstack[*]}" == *"ai_accept_line"* ]]; then
     from_ai=true
     debug "called from AI system"
   fi

   local original_buffer="$BUFFER"
   debug "processing command: '$BUFFER'"

   # ROUTER v2 (pattern-index based)
   local -a routed_plugins=()
   local -A seen_plugin
   debug "🔀 ROUTER: indexed patterns count=${#PATTERN_LIST[@]}"

   local pattern plugin_list plugin
   for pattern in "${PATTERN_LIST[@]}"; do
     if match_command_pattern "$BUFFER" "$pattern"; then
       debug "🎯 ROUTER: '$BUFFER' matches pattern '$pattern' → plugins: ${PATTERN_PLUGIN_MAP[$pattern]}"
       # Add all plugins for this pattern
       for plugin in ${=PATTERN_PLUGIN_MAP[$pattern]}; do
         if [[ -z "${seen_plugin[$plugin]}" ]]; then
           routed_plugins+=("$plugin")
           seen_plugin[$plugin]=1
         fi
       done
     else
       debug "⏭️  ROUTER: '$BUFFER' no match for pattern '$pattern'"
     fi
   done

   debug "🚀 ROUTER: dispatching to ${#routed_plugins[@]} plugins: ${routed_plugins[*]}"

   for plugin in "${routed_plugins[@]}"; do
     if declare -f "$plugin" >/dev/null 2>&1; then
       debug "📞 calling routed plugin: $plugin (BUFFER='$BUFFER')"
       local plugin_result
       plugin_result=$($plugin "$BUFFER" 2>&1)
       local exit_code=$?
       
        # If plugin blocks command (non-zero exit), stop execution
        if [[ $exit_code -ne 0 ]]; then
          # Print plugin output (error message) and clear buffer to prevent infinite loop
          # Plugin bloqueou o comando: mostra mensagem e força novo prompt
          # Imprime mensagem já contendo newline final; evita dupla linha em branco
          # Garantir que a mensagem começa em nova linha (prompt + comando ainda não tinham newline)
          { printf "\n%s" "$plugin_result"; } > /dev/tty 2>&1
          # Usar comando no-op ':' com espaço inicial para não entrar no histórico (HIST_IGNORE_SPACE)
          BUFFER=" :"
          CURSOR=${#BUFFER}
          zle $_ORIGINAL_ACCEPT_LINE   # executa ':' e gera novo prompt
          BUFFER=""    # limpa buffer para o usuário
          CURSOR=0
          return 0
        fi
       
       plugin_result="${plugin_result#"${plugin_result%%[![:space:]]*}"}"  # ltrim
       plugin_result="${plugin_result%"${plugin_result##*[![:space:]]}"}"  # rtrim
       
       # Handle special AI shell buffer-update-only signal
       if [[ "$plugin_result" == "BUFFER_UPDATE_ONLY:"* ]]; then
         debug "🤖 AI shell buffer update detected - processing with ZLE widget"
         local ai_command="${plugin_result#BUFFER_UPDATE_ONLY:}"
         # Call the ZLE widget version for buffer update without execution
         ai_process_command_zle_non_executing "$ai_command" "$BUFFER"
         return 0  # Don't execute, just update buffer
       elif [[ -n "$plugin_result" && "$plugin_result" != "$BUFFER" ]]; then
         debug "✅ $plugin returned: '$plugin_result'"
         debug "🔄 buffer corrected by $plugin: '$BUFFER' → '$plugin_result'"
         BUFFER="$plugin_result"
       else
         [[ "$BUFFER" != "$original_buffer" ]] && debug "🔄 $plugin modified buffer directly"
       fi
     else
       debug "❌ routed plugin function $plugin not found"
     fi
   done

   if [[ "$BUFFER" != "$original_buffer" ]]; then
     debug "visual correction applied: '$original_buffer' → '$BUFFER'"
     CURSOR=${#BUFFER}
   fi

   debug "executing final command: '$BUFFER'"
   zle $_ORIGINAL_ACCEPT_LINE
}

# Setup ZLE interception with widget preservation
plugins_setup_zle() {
  debug "setup_zle: checking ZLE availability"
  if ! zle -l >/dev/null 2>&1; then
    debug "setup_zle: ZLE not available, deferring setup"
    return 1
  fi
  debug "setup_zle: checking current accept-line widget"
  local current_widget=$(zle -l accept-line 2>/dev/null | awk '{print $2}')
  if [[ -z "$current_widget" ]]; then
    current_widget=".accept-line"
  fi
  debug "setup_zle: current widget='$current_widget'"
  if [[ "$current_widget" == "plugins_accept_line" ]]; then
    debug "setup_zle: already set up, skipping"
    return 0
  fi
  local enter_binding=$(bindkey | grep '^"^M"' | awk '{print $2}')
  debug "setup_zle: current ^M binding='$enter_binding'"
  if [[ "$enter_binding" == "ai_accept_line" ]]; then
    debug "setup_zle: AI shell detected, patching ai_accept_line"
    _ORIGINAL_ACCEPT_LINE=".accept-line"
    local ai_func=$(declare -f ai_accept_line)
    local patched_func=$(echo "$ai_func" | sed 's/zle \.accept-line/plugins_accept_line/')
    eval "$patched_func"
    plugin_diagnostic "setup_zle: AI shell patched to use plugins system"
    return 0
  else
    debug "setup_zle: standard mode, setting up direct binding"
    _ORIGINAL_ACCEPT_LINE="$current_widget"
    zle -N accept-line plugins_accept_line
    plugin_diagnostic "setup_zle: direct binding established"
    return 0
  fi
}

# Delayed setup function for precmd hook
plugins_delayed_setup() {
  debug "delayed_setup: attempting ZLE setup"
  if plugins_setup_zle; then
    plugin_diagnostic "delayed_setup: ZLE setup successful, removing hook"
    add-zsh-hook -d precmd plugins_delayed_setup
  fi
}

# Status function for debugging
plugins_status() {
  echo "🔌 ZSH Plugins System Status (Router-based)"
  echo "============================================="
  echo "Plugins directory: $PLUGINS_DIR"
  echo "Original accept-line: $_ORIGINAL_ACCEPT_LINE"
  echo "Current ^M binding: $(bindkey | grep '^"^M"' | awk '{print $2}')"
  echo ""
  echo "🔀 Pattern Index (pattern → plugins):"
  if [[ ${#PATTERN_LIST[@]} -eq 0 ]]; then
    echo "  (no patterns registered)"
  else
    local pat
    for pat in "${PATTERN_LIST[@]}"; do
      echo "  $pat → ${PATTERN_PLUGIN_MAP[$pat]}"
    done
  fi
  echo ""
  echo "🔀 Plugin Declarations:"
  if [[ ${#PLUGINS_LOADED[@]} -eq 0 ]]; then
    echo "  (no plugins registered)"
  else
    local plugin
    for plugin in "${PLUGINS_LOADED[@]}"; do
      local patterns="${PLUGIN_PATTERNS["$plugin"]:-*}"
      if declare -f "$plugin" >/dev/null 2>&1; then
        echo "  ✅ $plugin → patterns: $patterns"
      else
        echo "  ❌ $plugin → patterns: $patterns (function missing)"
      fi
    done
  fi
  echo ""
  echo "🧪 Routing Test Examples:"
  local test_commands=("aws s3 ls" "kubectl get pods" "git status" "ls -la" "# list files")
  local cmd
  for cmd in "${test_commands[@]}"; do
    echo -n "  '$cmd' → "
    local routed=()
    local -A seen
    for pat in "${PATTERN_LIST[@]}"; do
      if match_command_pattern "$cmd" "$pat"; then
        for plugin in ${=PATTERN_PLUGIN_MAP[$pat]}; do
          if [[ -z "${seen[$plugin]}" ]]; then
            routed+=("$plugin"); seen[$plugin]=1
          fi
        done
      fi
    done
    if [[ ${#routed[@]} -eq 0 ]]; then
      echo "no plugins"
    else
      echo "${routed[*]}"
    fi
  done
}

# Self-test function to validate routing logic against arbitrary commands
# Usage:
#   plugins_selftest 'aws s3 ls bucket' 'kubectl apply -k overlays/staging'
#   plugins_selftest -f /path/to/commands.txt   (lines beginning with # or blank ignored)
# Behavior:
#   - For each command prints matched plugins (or no plugins)
#   - Summary line with counts
#   - Exit code 0 always (diagnostic tool, not a CI gate)
plugins_selftest() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: plugins_selftest 'command1' 'command2' ..." >&2
    echo "       plugins_selftest -f file_with_commands" >&2
    return 1
  fi
  local -a commands=()
  if [[ "$1" == "-f" ]]; then
    local f="$2"
    if [[ -z "$f" || ! -f "$f" ]]; then
      echo "plugins_selftest: file not found: $f" >&2
      return 1
    fi
    while IFS=$'\n' read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      commands+=("$line")
    done < "$f"
  else
    commands=("$@")
  fi
  local total=0 matched=0
  local cmd
  for cmd in "${commands[@]}"; do
    ((total++))
    local -a routed=()
    local -A seen
    for pattern in "${PATTERN_LIST[@]}"; do
      if match_command_pattern "$cmd" "$pattern"; then
        for plugin in ${=PATTERN_PLUGIN_MAP[$pattern]}; do
          if [[ -z "${seen[$plugin]}" ]]; then
            routed+=("$plugin"); seen[$plugin]=1
          fi
        done
      fi
    done
    if [[ ${#routed[@]} -gt 0 ]]; then
      ((matched++))
      printf "✔ '%s' → %s\n" "$cmd" "${routed[*]}"
    else
      printf "✖ '%s' → (no plugins)\n" "$cmd"
    fi
  done
  echo "Summary: $matched/$total commands matched at least one plugin"
  return 0
}

# Restoration function (emergency mode)
plugins_restore() {
  plugin_diagnostic "restore: emergency restoration requested"
  if [[ -n "$_ORIGINAL_ACCEPT_LINE" ]]; then
    if [[ "$_ORIGINAL_ACCEPT_LINE" == ".accept-line" ]]; then
      bindkey '^M' accept-line
    else
      zle -N accept-line "$_ORIGINAL_ACCEPT_LINE"
    fi
    plugin_diagnostic "restore: accept-line restored to '$_ORIGINAL_ACCEPT_LINE'"
  fi
  PLUGINS_LOADED=()
  PLUGIN_PATTERNS=()
  PATTERN_PLUGIN_MAP=()
  PATTERN_LIST=()
  _ORIGINAL_ACCEPT_LINE=""
  echo "🔄 Plugins system restored to original state"
}

# Reload function for development
# Unregister a plugin at runtime
# Usage: plugin_unregister <plugin_name>
# - Removes plugin from all indices
# - Does NOT unfunction the underlying function (non-destructive)
# - Rebuilds pattern index and leaves ZLE binding intact
plugin_unregister() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "plugin_unregister: missing plugin name" >&2
    return 1
  fi
  local new_loaded=()
  local p
  for p in "${PLUGINS_LOADED[@]}"; do
    [[ "$p" == "$name" ]] && continue
    new_loaded+=("$p")
  done
  PLUGINS_LOADED=(${new_loaded[@]})
  unset PLUGIN_PATTERNS[$name]
  unset PLUGIN_FUNCTIONS[$name]
  # Rebuild pattern structures
  _rebuild_pattern_index
  echo "🗑️  Unregistered plugin: $name"
}

plugins_reload() {
  plugin_diagnostic "reload: reloading plugins system"
  PLUGINS_LOADED=()
  PLUGIN_PATTERNS=()
  PATTERN_PLUGIN_MAP=()
  PATTERN_LIST=()
  local plugin_file
  for plugin_file in "$PLUGINS_DIR"/*.zsh; do
    if [[ -f "$plugin_file" ]]; then
      plugin_diagnostic "reload: sourcing $plugin_file"
      source "$plugin_file"
    fi
  done
  _rebuild_pattern_index
  plugins_setup_zle
  echo "🔄 Plugins system reloaded"
}

# Initialize plugin system
plugins_init() {
  if [[ -n "$PLUGINS_DISABLED" ]]; then
    echo "[plugins-loader] Plugins are disabled (emergency mode)"
    return 0
  fi
  plugin_diagnostic "plugins_init: STARTING"
  [[ -d "$PLUGINS_DIR" ]] || mkdir -p "$PLUGINS_DIR"
  local plugin_file
  for plugin_file in "$PLUGINS_DIR"/*.zsh; do
    if [[ -f "$plugin_file" ]]; then
      plugin_diagnostic "plugins_init: sourcing $plugin_file"
      source "$plugin_file"
    fi
  done
  _rebuild_pattern_index
  if ! plugins_setup_zle; then
    plugin_diagnostic "plugins_init: ZLE setup failed, setting up delayed retry"
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd plugins_delayed_setup
  fi
  plugin_diagnostic "plugins_init: COMPLETED"
}

# Auto-initialize when sourced
plugins_init
