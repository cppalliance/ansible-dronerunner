
# Script to bootstrap Windows for Ansible

# manually run this:
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')) }
choco install -y notepadplusplus

# create bootstrap1.ps1:

# Set variables:
$pubkey1 = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCH0oawPzIylSjdu/fpyDD2i2stkqe52bFmLT8+MeiTAp5WI8BwlbeeiiZkneEHhLW7bGMKZ50rQONjiudWCFibb4zM2pUQTFP91BuzUG7MjFf179UlvRMUiNSYkKSSB4q0QZ8+2Vjj5lXzYxM5FjZ9FdA1ioI5l8TK8rLlf/F1TKKDfjA/YMk7769BVYndDilSidaDEvRVxQM8Z5RBUnSnDFQwEaVOuVaHIki0ZPVecwyE96e2HaFDRjNlMUZbSgHrdwkjbIugaUfiWFANBA5eIOka19CSLV5aY1tNeawoUvIBsRXjUleFJE+EIL0iGcuTcLXvAqh5UwFdMkkwUfhH drone-runner"
# Recent Windows images (e.g. AWS Windows Server 2025) ship OpenSSH already, so only
# install what is missing. sshd looks in both of these locations depending on the
# account and version, so the key goes in both.
$keysfiles = @("C:\ProgramData\ssh\administrators_authorized_keys", "C:\Users\administrator\.ssh\authorized_keys")

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')) }

if (Get-Service sshd -ErrorAction SilentlyContinue) {
    Write-Host "OpenSSH server already present, skipping install."
} else {
    choco install -y --package-parameters=/SSHServerFeature openssh
}

# On some images the inbound rule is limited to the Private profile, which blocks
# ssh from outside the VPC. The rule name varies by install method.
$sshrule = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*SSH*" -or $_.DisplayName -like "*SSH*" }
if ($sshrule) {
    $sshrule | Set-NetFirewallRule -Profile Public -Enabled True
} else {
    Write-Warning "No OpenSSH firewall rule found, not changing the firewall profile."
}

# the following packages are not strictly required, but convenient to have.
choco install -y vim
choco install -y git

foreach ($keysfile in $keysfiles) {
    New-Item -ItemType Directory -Force -Path (Split-Path $keysfile) | Out-Null
    Add-Content $keysfile $pubkey1
    icacls $keysfile /inheritance:d
    icacls $keysfile /remove "Users"
    icacls $keysfile /remove "Authenticated Users"
}

Add-Content C:\ProgramData\ssh\sshd_config "PasswordAuthentication no"
# Some images leave sshd on Manual start, so it disappears after the first reboot.
Set-Service -Name sshd -StartupType Automatic
Restart-Service -Name sshd

# create bootstrap2.ps1. Better, move this to ansible.
# docker pull cppalliance/dronevs2015:latest
# docker pull cppalliance/dronevs2017:latest
# docker pull cppalliance/dronevs2019:latest
# docker pull cppalliance/dronevs2022:latest
