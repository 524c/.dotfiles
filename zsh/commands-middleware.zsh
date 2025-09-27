#!/usr/bin/env zsh

# commands-middleware plugin - Robust command interception via preexec hook
# Substitui abordagem anterior (override de accept-line) para evitar conflitos
# com outros plugins (fzf, autosuggestions, syntax-highlighting) que redefinem
# widgets do ZLE após o carregamento.

# Diretório dos middlewares
COMMANDS_MIDDLEWARE_DIR="$HOME/.dotfiles/zsh/middlewares"
# Lista de funções middleware registradas
COMMANDS_MIDDLEWARE_LOADED=()

# Registro de middleware
commands_middleware_register() {
  local func_name="$1"
  [[ -n "$func_name" ]] && COMMANDS_MIDDLEWARE_LOADED+="$func_name"
}

# Função executada antes de QUALQUER comando (preexec hook)
# $1 = linha completa do comando
commands_middleware_preexec() {
  local line="$1"
  # Ignora linhas vazias ou só com espaços
  [[ -z "${line//[[:space:]]/}" ]] && return 0

  # Executa cada middleware em ordem
  local mw
  for mw in $COMMANDS_MIDDLEWARE_LOADED; do
    # Chama protegendo contra erros individuais
    { $mw "$line"; } 2>/dev/null || true
  done
}

commands_middleware_init() {
  # Garante diretório
  [[ -d "$COMMANDS_MIDDLEWARE_DIR" ]] || mkdir -p "$COMMANDS_MIDDLEWARE_DIR"

  # Carrega middlewares
  local middleware
  for middleware in "$COMMANDS_MIDDLEWARE_DIR"/*.zsh; do
    [[ -f "$middleware" ]] && source "$middleware"
  done

  # Garante add-zsh-hook carregado
  autoload -Uz add-zsh-hook 2>/dev/null || true
  # Evita registrar múltiplas vezes (remove anterior se existir)
  add-zsh-hook -d preexec commands_middleware_preexec 2>/dev/null || true
  add-zsh-hook preexec commands_middleware_preexec
}

commands_middleware_init
