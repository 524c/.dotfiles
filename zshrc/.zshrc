#if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
#fi

# zsh
ZSH_DISABLE_COMPFIX=true
setopt nocorrectall
setopt APPEND_HISTORY
setopt HIST_VERIFY
setopt AUTO_CD
unsetopt EQUALS

export HISTFILE=$HOME/.zhistory
export HISTSIZE=1000000
export SAVEHIST=1000000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_IGNORE_SPACE
setopt HIST_NO_STORE
setopt HIST_EXPIRE_DUPS_FIRST
setopt INC_APPEND_HISTORY
setopt EXTENDED_HISTORY

# K8S
export KUBECONFIG=$HOME/.kube/config

alias kg="kubectl get"
alias kd="kubectl describe"
alias kdel="kubectl delete"
alias kl="kubectl logs"
alias kgpo="kubectl get pod"
alias kgd="kubectl get deployments"
alias kgst="kubectl get statefulset"
alias kc="kubectx"
alias kns="kubens"
alias kl="kubectl logs -f"
alias ke="kubectl exec -it"
alias kcns='kubectl config set-context --current --namespace'
alias ka='kubectl apply -f'
alias kall='kubectl get pod,service,deployment,statefulset,ingress,Gateway,HTTPRoute,secret,ClusterIssuer,issuer,certificate,application'
alias kcgc='kubectl config get-contexts'
alias kgns='kubectl get namespaces'
alias kgp='kubectl get pods'
alias kgs='kubectl get service'
alias khelp='echo -ne "kubectl config get-contexts\nkubectl config use-context NAME\n"'
alias kp='kubectl proxy'
alias kpf='kubectl port-forward '
alias ksc='kubectl config set-context "$(kubectl config current-context)"'
alias kuc='kubectl config use-context'
#alias k9s='k9s -A'
alias kc='kctrl'

# tmux
alias ta='tmux attach-session -t'
alias tl='tmux list-sessions'
alias tn='tmux new-session -s'
alias pi='ssh 192.168.1.3'

# Docker
alias dco="docker compose"
alias dps="docker ps"
alias dpa="docker ps -a"
alias dl="docker ps -l -q"
alias dx="docker exec -it"

# Git
alias gc="git commit -m"
alias gca="git commit -a -m"
alias gp="git push origin HEAD"
alias gpu="git pull origin"
alias gst="git status"
#alias glog="git log --graph --topo-order --pretty='%w(100,0,6)%C(yellow)%h%C(bold)%C(black)%d %C(cyan)%ar %C(green)%an%n%C(bold)%C(white)%s %N' --abbrev-commit"
alias glog="git log --oneline --decorate --graph"
alias gdiff="git diff"
alias gco="git checkout"
alias gb='git branch'
alias gba='git branch -a'
alias gadd='git add'
alias ga='git add -p'
alias gcoall='git checkout -- .'
alias gr='git remote'
alias gre='git reset'

# python
alias pip='pip3'
alias py='python3'
alias python='python3'

# .oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"
#ZSH_THEME="powerlevel10k/powerlevel10k"

# autocomplete
#plugins=(
#git
#zsh-syntax-highlighting
#zsh-autosuggestions
#)
#source $ZSH/oh-my-zsh.sh

kctrl completion zsh > ~/.zsh/completions/_kctrl
fpath=(~/.zsh/completions $fpath)

autoload -U compinit && compinit

#source <(kubecolor completion zsh)

if [ $commands[conda] ]; then
  eval "$(conda shell.zsh hook)"
fi

eval "$(starship init zsh)"

function kubectl() {
  if [[ $1 == "completion" ]]; then
    command kubectl "$@"
  else
    kubecolor "$@"
  fi
}

function k() {
  if [[ $1 == "completion" ]]; then
    command kubectl "$@"
  else
    kubecolor "$@"
  fi
}

source <(kubectl completion zsh)
compdef k=kubectl

source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /opt/homebrew/opt/zsh-git-prompt/zshrc.sh

# bindkey
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey  "^[[H"   beginning-of-line
bindkey  "^[[F"   end-of-line
bindkey  "^[[3~"  delete-char

# .dotfiles
export DOTFILES=$HOME/.dotfiles
export PATH=/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/opt/homebrew/opt/util-linux/bin:/opt/homebrew/opt/util-linux/sbin:/opt/homebrew/opt/curl/bin:$PATH

function devup() {
  ITERM2_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"

  cd $DOTFILES && git pull > /dev/null 2>&1
  cd -

  [[ -d $HOME/.oh-my-zsh ]] || {
    source $DOTFILES/install.sh
    setup_oh_my_zsh
  }

  #[[ -f $HOME/.p10k.zsh ]] || {
  #  setup_p10k
  #}

  [[ -f $HOME/.dotfiles/vim/.vimrc ]] || {
    setup_vim
  }

  [[ -f $ITERM2_PLIST ]] || {
    setup_iterm2
  }
}

# tmux
function ts() {
  name=$1
  tmux has-session -t $name 2>/dev/null || tmux new-session -d -s $name
  tmux attach-session -t $name
}

# misc
function myips() {
  SHOW_IPV6=0
  if [[ "$1" == "--ipv6" ]] || [[ "$1" == "-6" ]]; then
    SHOW_IPV6=1
  fi

  for iface in $(ifconfig -l); do
    [[ $iface == "lo"* ]] && continue

      ipv4=$(ifconfig "$iface" | grep 'inet ' | awk '{print $2}')

      if [[ -n $ipv4 ]]; then
        echo "$iface (IPv4): $ipv4"
      fi

      if [[ $MYIPS_ONLY_IPV4 -eq 1 ]] && [[ $SHOW_IPV6 -eq 0 ]]; then
        continue
    fi

    ipv6=$(ifconfig "$iface" | grep 'inet6 ' | awk '{printf "%s ", $2}')
    if [[ -n $ipv6 ]]; then
      echo "$iface (IPv6): ${ipv6% }"
    fi
  done

  echo "public ip: $(extip)"
}

alias ls='lsd -ltr --group-dirs first'
alias l='lsd -ltr --group-dirs first'
alias ll='lsd -lh --group-dirs first'
alias lt='lsd -ltr --group-dirs first'
alias la='lsd -lAhtr --group-dirs first'
alias scp='scp -C'
alias extip='dig +time=1 +short @resolver1.opendns.com myip.opendns.com 2>/dev/null || curl ipinfo.io/ip'
alias tar=gtar
alias indent=gindent
alias sed=gsed
alias awk=gawk
alias which=gwhich
alias grep='/opt/homebrew/bin/ggrep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox}'
alias egrep='/opt/homebrew/bin/ggrep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox}'
alias extip='dig +time=1 +short @resolver1.opendns.com myip.opendns.com 2>/dev/null || curl ipinfo.io/ip'

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export EDITOR='vim'
export GPG_TTY=$(tty)

source $HOME/.dotfiles/zsh/custom.zsh

source <(fzf --zsh)

. "$HOME/.local/bin/env"

#[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
export HOMEBREW_PREFIX="/opt/homebrew";
export HOMEBREW_CELLAR="/opt/homebrew/Cellar";
export HOMEBREW_REPOSITORY="/opt/homebrew";

#fpath[1,0]="/opt/homebrew/share/zsh/site-functions";
#PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew/Caskroom/miniconda/base/envs/Orpheus-TTS/bin:/Users/rlucas/.local/bin:/opt/homebrew/Caskroom/miniconda/base/condabin:/Users/rlucas/.bun/bin:/usr/local/bin:/usr/local/sbin:/opt/homebrew/opt/util-linux/bin:/opt/homebrew/opt/util-linux/sbin:/opt/homebrew/opt/curl/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/Library/Apple/usr/bin:/Applications/Wireshark.app/Contents/MacOS:/usr/local/share/dotnet:~/.dotnet/tools:/opt/podman/bin:/Users/rlucas/.cache/lm-studio/bin"; export PATH;
[ -z "${MANPATH-}" ] || export MANPATH=":${MANPATH#:}";
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}";

# bun completions
[ -s "/Users/rlucas/.bun/_bun" ] && source "/Users/rlucas/.bun/_bun"

[[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

#source $HOME/.dotfiles/zsh/k8s.sh

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    else
        export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
    fi
fi
#export PATH="/opt/homebrew/Caskroom/miniconda/base/envs/coding-agent/bin:$PATH"
unset __conda_setup
# <<< conda initialize <<<

# opencode
export PATH=/Users/rlucas/.opencode/bin:$PATH

# commands-middleware plugin (moved to end to work with zsh-syntax-highlighting)
# Force reload of commands-middleware and its plugins on every source
unset COMMANDS_MIDDLEWARE_INITIALIZED &>/dev/null
unfunction commands_middleware_register commands_middleware_accept_line commands_middleware_setup_zle commands_middleware_restore commands_middleware_init commands_middleware_reload aws_middleware aws_fix_s3_uri aws_session_valid aws_refresh_session aws_mw_debug &>/dev/null

source $HOME/.dotfiles/zsh/commands-middleware.zsh
