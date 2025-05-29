#!/bin/bash

# These are notes about steps. It can't be run as-is.

set -xe

# Upgrade IBM Cloud
# In fact, the upgrade from 22.04 to 24.04 is "failing" due to network connectivity.
# Don't proceed.

apt-get update
apt-get dist-upgrade
apt remove unattended-upgrades
reboot
do-release-upgrade
# keep original files, rather than package maintainer

