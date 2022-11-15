#!/bin/sh

# Run this as root

set -xe

pkg install -y sudo

# an admin user, regardless of hosting:
user=ec2-user
group=ec2-user

if id -g $group ; then
    echo "group exists"
else
    pw group add $group
fi

if id -u $user ; then
    echo "user exists"
else
    pw user add -n $user -c "$user" -d /home/$user -G $group -m -s /bin/sh
    mkdir -p /home/$user/.ssh
    chown $user:$group /home/$user/.ssh
    pubkey1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCH0oawPzIylSjdu/fpyDD2i2stkqe52bFmLT8+MeiTAp5WI8BwlbeeiiZkneEHhLW7bGMKZ50rQONjiudWCFibb4zM2pUQTFP91BuzUG7MjFf179UlvRMUiNSYkKSSB4q0QZ8+2Vjj5lXzYxM5FjZ9FdA1ioI5l8TK8rLlf/F1TKKDfjA/YMk7769BVYndDilSidaDEvRVxQM8Z5RBUnSnDFQwEaVOuVaHIki0ZPVecwyE96e2HaFDRjNlMUZbSgHrdwkjbIugaUfiWFANBA5eIOka19CSLV5aY1tNeawoUvIBsRXjUleFJE+EIL0iGcuTcLXvAqh5UwFdMkkwUfhH drone-runner"
    echo $pubkey1 > /home/$user/.ssh/authorized_keys
    chown -R $user:$group /home/$user/.ssh
    chmod -R 700 /home/$user/.ssh
fi

if [ ! -f /usr/local/etc/sudoers.d/$user ]; then
    echo "$user ALL=(ALL) NOPASSWD:ALL" | tee /usr/local/etc/sudoers.d/$user
    echo "You may need to logout and login again before continuing."
    # exit 0
fi
