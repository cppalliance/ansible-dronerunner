
# Script to bootstrap Windows for Ansible

# Set variables:
$pubkey1 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCH0oawPzIylSjdu/fpyDD2i2stkqe52bFmLT8+MeiTAp5WI8BwlbeeiiZkneEHhLW7bGMKZ50rQONjiudWCFibb4zM2pUQTFP91BuzUG7MjFf179UlvRMUiNSYkKSSB4q0QZ8+2Vjj5lXzYxM5FjZ9FdA1ioI5l8TK8rLlf/F1TKKDfjA/YMk7769BVYndDilSidaDEvRVxQM8Z5RBUnSnDFQwEaVOuVaHIki0ZPVecwyE96e2HaFDRjNlMUZbSgHrdwkjbIugaUfiWFANBA5eIOka19CSLV5aY1tNeawoUvIBsRXjUleFJE+EIL0iGcuTcLXvAqh5UwFdMkkwUfhH drone-runner"
$keysfile = "C:\ProgramData\ssh\administrators_authorized_keys"

iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
choco install -y --package-parameters=/SSHServerFeature openssh

Add-Content C:\ProgramData\ssh\sshd_config "PasswordAuthentication no"
Restart-Service -Name sshd

Add-Content $keysfile $pubkey1
icacls $keysfile /inheritance:d
icacls $keysfile /remove "Users"
icacls $keysfile /remove "Authenticated Users"

