#!/bin/bash

# Version of script for MacOS 14

# Purpose:
# - Sets up ssh and sudo. Although, that might already have been done.
# - Installs multiple versions of Xcode.
# - Installs other packages needed by drone jobs.
#
# Instructions:
#
# Log into VNC. Set at least 16b resolution. Have a desktop session running.
#
# Enable ssh to have more permissions:
# System Preferences -> Sharing , Remote Login, check the box Allow full disk access for remote users
#
# Set these variable before proceeding:
: '
export XCODES_USERNAME=
export XCODES_PASSWORD=
'

# Common Ansible section:

set -xe
user=administrator
group=staff
sshdir=/Users/${user}/.ssh
pubkey1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCH0oawPzIylSjdu/fpyDD2i2stkqe52bFmLT8+MeiTAp5WI8BwlbeeiiZkneEHhLW7bGMKZ50rQONjiudWCFibb4zM2pUQTFP91BuzUG7MjFf179UlvRMUiNSYkKSSB4q0QZ8+2Vjj5lXzYxM5FjZ9FdA1ioI5l8TK8rLlf/F1TKKDfjA/YMk7769BVYndDilSidaDEvRVxQM8Z5RBUnSnDFQwEaVOuVaHIki0ZPVecwyE96e2HaFDRjNlMUZbSgHrdwkjbIugaUfiWFANBA5eIOka19CSLV5aY1tNeawoUvIBsRXjUleFJE+EIL0iGcuTcLXvAqh5UwFdMkkwUfhH drone-runner"

if [ ! -f /etc/sudoers.d/$user ]; then
    sudo echo "$user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$user
    echo "You may need to logout and login again before continuing."
    # exit 0
fi

mkdir -p $sshdir
echo "$pubkey1" > $sshdir/authorized_keys
chmod -R 700 $sshdir
chown -R $user:$group $sshdir

####

user=cppal
group=staff

# sysadminctl -addUser ${user} -fullName ${user} -shell /bin/bash -password ${password} -home /Users/${user}
sysadminctl -addUser ${user} -fullName ${user} -shell /bin/bash -home /Users/${user}
mkdir -p /Users/${user}
chown ${user}:${group} /Users/${user}
dscl . -append /Groups/admin GroupMembership ${user}
sshdir=/Users/${user}/.ssh
# pubkey1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCH0oawPzIylSjdu/fpyDD2i2stkqe52bFmLT8+MeiTAp5WI8BwlbeeiiZkneEHhLW7bGMKZ50rQONjiudWCFibb4zM2pUQTFP91BuzUG7MjFf179UlvRMUiNSYkKSSB4q0QZ8+2Vjj5lXzYxM5FjZ9FdA1ioI5l8TK8rLlf/F1TKKDfjA/YMk7769BVYndDilSidaDEvRVxQM8Z5RBUnSnDFQwEaVOuVaHIki0ZPVecwyE96e2HaFDRjNlMUZbSgHrdwkjbIugaUfiWFANBA5eIOka19CSLV5aY1tNeawoUvIBsRXjUleFJE+EIL0iGcuTcLXvAqh5UwFdMkkwUfhH drone-runner"
if [ ! -f /etc/sudoers.d/${user} ]; then
    sudo echo "$user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$user
fi
mkdir -p $sshdir
echo "$pubkey1" > $sshdir/authorized_keys
chmod -R 700 $sshdir
chown -R $user:$group $sshdir

#####

if [ -z "$XCODES_USERNAME" ] || [ -z "$XCODES_PASSWORD" ]; then
  echo "Set both XCODES_USERNAME and XCODES_PASSWORD:
export XCODES_USERNAME=
export XCODES_PASSWORD=
"
exit 1
fi

# ##########################################################################

# XCode and other packages:

# Check if /Library/Developer/CommandLineTools is installed. This is a new requirement and it's unclear which OS versions it should apply to.

if [[ "$(uname -p)" =~ "arm" ]]; then
    if xcode-select -p; then
        echo "CommandLineTools are already installed"
    else
        sudo softwareupdate -l
        sudo softwareupdate -i "Command Line Tools for Xcode-15.0"
    fi
fi

# Install brew

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
if command -v brew ; then
    echo "Brew already installed"
else
    echo "Install brew"
    set +x
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    set -x
fi

# Brew recommendation:
shell_initialization_file=/Users/administrator/.profile
if [ grep "brew" ${shell_initialization_file} ];then
    echo "brew already in startup"
else
    echo "adding brew to startup"
    (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> /Users/administrator/.zprofile
fi

eval "$(/opt/homebrew/bin/brew shellenv)"
#
# Previously I used
# .zshrc:   export PATH=/opt/homebrew/bin:$PATH

brew install htop
brew install nload
brew install wget
brew install cmake
brew install lcov
brew install valgrind || true
brew install doxygen
brew install ccache || true
brew install pkg-config
brew install openssl
brew install gcc

if [[ "$(uname -p)" =~ "arm" ]]; then
    sudo mkdir -p /usr/local/opt
    sudo chown administrator:admin /usr/local/opt
    sudo mkdir -p /usr/local/bin
    sudo chown administrator:admin /usr/local/bin

    ln -s /opt/homebrew/opt/openssl /usr/local/opt/openssl || true
else
    opensslpackage=$(brew list | grep openssl | tail -n 1)
    ln -s /usr/local/opt/$opensslpackage /usr/local/opt/openssl || true
fi

expect_commands='
set timeout -1
spawn fastlane spaceauth
expect "Please enter the 6 digit code:"
send -- "sms\n"
expect "Please select a trusted phone number"
send -- "1\n"
expect "Please enter the 6 digit code"
expect_user -re "(.*)\n"
send "$expect_out(1,string)\r"
expect "Should fastlane copy the cookie into your clipboard"
send -- "no\n"
expect eof
'


if [[ $(sw_vers -productVersion) =~ ^14 ]] ; then

    xcodeversions="14.2.0 14.3.0 14.3.1 15.0.0 15.0.1"
    gccversion="13"
    pythonversion="3.11"
    brew install python
    if [[ "$(uname -p)" == "arm" ]]; then
        ln -s /opt/homebrew/bin/python3 /usr/local/bin/python3 || true
        ln -s /usr/local/bin/python3 /usr/local/bin/python || true
    else
        ln -s /usr/local/bin/python${pythonversion} /usr/local/bin/python3 || true
        ln -s /usr/local/bin/python3 /usr/local/bin/python || true
    fi

    if [[ "$(uname -p)" == "arm" ]]; then
        ln -s /opt/homebrew/bin/g++-$gccversion /usr/local/bin/ || true
        ln -s /opt/homebrew/bin/gcc-$gccversion /usr/local/bin/ || true
        ln -s /opt/homebrew/bin/gcov-$gccversion /usr/local/bin/ || true
    fi

    brew install xcodesorg/made/xcodes

    # fastlane per se is obsolete.
    # A very similar expect script might be made to work with xcodes because it follows a similar set of steps.

    # if [ ! -d ~/.fastlane ]; then
    # echo "\n\n Now running 'fastlane spaceauth' to authenticate with Apple. Check your sms messages. \n\n"
# expect -c "${expect_commands//
# /;}"
#    fi

    for xcodeversion in $xcodeversions; do
        if [ ! -d /Applications/Xcode-$xcodeversion.app ]; then
            xcodes install --no-superuser $xcodeversion
        else
            echo "Directory /Applications/Xcode-$xcodeversion.app already exists."
        fi
        # and then check the result
        if [ ! -d /Applications/Xcode-$xcodeversion.app ]; then
            echo "Failed to install /Applications/Xcode-$xcodeversion.app"
            exit 1
        fi
    done

    cd /Applications

    if [ -d /Library/Developer/CommandLineTools ]; then
        sudo mv /Library/Developer/CommandLineTools /Library/Developer/CommandLineTools.bck
    fi
    sudo xcode-select -switch /Applications/Xcode-15.0.0.app/Contents/Developer
    sudo xcodebuild -license accept
    # sudo xcode-select -switch /Applications/Xcode-14.2.0.app/Contents/Developer
    # sudo xcodebuild -license accept

    brew install bash
    if [ ! -f /usr/local/bin/bash ]; then
        ln -s /opt/homebrew/bin/bash /usr/local/bin/
    fi
fi

brew install ruby
ln -s /opt/homebrew/opt/ruby/bin/ruby /usr/local/bin/ruby  || true
ln -s /opt/homebrew/opt/ruby/bin/gem /usr/local/bin/gem || true
which ruby
which gem
sudo gem install asciidoctor-pdf --no-document
sudo gem install coveralls-lcov --no-document
sudo gem install asciidoctor --no-document
sudo gem install coderay --no-document


