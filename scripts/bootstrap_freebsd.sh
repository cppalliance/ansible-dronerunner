#!/bin/sh

# Run this as root

pkg install -y sudo

user=ec2-user
group=ec2-user

if [ ! -f /usr/local/etc/sudoers.d/$user ]; then
    echo "$user ALL=(ALL) NOPASSWD:ALL" | tee /usr/local/etc/sudoers.d/$user
    echo "You may need to logout and login again before continuing."
    # exit 0
fi
