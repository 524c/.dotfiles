if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# zsh
autoload -Uz compinit && compinit
setopt nocorrectall
setopt APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_IGNORE_SPACE
setopt HIST_NO_STORE
setopt SHARE_HISTORY
setopt AUTO_CD
unsetopt EQUALS

HISTFILE=$HOME/.zhistory
SAVEHIST=10000
HISTSIZE=10000

zstyle ':omz:update' frequency 13

# K8S
export KUBECONFIG=$HOME/.kube/config
alias k="kubecolor"
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
alias kubectl=kubecolor
alias kuc='kubectl config use-context'

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
alias glog="git log --graph --topo-order --pretty='%w(100,0,6)%C(yellow)%h%C(bold)%C(black)%d %C(cyan)%ar %C(green)%an%n%C(bold)%C(white)%s %N' --abbrev-commit"
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
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
git
zsh-syntax-highlighting
zsh-autosuggestions
)

source $ZSH/oh-my-zsh.sh
[[ ! -e $HOME/.p10k.zsh ]] || source $HOME/.p10k.zsh

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

  [[ -f $HOME/.p10k.zsh ]] || {
    setup_p10k
  }

  [[ -f $HOME/.dotfiles/vim/.vimrc ]] || {
    setup_vim
  }

  [[ -f $ITERM2_PLIST ]] || {
    setup_iterm2
  }
}

# tmux
function ts() {
  tmux has-session -t $1 2>/dev/null || tmux new-session -d -s $1
  tmux attach-session -t $1
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

alias ls='lsd --group-dirs first'
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

tmux has-session -t session1 2>/dev/null || tmux new-session -d -s session1
