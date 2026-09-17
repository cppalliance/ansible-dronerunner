#!/bin/bash

set -xe

# Run as administrator

# Purpose:
# - Downloads Xcode archives, and nothing else. Installs no Xcode.
#
# Run this on a macOS 26 host, then copy the archives to the older hosts. Those
# hosts cannot run xcodes themselves: the 2.x binary is built for macOS 13, and
# 1.6.2, the last release that runs on macOS 12, predates the Apple login
# changes that 2.1.0 was released to fix.
#
# Apple does not care which macOS does the downloading. These archives are
# files on a CDN, and the version only has to be one xcodes can look up. Which
# of them a given host can actually run is a separate question, answered by
# supported_xcodes.sh.
#
# Instructions:
#
# Run it interactively the first time. xcodes prompts for a 2FA code once and
# then keeps the session in the keychain.
#
# Budget the disk space. The list below is a little over 100GB.
#
# Set these variables before proceeding:
: '
export XCODES_USERNAME=
export XCODES_PASSWORD=
'

# The versions the macOS 12 and 13 hosts install. Keep in step with
# bootstrap_mac_earlier_than_14.sh.
xcodeversions="12.5 12.5.1 13.0 13.1 13.2 13.2.1 13.3 13.3.1 13.4 13.4.1 14.0 14.1"

downloaddir="${XCODE_DOWNLOADS:-$HOME/xcode-downloads}"

if [ -z "$XCODES_USERNAME" ] || [ -z "$XCODES_PASSWORD" ]; then
    echo "Set both XCODES_USERNAME and XCODES_PASSWORD:
export XCODES_USERNAME=
export XCODES_PASSWORD=
"
exit 1
fi

export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH

if ! command -v brew ; then
    echo "Install brew first, or run bootstrap_mac_26.sh." >&2
    exit 1
fi

command -v xcodes || brew install xcodes

# xcodes uses aria2 with up to 16 connections when it is installed, which is
# 3-5x faster than its URLSession fallback.
command -v aria2c || brew install aria2

mkdir -p "$downloaddir"

normalize_version() {
    # 12.5 -> 12.5.0, because that is how xcodes names the file.
    case "$(echo "$1" | awk -F. '{print NF}')" in
        1) echo "$1.0.0" ;;
        2) echo "$1.0" ;;
        *) echo "$1" ;;
    esac
}

# One failure should not abandon the rest of a multi-hour run, so collect them
# and report at the end.
failed=""

for xcodeversion in $xcodeversions; do
    # xcodes writes Xcode-<x.y.z>+<build>.xip, and the build number is not
    # known ahead of time, hence the glob rather than an exact filename.
    existing=$(ls "$downloaddir"/Xcode-"$(normalize_version "$xcodeversion")"+*.xip 2>/dev/null | head -n 1)
    if [ -n "$existing" ]; then
        echo "Already downloaded: $existing"
        continue
    fi

    if ! xcodes download "$xcodeversion" --directory "$downloaddir" ; then
        failed="$failed $xcodeversion"
    fi
done

ls -lh "$downloaddir"

if [ -n "$failed" ]; then
    echo "Failed to download:$failed" >&2
    exit 1
fi

echo "
Now copy these to the target host, into the directory that
bootstrap_mac_earlier_than_14.sh reads:

    scp $downloaddir/*.xip administrator@<host>:/Applications/downloads/
"
