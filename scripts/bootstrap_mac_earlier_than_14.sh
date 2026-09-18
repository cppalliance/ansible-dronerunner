#!/bin/bash

set -xe

# Purpose:
# - Sets up ssh and sudo. Although, that might already have been done.
# - Installs multiple versions of Xcode.
# - Installs other packages needed by drone jobs.
#
# Instructions:
#
# Log into VNC. Set at least 16b resolution. Have a desktop session running.
#
# Enable ssh to have more permissions. On these releases that is not the
# checkbox under Remote Login, which does not exist before Ventura: add
# /usr/libexec/sshd-keygen-wrapper to System Preferences -> Security & Privacy
# -> Privacy -> Full Disk Access. See docs/FDA.md.
#
# Nothing is downloaded from Apple here. Run scripts/downloader.sh on a macOS
# 26 host, which can still authenticate, and copy the archives over first:
#
#     scp *.xip administrator@<this host>:/Applications/downloads/
#
# Set this only if they live somewhere other than /Applications/downloads, an
# external disk say:
: '
export XCODE_DOWNLOADS=/Volumes/xcode
'

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

####

if true ; then
    user=cppal
    group=staff

    # sysadminctl -addUser ${user} -fullName ${user} -shell /bin/bash -password ${password} -home /Users/${user}
    sudo sysadminctl -addUser ${user} -fullName ${user} -shell /bin/bash -home /Users/${user}
    sudo mkdir -p /Users/${user}
    sudo chown ${user}:${group} /Users/${user}
    sudo dscl . -append /Groups/admin GroupMembership ${user}
    sshdir=/Users/${user}/.ssh
    # pubkey1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCH0oawPzIylSjdu/fpyDD2i2stkqe52bFmLT8+MeiTAp5WI8BwlbeeiiZkneEHhLW7bGMKZ50rQONjiudWCFibb4zM2pUQTFP91BuzUG7MjFf179UlvRMUiNSYkKSSB4q0QZ8+2Vjj5lXzYxM5FjZ9FdA1ioI5l8TK8rLlf/F1TKKDfjA/YMk7769BVYndDilSidaDEvRVxQM8Z5RBUnSnDFQwEaVOuVaHIki0ZPVecwyE96e2HaFDRjNlMUZbSgHrdwkjbIugaUfiWFANBA5eIOka19CSLV5aY1tNeawoUvIBsRXjUleFJE+EIL0iGcuTcLXvAqh5UwFdMkkwUfhH drone-runner"
    if [ ! -f /etc/sudoers.d/${user} ]; then
        sudo echo "$user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$user
    fi
    sudo mkdir -p $sshdir
    sudo echo "$pubkey1" | sudo tee $sshdir/authorized_keys
    sudo chmod -R 700 $sshdir
    sudo chown -R $user:$group $sshdir
fi

#####

xcodearchives="${XCODE_DOWNLOADS:-/Applications/downloads}"

if [ ! -d "$xcodearchives" ]; then
  echo "No Xcode archives at $xcodearchives .
Run scripts/downloader.sh on a macOS 26 host, copy the .xip files here, or set
XCODE_DOWNLOADS to wherever they already are.
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

# Catalina needs brew pinned at both ends. Two separate walls, and the one
# that announces itself is the lesser of them.
#
# The visible one: install.sh aborts on Intel, "Homebrew on macOS is only
# supported on Apple Silicon processors!", a bare "uname -m" test added on
# 2026-09-04 in Homebrew/install commit e078684. It offers no way round
# itself, but the commit before it, pinned below, has no such test and its own
# version floor stops at 10.11, so Catalina passes.
#
# The one that matters: brew declares its own floor, HOMEBREW_MACOS_OLDEST_ALLOWED
# in Library/Homebrew/brew.sh, and 7.0 raised it from 10.15 to 11. Current brew
# therefore refuses to start here no matter what installed it. 6.0.22 is the
# last release with that floor still at 10.15, hence the pin. Nothing as old
# as the 3.x that supported Catalina at the time is needed: 5.x and 6.x both
# still allow it, and only warn that it is unsupported.
#
# Then there are the formulae. Current homebrew-core carries no catalina
# bottles, so every formula would build from source with a 2019 toolchain.
# Those bottles do exist for the versions that were current while Catalina was
# supported, and the blobs stay on ghcr, so the core tap is pinned to
# 2022-10-31. Verified at that commit: htop, wget, cmake, doxygen, ccache,
# pkg-config, openssl@3, aria2, bash, git and python all have a catalina
# bottle. (Not valgrind, which has no bottle on any macOS of that era and is
# already tolerated below.)
#
# The whole tap is pinned rather than single formulae, unlike the gcc@12 case
# further down, because dependencies have to come from the same era too: a
# 2022 wget resolved against a 2026 openssl gets no bottle either. That in
# turn needs HOMEBREW_NO_INSTALL_FROM_API, or brew reads formulae from its
# JSON API and ignores the tap completely.
brewversion="6.0.22"
brewcorecommit="ed5bfd3f5931a74e4b5df84ece8bd17ad26da86c"
brewinstallcommit="7a133dcc74051ee4efc79467ed215dfedf45aea2"

catalina=no
if [[ $(sw_vers -productVersion) =~ ^10\.15 ]]; then
    catalina=yes
    # Without the first of these, the next "brew install" updates brew to 7.x
    # and everything after it stops working.
    export HOMEBREW_NO_AUTO_UPDATE=1
    export HOMEBREW_NO_INSTALL_FROM_API=1
fi

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
if command -v brew ; then
    echo "Brew already installed"
elif [ "$catalina" = yes ]; then
    echo "Install brew, pinned, for Catalina"
    set +x
    # The pinned installer is still worth using for the /usr/local directory
    # and ownership work, which is the tedious part to reproduce. It clones
    # brew at HEAD and then runs it, and that last step fails here because
    # HEAD is 7.x; the clone is already on disk by then, so the failure is
    # expected rather than fatal.
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/${brewinstallcommit}/install.sh)" || true
    set -x
    if [ ! -x /usr/local/Homebrew/bin/brew ]; then
        echo "The installer did not leave a brew clone at /usr/local/Homebrew ."
        exit 1
    fi
    git -C /usr/local/Homebrew fetch --tags --force
    git -C /usr/local/Homebrew checkout "$brewversion"
else
    echo "Install brew"
    set +x
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    set -x
fi

if [ "$catalina" = yes ]; then
    brewcoretap="$(brew --repo)/Library/Taps/homebrew/homebrew-core"
    if [ ! -d "$brewcoretap" ]; then
        # --filter=blob:none fetches file contents on demand, so this is a few
        # minutes and a few hundred MB rather than the whole multi-GB history,
        # while still leaving a repository that can check out a 2022 commit.
        git clone --filter=blob:none https://github.com/Homebrew/homebrew-core "$brewcoretap"
    fi
    git -C "$brewcoretap" checkout "$brewcorecommit"
fi

brew install htop
brew install wget
brew install cmake
# lcov comes from upstream rather than brew. These OS versions get no bottles
# (Tier 3), so brew builds from source, and lcov's one build dependency is
# sphinx-doc, needed purely to typeset man pages. Building sphinx means
# creating a Python venv, which is where "brew install lcov" dies on macOS 12,
# with an error Homebrew cannot even report: its forked-child error reporter
# crashes marshalling a Pathname to JSON, so the real failure never prints.
#
# lcov is Perl scripts, hence its bottle being "cellar :any_skip_relocation",
# so an upstream install needs no compiler, no Python and no brew at all.
#
# 1.16 rather than 2.x deliberately. Its install target has no doc
# prerequisite, the tarball ships the man pages already built, and every
# module it uses is core Perl, down to IO::Uncompress::Gunzip. 2.x needs
# sphinx (its install target depends on the generated docs) and also
# Capture::Tiny, which is not core Perl: the brew formula gets away with that
# by relying on the system perl of a newer macOS to supply it.
lcovversion="1.16"
lcovsha256="987031ad5528c8a746d4b52b380bc1bffe412de1f2b9c2ba5224995668e3240b"

if command -v lcov ; then
    echo "lcov already installed"
else
    curl -fsSL -o /tmp/lcov.tar.gz "https://github.com/linux-test-project/lcov/releases/download/v${lcovversion}/lcov-${lcovversion}.tar.gz"
    echo "${lcovsha256}  /tmp/lcov.tar.gz" | shasum -a 256 -c -
    rm -rf /tmp/lcovsrc
    mkdir -p /tmp/lcovsrc
    tar -xzf /tmp/lcov.tar.gz -C /tmp/lcovsrc
    # Rewrites the shebangs to /usr/bin/perl, so this does not depend on a brew
    # perl being installed.
    sudo make -C "/tmp/lcovsrc/lcov-${lcovversion}" install PREFIX=/usr/local
fi
lcov --version

brew install valgrind || true
brew install doxygen
brew install ccache || true
brew install pkg-config
brew install openssl

# gcc comes from a pinned formula in a local tap rather than "brew install gcc".
#
# Current gcc is 16.2.0 with no arm64_monterey bottle, so brew attempts a full
# GCC bootstrap from source, and that fails in stage1 here. gcc@12 12.4.0 is
# the last revision carrying real monterey and arm64_monterey bottles, so it
# pours in seconds instead.
#
# Bottles for this configuration do still exist: any formula version that was
# current while Homebrew supported Monterey was bottled then and the blob stays
# on ghcr, which is why "make" pours a bottle in this same run while gcc does
# not. (Only Monterey. That revision has no Catalina or High Sierra bottle, so
# the 10.x branches below get no gcc from this.)
#
# Reaching one takes a tap of our own. Homebrew 7.0 rejects "brew install
# <url>" outright, and the "brew version-install" it suggests instead runs
# "brew extract", which strips the bottle block ("Remove bottle blocks, as they
# won't work") and would therefore build from source too. A formula in our tap
# keeps the block. None of this depends on the tap: root_url defaults to
# $HOMEBREW_BOTTLE_DOMAIN, ghcr.io/v2/homebrew/core, and the blob path is
# derived from the formula name, so the file has to keep the name gcc@12 to
# resolve as gcc/12.
#
# 12 also happens to be what this script has always wanted: gccversion below
# is "12" and the symlinks want gcc-12, whereas "brew install gcc" now yields
# gcc-16.
gcc12commit="fa3b9b2071819e5f9f548a08286a5e5840aa3e09"
gcc12tap="cppalliance/pinned"

if command -v gcc-12 ; then
    echo "gcc-12 already installed"
elif [ "$catalina" = yes ]; then
    # None of the above applies with the core tap pinned to 2022: gcc was
    # itself 12 then, so this is plain gcc 12.2.0, with a catalina bottle and
    # the gcc-12 binaries the symlinks want. There is no gcc@12 formula at
    # that commit to pin, and no need for a tap of our own.
    brew install gcc
else
    brew tap-new --no-git "$gcc12tap" || true
    gcc12formula="$(brew --repo "$gcc12tap")/Formula/gcc@12.rb"
    curl -fsSL -o "$gcc12formula" \
        "https://raw.githubusercontent.com/Homebrew/homebrew-core/${gcc12commit}/Formula/g/gcc@12.rb"
    # cxxstdlib_check has since been dropped from the formula DSL, and a
    # formula that calls it no longer loads at all. It only ever applied to
    # building from source.
    sed -i '' '/cxxstdlib_check/d' "$gcc12formula"
    # Expect "Pouring gcc@12--12.4.0.arm64_monterey.bottle.tar.gz". Note that
    # the bottle is conditional on "pour_bottle? only_if: :clt_installed", so
    # this has to run before the CommandLineTools directory is moved aside
    # further down, or brew quietly builds from source instead. That build does
    # work, 12.4.0 being a version Homebrew bottled on this OS, but it is an
    # hour rather than a minute.
    brew install "$gcc12tap/gcc@12"
fi

# That bottle was linked against isl 0.26 and this machine now has 0.28. isl
# appears not to have changed soname in between, since brew never revved gcc@12
# for it, but do not take that on faith: a stale libisl reference surfaces here.
gcc-12 --version

brew install aria2

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

# bash belongs here, not down beside the Xcode work where it used to be. macOS
# ships bash 3.2 and /usr/local/bin/bash is expected to be a modern one, but
# the Xcode section moves /Library/Developer/CommandLineTools aside, and once
# that is gone brew will not build anything from source on Monterey: "Xcode
# alone is not sufficient on Monterey. Install the Command Line Tools". On this
# OS every formula is a source build, so that is every formula.
brew install bash
if [ ! -f /usr/local/bin/bash ]; then
    ln -s /opt/homebrew/bin/bash /usr/local/bin/ || true
fi

# Xcode installation, from archives already sitting on this machine.
#
# These OS versions can run neither xcodes (the 2.x binary is built for macOS
# 13, and 1.6.2, the last one that runs here, predates the Apple login changes
# that 2.1.0 was released to fix) nor the xcode-install gem's "xcversion"
# (abandoned, and its Apple login no longer works). Downloading is therefore
# done elsewhere, by downloader.sh on a macOS 26 host.
#
# Installing is little more than expanding the archive: an Xcode.app is
# self-contained and code-signed, and nothing registers it with the system.
# What xcodes does beyond this, and what is still done per-machine further
# down, is accept the license. It would also run "DevToolsSecurity -enable",
# add staff to the _developer group, and run "xcodebuild -runFirstLaunch" to
# install the bundled components, except that these hosts have always passed
# --no-superuser and skipped all three.

xcode_normalize_version() {
    # 12.5 -> 12.5.0, because that is how xcodes names what it downloads.
    case "$(echo "$1" | awk -F. '{print NF}')" in
        1) echo "$1.0.0" ;;
        2) echo "$1.0" ;;
        *) echo "$1" ;;
    esac
}

xcode_archive() {
    # Accepts either naming: xcodes writes Xcode-13.4.1+13F100.xip, while a
    # browser download straight from Apple arrives as Xcode_13.4.1.xip.
    local version="$1" normalized
    normalized=$(xcode_normalize_version "$version")
    ls -1 "$xcodearchives"/Xcode-"$normalized"+*.xip \
          "$xcodearchives"/Xcode-"$normalized".xip \
          "$xcodearchives"/Xcode_"$version".xip \
          "$xcodearchives"/Xcode_"$version".dmg 2>/dev/null | head -n 1
}

xcode_install() {
    local version="$1"
    local archive workdir app mountpoint

    archive=$(xcode_archive "$version")
    if [ -z "$archive" ]; then
        echo "No archive for Xcode $version in $xcodearchives"
        return 1
    fi

    # Expanding beside the archive keeps the move below on one filesystem, and
    # needs room for the app as well, roughly 25GB for the newer versions.
    # "xip --expand" verifies the archive's signature, so a truncated or
    # corrupted copy fails here rather than producing a broken Xcode.
    workdir=$(mktemp -d "$xcodearchives/xcode-install.XXXXXX")

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
    # scp leaves no quarantine flag, but a browser download does.
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

    # xcode-install and its fastlane authentication are no longer used.
    # xcode_install below expands an archive that downloader.sh already
    # fetched on a macOS 26 host.
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
    ln -s Xcode-6.4.app Xcode-6.app || true
    # one repo references this:
    ln -s Xcode-8.app Xcode-8.0.app || true

    sudo xcode-select -switch /Applications/Xcode-9.4.1.app/Contents/Developer
    sudo mv /Library/Developer/CommandLineTools /Library/Developer/CommandLineTools.bck
    sudo xcodebuild -license accept
fi

sudo xcrun gem install coveralls-lcov --no-document
sudo xcrun gem install asciidoctor --no-document
sudo xcrun gem install asciidoctor-pdf --no-document
sudo xcrun gem install coderay --no-document
