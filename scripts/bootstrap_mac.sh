#!/bin/bash

# Notes:
# In development. Each time the script is run it's being rechecked and debugged.
#
# Purpose:
# - Sets up ssh and sudo. Although, that might already have been done.
# - Installs multiple versions of Xcode.
# - Installs other packages needed by drone jobs.
#
# Set these variable before proceeding:
: '
export XCODE_INSTALL_USER=
export XCODE_INSTALL_PASSWORD=
or
export FASTLANE_USER=
export FASTLANE_PASSWORD=

Log into VNC. Set at least 16b resolution. Have a desktop session running.
'

# Common Ansible section:

set -xe
user=administrator
group=staff
sshdir=/Users/administrator/.ssh
pubkey1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCH0oawPzIylSjdu/fpyDD2i2stkqe52bFmLT8+MeiTAp5WI8BwlbeeiiZkneEHhLW7bGMKZ50rQONjiudWCFibb4zM2pUQTFP91BuzUG7MjFf179UlvRMUiNSYkKSSB4q0QZ8+2Vjj5lXzYxM5FjZ9FdA1ioI5l8TK8rLlf/F1TKKDfjA/YMk7769BVYndDilSidaDEvRVxQM8Z5RBUnSnDFQwEaVOuVaHIki0ZPVecwyE96e2HaFDRjNlMUZbSgHrdwkjbIugaUfiWFANBA5eIOka19CSLV5aY1tNeawoUvIBsRXjUleFJE+EIL0iGcuTcLXvAqh5UwFdMkkwUfhH drone-runner"

if [ -z "$FASTLANE_USER" ] || [ -z "FASTLANE_PASSWORD" ]; then
  echo "Set both FASTLANE_USER and FASTLANE_PASSWORD:
export FASTLANE_USER=
export FASTLANE_PASSWORD=
"
exit 1
fi

if [ ! -f /etc/sudoers.d/$user ]; then
    sudo echo "$user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$user
    echo "You may need to logout and login again before continuing."
    # exit 0
fi

mkdir -p $sshdir
echo "$pubkey1" > $sshdir/authorized_keys
chmod -R 700 $sshdir
chown -R $user:$group $sshdir

# ##########################################################################

# XCode and other packages:

# Install brew
if [ ! -f /usr/local/bin/brew ]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
fi

brew install htop
brew install wget
brew install cmake
brew install lcov
brew install valgrind || true
brew install doxygen
brew install ccache || true
brew install pkg-config
brew install openssl

opensslpackage=$(brew list | grep openssl | tail -n 1)
ln -s /usr/local/opt/$opensslpackage /usr/local/opt/openssl

if [[ "$(sw_vers -productVersion)" =~ "10.15" ]] ; then
    xcodeversions="10 10.1 10.2 10.3 11 11.1 11.2 11.2.1 11.3 11.4 11.5 11.6 11.7 12 12.1 12.2 12.3 12.4"
    sudo xcrun gem install xcode-install --no-document
    # 2022-03-07 latest experiment, will this happen automatically if needed?
    # That is, will it prompt you for a login and 2FA.
    # if [ ! -d /Users/administrator/.fastlane/spaceship ]; then
    #     echo "Configuring auth"
    #     read -p "Apple user name:" appleuser
    #     fastlane spaceauth -u $appleuser
    #     read -p "Do you wish to continue?" yn
    # fi
    for xcodeversion in $xcodeversions; do
        if [ ! -d /Applications/Xcode-$xcodeversion.app ]; then
            xcversion install $xcodeversion --no-switch
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
    sudo xcode-select -switch /Applications/Xcode-11.7.app/Contents/Developer
    sudo xcodebuild -license accept
    sudo xcode-select -switch /Applications/Xcode-12.3.app/Contents/Developer
    sudo xcodebuild -license accept

    brew install bash
fi

if [[ "$(sw_vers -productVersion)" =~ "10.13" ]] ; then
    xcodeversions="6.4 7 7.1 7.2 7.3 8 8.1 8.2 8.3 8.3.2 8.3.3 9 9.1 9.2 9.3 9.4 9.4.1"
    brew install git
    brew install ruby@2.7
    if grep /usr/local/lib/ruby/gems ~/.profile; then
        echo PATH already found in .profile
    else
        echo Updating PATH in .profile
        echo 'export PATH=/usr/local/lib/ruby/gems/2.7.0/bin:/usr/local/opt/ruby@2.7/bin:$PATH' >> ~/.profile
        export PATH=/usr/local/lib/ruby/gems/2.7.0/bin:/usr/local/opt/ruby@2.7/bin:$PATH
    fi
    sudo xcrun gem install xcode-install --no-document
    # 2022-03-07 latest experiment, will this happen automatically if needed?
    # That is, will it prompt you for a login and 2FA.
    # if [ ! -d /Users/administrator/.fastlane/spaceship ]; then
    #     # 2022-03, still experimenting in this section.
    #     echo "Configuring auth"
    #     read -p "Apple user name:" appleuser
    #     fastlane spaceauth -u $appleuser
    #     read -p "Do you wish to continue?" yn
    # fi
    for xcodeversion in $xcodeversions; do
        if [ ! -d /Applications/Xcode-$xcodeversion.app ]; then
            xcversion install $xcodeversion --no-switch
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
    # may not be necessary:
    ln -s Xcode-6.4.app Xcode-6.app
    # one repo references this:
    ln -s Xcode-8.app Xcode-8.0.app

    sudo xcode-select -switch /Applications/Xcode-9.4.1.app/Contents/Developer
    sudo mv /Library/Developer/CommandLineTools /Library/Developer/CommandLineTools.bck
    sudo xcodebuild -license accept
fi

sudo xcrun gem install coveralls-lcov --no-document
sudo xcrun gem install asciidoctor --no-document
sudo xcrun gem install asciidoctor-pdf --no-document
sudo xcrun gem install coderay --no-document
