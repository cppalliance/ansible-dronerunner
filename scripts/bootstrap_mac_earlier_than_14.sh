#!/bin/bash

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
# Set these variable before proceeding.
#
# Either point at a mirror holding the Xcode archives (recommended for a fleet,
# and it needs no Apple credentials on the machine):
: '
export XCODE_MIRROR=https://example.com/xcode
'
# or supply an Apple developer session cookie to download from Apple directly.
# Log in at https://developer.apple.com/download/all/ in a browser on any
# machine, then copy the value of the "myacinfo" cookie:
: '
export ADC_COOKIE="myacinfo=<value>"
'
# Apple's login (SRP plus 2FA) is the one part not worth reimplementing here,
# which is why the cookie is obtained elsewhere. Everything after it is a
# cookie-authenticated GET. The cookie is good for hours, not weeks, so for a
# long run of versions prefer XCODE_MIRROR.

# to test:
# to test:
if head -c1 "/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1; then
  echo "FDA enabled"
else
  echo "FDA NOT enabled. Full disk access for remote login." >&2
  exit 1
fi

# Common Ansible section:

set -xe
user=administrator
group=staff
sshdir=/Users/administrator/.ssh
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

if [ -z "$XCODE_MIRROR" ] && [ -z "$ADC_COOKIE" ]; then
  echo "Set either XCODE_MIRROR or ADC_COOKIE:
export XCODE_MIRROR=https://example.com/xcode
export ADC_COOKIE=\"myacinfo=...\"
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
        sudo softwareupdate -i "Command Line Tools for Xcode-13.4"
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

brew install htop
brew install wget
brew install cmake
brew install lcov
brew install valgrind || true
brew install doxygen
brew install ccache || true
brew install pkg-config
brew install openssl
brew install gcc
brew install aria2

if [[ "$(uname -p)" =~ "arm" ]]; then
    sudo mkdir -p /usr/local/opt
    sudo chown administrator:admin /usr/local/opt
    sudo mkdir -p /usr/local/bin
    sudo chown administrator:admin /usr/local/bin

    ln -s /opt/homebrew/opt/openssl /usr/local/opt/openssl
else
    opensslpackage=$(brew list | grep openssl | tail -n 1)
    ln -s /usr/local/opt/$opensslpackage /usr/local/opt/openssl || true
fi

# Xcode installation.
#
# These OS versions can run neither xcodes (the 2.x binary requires macOS 13)
# nor the xcode-install gem's "xcversion" (abandoned, and its Apple login no
# longer works). Downloading and expanding the archive by hand is all those
# tools were doing for us, so do that instead.

xcode_url() {
    # Apple lays the archives out predictably:
    #   Developer_Tools/Xcode_<version>/Xcode_<version>.<xip or dmg>
    # with any trailing ".0" dropped, and .dmg for Xcode 7 and earlier. This
    # matches every release from 6.2 through 16.x listed at
    # https://xcodereleases.com/data.json , which is where to look if a version
    # ever deviates. Xcode 26 does deviate: those filenames carry an extra
    # _Universal or _Apple_silicon suffix.
    local version="${1%.0}"
    local extension="xip"
    case "$version" in
        [1-7] | [1-7].* ) extension="dmg" ;;
    esac
    echo "https://download.developer.apple.com/Developer_Tools/Xcode_${version}/Xcode_${version}.${extension}"
}

xcode_download() {
    local url="$1" dest="$2"
    local path jar cookie

    if [ -n "$XCODE_MIRROR" ]; then
        curl -fL --retry 3 -C - -o "$dest" "${XCODE_MIRROR%/}/$(basename "$url")"
        return
    fi

    # Apple hands out a short-lived ADCDownloadAuth cookie per download path,
    # in exchange for the session cookie. Both are then sent to the CDN.
    path="${url#https://download.developer.apple.com}"
    jar=$(mktemp /tmp/adc-cookies.XXXXXX)
    set +x
    curl -fsS -o /dev/null -c "$jar" -H "Cookie: $ADC_COOKIE" \
        "https://developerservices2.apple.com/services/download?path=${path}"
    cookie="$ADC_COOKIE; ADCDownloadAuth=$(awk '$6 == "ADCDownloadAuth" { print $7 }' "$jar" | tail -n 1)"
    if command -v aria2c > /dev/null ; then
        aria2c -x 8 -s 8 --continue --header "Cookie: $cookie" \
            -d "$(dirname "$dest")" -o "$(basename "$dest")" "$url"
    else
        curl -fL --retry 3 -C - -H "Cookie: $cookie" -o "$dest" "$url"
    fi
    set -x
    rm -f "$jar"
}

xcode_install() {
    local version="$1"
    local url archive workdir app mountpoint

    url=$(xcode_url "$version")

    # Needs room for the archive plus the expanded app, roughly 25GB for
    # recent versions.
    workdir=$(mktemp -d /tmp/xcode-install.XXXXXX)
    archive="$workdir/$(basename "$url")"
    xcode_download "$url" "$archive"

    # An expired cookie or a wrong version number redirects to an HTML page,
    # which curl saves as if it were the archive. Xcode .xip files are signed
    # xar archives, so check for the xar magic before spending time on it.
    if [ "${archive##*.}" = "xip" ] && [ "$(head -c 4 "$archive")" != "xar!" ]; then
        echo "$archive is not an Xcode archive. Refresh ADC_COOKIE and retry."
        return 1
    fi

    case "$archive" in
        *.xip)
            (cd "$workdir" && xip --expand "$archive")
            ;;
        *.dmg)
            # Xcode 7.3.1 and earlier shipped as disk images.
            mountpoint="$workdir/mnt"
            hdiutil attach -nobrowse -quiet -mountpoint "$mountpoint" "$archive"
            cp -R "$mountpoint"/*.app "$workdir"/
            hdiutil detach -quiet "$mountpoint"
            ;;
    esac

    app=$(find "$workdir" -maxdepth 1 -name '*.app' | head -n 1)
    if [ -z "$app" ]; then
        echo "No .app found after expanding $archive"
        return 1
    fi

    sudo mv "$app" "/Applications/Xcode-$version.app"
    sudo xattr -dr com.apple.quarantine "/Applications/Xcode-$version.app" || true
    rm -rf "$workdir"
}

# if [[ "$(sw_vers -productVersion)" =~ "12.4" ]] ; then
if [[ $(sw_vers -productVersion) =~ ^12 ]] || [[ $(sw_vers -productVersion) =~ ^13 ]] ; then
    xcodeversions="12.5 12.5.1 13.0 13.1 13.2 13.2.1 13.3 13.3.1 13.4 13.4.1 14.0 14.1"
    gccversion="12"
    pythonversion="3.9"
    brew install python
    if [[ "$(uname -p)" == "arm" ]]; then
        ln -s /opt/homebrew/bin/python3 /usr/local/bin/python3
        ln -s /usr/local/bin/python3 /usr/local/bin/python
    else
        ln -s /usr/local/bin/python${pythonversion} /usr/local/bin/python3
        ln -s /usr/local/bin/python3 /usr/local/bin/python
    fi

    if [[ "$(uname -p)" == "arm" ]]; then
        ln -s /opt/homebrew/bin/g++-$gccversion /usr/local/bin/
        ln -s /opt/homebrew/bin/gcc-$gccversion /usr/local/bin/
        ln -s /opt/homebrew/bin/gcov-$gccversion /usr/local/bin/
    fi

    # xcode-install and its fastlane authentication are no longer used.
    # xcode_install below downloads from XCODE_MIRROR or from Apple with
    # ADC_COOKIE instead.
    # sudo xcrun gem install xcode-install --no-document

    for xcodeversion in $xcodeversions; do
        if [ ! -d /Applications/Xcode-$xcodeversion.app ]; then
            xcode_install $xcodeversion
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
    sudo xcode-select -switch /Applications/Xcode-12.5.app/Contents/Developer
    sudo xcodebuild -license accept
    sudo xcode-select -switch /Applications/Xcode-13.0.app/Contents/Developer
    sudo xcodebuild -license accept
    sudo xcode-select -switch /Applications/Xcode-13.4.1.app/Contents/Developer
    sudo xcodebuild -license accept

    brew install bash
    if [ ! -f /usr/local/bin/bash ]; then
        ln -s /opt/homebrew/bin/bash /usr/local/bin/
    fi
fi

if [[ "$(sw_vers -productVersion)" =~ "10.15" ]] ; then
    xcodeversions="10 10.1 10.2 10.3 11 11.1 11.2 11.2.1 11.3 11.4 11.5 11.6 11.7 12 12.1 12.2 12.3 12.4"
    # sudo xcrun gem install xcode-install --no-document
    for xcodeversion in $xcodeversions; do
        if [ ! -d /Applications/Xcode-$xcodeversion.app ]; then
            xcode_install $xcodeversion
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
    # sudo xcrun gem install xcode-install --no-document
    for xcodeversion in $xcodeversions; do
        if [ ! -d /Applications/Xcode-$xcodeversion.app ]; then
            xcode_install $xcodeversion
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
