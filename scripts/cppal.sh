#!/bin/bash

# Create another user to be able to connect. Included in the ansible tasks, so this script doesn't need to be run by itself.
# export env var:
# export dronerunner_password=
set -ex
user=cppal
group=staff
sshdir=/Users/cppal/.ssh
sysadminctl -addUser $user -fullName $user -shell /bin/bash -password $dronerunner_password -home /Users/$user
mkdir -p /Users/$user
chown $user:staff /Users/$user
dscl . -append /Groups/admin GroupMembership $user
pubkey1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCH0oawPzIylSjdu/fpyDD2i2stkqe52bFmLT8+MeiTAp5WI8BwlbeeiiZkneEHhLW7bGMKZ50rQONjiudWCFibb4zM2pUQTFP91BuzUG7MjFf179UlvRMUiNSYkKSSB4q0QZ8+2Vjj5lXzYxM5FjZ9FdA1ioI5l8TK8rLlf/F1TKKDfjA/YMk7769BVYndDilSidaDEvRVxQM8Z5RBUnSnDFQwEaVOuVaHIki0ZPVecwyE96e2HaFDRjNlMUZbSgHrdwkjbIugaUfiWFANBA5eIOka19CSLV5aY1tNeawoUvIBsRXjUleFJE+EIL0iGcuTcLXvAqh5UwFdMkkwUfhH drone-runner"
if [ ! -f /etc/sudoers.d/$user ]; then
    sudo echo "$user ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$user
fi
mkdir -p $sshdir
echo "$pubkey1" > $sshdir/authorized_keys
chmod -R 700 $sshdir
chown -R $user:$group $sshdir

