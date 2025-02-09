#!/usr/bin/env bash

function update_sudoers() {
  if ! sudo grep -q "^%admin.*NOPASSWD" /etc/sudoers; then
    if sudo grep -q "^%admin.*ALL" /etc/sudoers; then
      if sed --version 2>&1 | grep -q "GNU"; then
        sudo sed -i 's/^%admin.*ALL/%admin ALL=(ALL) NOPASSWD:ALL/' /etc/sudoers
      else
        sudo sed -i '' 's/^%admin.*ALL/%admin ALL=(ALL) NOPASSWD:ALL/' /etc/sudoers
      fi
    elif sudo grep -q "^#.*%admin.*NOPASSWD" /etc/sudoers; then
      if sed --version 2>&1 | grep -q "GNU"; then
        sudo sed -i 's/^#.*%admin.*NOPASSWD/%admin ALL=(ALL) NOPASSWD:ALL/' /etc/sudoers
      else
        sudo sed -i '' 's/^#.*%admin.*NOPASSWD/%admin ALL=(ALL) NOPASSWD:ALL/' /etc/sudoers
      fi
    else
      echo "%admin ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers > /dev/null
    fi
  fi
}

function install_apps() {
  brew update > /dev/null 2>&1
  app_names=(
    "iterm2:iTerm.app"
    "visual-studio-code:Visual Studio Code.app"
    "firefox:Firefox.app"
    "docker:Docker.app"
  )

  for app_name in "${app_names[@]}"
  do
    package="${app_name%%:*}"
    application="${app_name#*:}"

    if ! [ -d "/Applications/$application" ]; then
      brew install --cask --force "$package"
    else
      echo "The application $application is already installed in /Applications"
    fi
  done

  brew install coreutils binutils diffutils gawk gnutls screen tmux watch wget curl gpatch m4             \
    make gcc vim nano file-formula git less openssh perl python3 rsync zsh ffmpeg ed findutils            \
    wdiff grep gnu-indent gnu-sed gnu-tar unzip gzip xz gnu-which fswatch lsusb fsevents-tools            \
    openssl brotli base64 mkcert redis htop btop go tanka jsonnet-bundler readline pyenv pyenv-virtualenv \
    pgcli jq tldr kubectl kubecolor tcpdump libassuan gnupg unxip lsd > /dev/null 2>&1
}

function install_fonts() {
  brew install --cask font-hack-nerd-font
}

function setup_iterm2() {
  ITERM2_PLIST="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
  [ -f "$ITERM2_PLIST" ] && cp "$ITERM2_PLIST" "${ITERM2_PLIST}.bak"

  # convert from binary to xml
  # plutil -convert xml1 -o iterm2_prefs.xml $ITERM2_PLIST

  plutil -convert binary1 $HOME/.dotfiles/iterm2/iterm2_prefs.xml -o "$ITERM2_PLIST"
}

function setup_vim () {
  [ -f $HOME/.vimrc ] && cp $HOME/.vimrc $HOME/.vimrc.bak
  [ -e $HOME/.vimrc ] && rm $HOME/.vimrc
  ln -s $HOME/.dotfiles/vim/.vimrc $HOME/.vimrc
  sudo cp $HOME/.vimrc /var/root/
}

function setup_oh_my_zsh() {
  export ZSH="$HOME/.oh-my-zsh"
  export ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

  [ -e $HOME/.oh-my-zsh_old ] && rm -rf $HOME/.oh-my-zsh_old
  [ -e $HOME/.zshrc.bak ] && rm -f $HOME/.zshrc.bak
  [ -e $HOME/.oh-my-zsh ] && mv $HOME/.oh-my-zsh $HOME/.oh-my-zsh_old

  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  if [ ! -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]; then
    git clone https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM}/themes/powerlevel10k
  fi

  ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
  if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
  fi

  if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
  fi

  [ -f $HOME/.zshrc ] && cp $HOME/.zshrc $HOME/.zshrc.bak
  [ -e $HOME/.zshrc ] && rm $HOME/.zshrc

  ln -s $HOME/.dotfiles/zshrc/.zshrc $HOME/.zshrc

  [ -e $HOME/.dotfiles/zsh/custom.zsh ] || {
    mkdir -p $HOME/.dotfiles/zsh
    cat << EOF > $HOME/.dotfiles/zsh/custom.zsh
# placeholder for user custom configurations

# alias x="x"
# export x="xxxx"
EOF
  }
}

function setup_zsh() {
  [[ $(dscl . -read /Users/$USER UserShell | awk '{print $2}') == "/opt/homebrew/bin/zsh" ]] || {
    echo "Setting zsh as the default shell"
    sudo dscl . -create /Users/$USER UserShell /opt/homebrew/bin/zsh
  }
}

function setup_p10k() {
  [ -e $HOME/.p10k.zsh.bak ] && rm -f $HOME/.p10k.zsh.bak

  [ -f $HOME/.p10k.zsh ] && mv $HOME/.p10k.zsh $HOME/.p10k.zsh.bak
  [ -e $HOME/.p10k.zsh ] && rm $HOME/.p10k.zsh

  ln -s $HOME/.dotfiles/p10k/.p10k.zsh $HOME/.p10k.zsh
}

function clone_dotfiles() {
  git clone https://github.com/524c/.dotfiles $HOME/.dotfiles
}

function setup_tmux() {
  [ -d $HOME/.tmux_old ] && rm -rf $HOME/.tmux_old
  [ -d $HOME/.tmux ] && mv $HOME/.tmux $HOME/.tmux_old
  [ -e $HOME/.tmux.conf.bak ] && rm $HOME/.tmux.conf.bak
  [ -e $HOME/.tmux.conf ] && mv $HOME/.tmux.conf $HOME/.tmux.conf.bak
  mkdir -p $HOME/.tmux/plugins
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
  ln -s $HOME/.dotfiles/tmux/.tmux.conf $HOME/.tmux.conf
}

export PATH=/usr/local/bin:/usr/local/sbin:/opt/homebrew/opt/curl/bin:/bin:/sbin:/usr/bin:/usr/sbin:/opt/homebrew/bin

[[ $(uname) == "Darwin" ]] || {
  echo "This script is for macOS only."
  exit 1
}

[[ ! -x /opt/homebrew/bin/brew ]] && {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
}
brew update > /dev/null 2>&1

option=$1
if [[ $option != "--reinstall" ]] &&  [[ -f $HOME/.dotfiles/install.sh ]]; then
  echo "The setup was done previously. Do you want to redo it? [y/n]"
  read -r r
  [[ $r == "y" ]] || exit 0
  [ -e $HOME/.dotfiles_old ] && rm -rf $HOME/.dotfiles_old
  mv $HOME/.dotfiles $HOME/.dotfiles_old
fi

clone_dotfiles
update_sudoers
install_apps
install_fonts
setup_zsh
setup_oh_my_zsh
setup_p10k
setup_vim
setup_iterm2
setup_tmux

echo -e "\nQuit Terminal and reopen it to apply the changes.\nUsage: devup to update the dotfiles."
