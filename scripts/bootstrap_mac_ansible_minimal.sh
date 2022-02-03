#!/bin/bash

# Notes:
# This script enables ssh and sudo, for ansible.

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
