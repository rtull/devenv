#!/usr/bin/env bash
set -e

made_changes=
echo "==> Checking dependencies"

##############################
# declare internal functions

function assert_tap {
    echo "==> Checking tap $1"
    
    if ! brew tap | grep "$1" > /dev/null 2>&1; then
        echo "==> Installing brew $1"
        brew tap "$1" > /dev/null

        made_changes=1
    fi
}

function assert_pack {
    echo "==> Checking pack $1"
    
    if ! brew list "$1" > /dev/null 2>&1; then
        echo "==> Installing brew $1"
        brew install "$1" > /dev/null

        made_changes=1
    fi
}

function assert_cask {
    echo "==> Checking cask $1"
    
    if ! brew cask list "$1" > /dev/null 2>&1 ; then
        echo "==> Installing cask "$1""
        brew cask install "$1" > /dev/null

        made_changes=1
    fi
}

##############################
# install major tooling

# install developer tools if not present
echo "==> Checking command line tools"
if ! xcode-select -p > /dev/null 2>&1; then
    echo "==> Finding command line tools package"
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    xcode_package=$(softwareupdate -l | grep '* Command Line' | head -n1 | sed -E 's/ +\* //g')
    
    echo "==> Installing $xcode_package"
    softwareupdate -i "$xcode_package" -v
    
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    made_changes=1
fi

# install brew if not present
echo "==> Checking brew package manager"
if ! which brew > /dev/null; then
    echo "==> Installing brew package manager"
    curl -s https://raw.githubusercontent.com/Homebrew/install/master/install | ruby > /dev/null 2>&1
    brew doctor

    made_changes=1
fi

##############################
# install dependencies

if [[ ! -d /usr/local/bin ]]; then
    sudo mkdir -p /usr/local/bin
    made_changes=1
fi

if [[ "$(stat -f "%u" /usr/local/bin/)" != "$(id -u)" ]]; then
    sudo chown $(whoami):admin /usr/local/bin
    made_changes=1
fi

# general tooling
assert_pack ack
assert_pack bash-completion
assert_pack git
assert_pack mysql
assert_pack pv
assert_pack perl    # no El Capitan support yet
assert_pack redis
assert_pack ruby
assert_pack tree
assert_pack wget

assert_tap homebrew/php
assert_pack homebrew/php/php56
assert_pack homebrew/php/php56-mcrypt
assert_pack homebrew/php/php56-redis    # no El Capitan support yet
assert_pack homebrew/php/php56-intl

# virtualization tech
assert_tap caskroom/cask
assert_pack caskroom/cask/brew-cask

assert_cask vagrant
assert_tap homebrew/completions
assert_pack homebrew/completions/vagrant-completion

assert_cask virtualbox

##############################
# verify server link and mount

echo "==> Checking /server for environment setup"

if [[ ! -d /server ]] && [[ -L /server ]]; then
    >&2 echo "Warning: /server is a dead symbolic link pointing to nowhere. Removing and moving on..."
    sudo rm -f /server
    made_changes=1
fi

# nothing is at /server, so begin setup by creating it
if [[ ! -d /server ]] && [[ ! -L /server ]]; then
    if [[ -d "/Volumes/Server" ]]; then
        echo "==> Creating /server -> /Volumes/Server symbolic link"
        sudo ln -s /Volumes/Server /server
        made_changes=1
    else
        >&2 echo "Warning: Failed to detect /Volumes/Server mount. Creating directory at /server instead"
        sudo mkdir /server
        made_changes=1
    fi
fi

if [[ -d /server ]] && [[ ! -L /server ]]; then
    >&2 echo "Warning: /server is a directory. This may cause case-insensitivity issues in virtual machines"
fi

# create /sites link if not exists
if [[ ! -d /sites ]] && [[ ! -L /sites ]]; then
    echo "==> Creating /sites -> /server/sites symbolic link"
    sudo ln -s /server/sites /sites
    made_changes=1
fi

# verify /server is empty (barring system dotfiles) and hasn't been git inited
if [[ ! "$(ls /server | head -n1)" ]] && [[ ! -f /server/.git/config ]] ; then
    echo "==> Installing environment at /server"
    sudo chown $(whoami):admin /server
    cd /server
    git init -q
    git remote add origin https://github.com/davidalger/devenv.git
    git fetch -q origin
    git checkout -q master
    vagrant status
    echo "==> Please run `source /etc/profile` in your shell before starting vagrant"

    made_changes=1
elif [[ ! -f /server/vagrant/vagrant.rb ]]; then
    >&2 echo "Error: /server is not empty, but does not appear to be setup either. Moving on..."
fi

##############################
# install composer (must come after /server creation)
echo "==> Checking for composer"
if [[ ! -x /usr/local/bin/composer ]]; then
    echo "==> Installing composer"
    mkdir -p /server/.shared/composer
    wget -q https://getcomposer.org/composer.phar -O /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    made_changes=1
fi

##############################
# inform user and exit
if [ $made_changes ]; then
    echo "Process Complete!"
else
    echo "Nothing to do!"
fi
