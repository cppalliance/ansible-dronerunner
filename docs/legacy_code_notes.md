
2023-01-17

The first iteration of the macOS implementation started the drone runner service on boot by adding a LaunchAgent for the drone user in /Users/drone/Library/LaunchAgents/drone-runner-exec.plist  
The macOS user is configured to log in (locally) at boot time with a password.  
The process can be improved by moving the plist file to /Library/LaunchDaemons and setting:  

```
<key>UserName</key>  
<string>drone</string>  
```

LaunchDaemons run as root and don't require a user to have a desktop session initiated.  

The previous methodology was interesting though and shouldn't be deleted entirely. Here is documentation as a record:  

In tasks/macos.yml

```

# To set up autologin
- name: Tap Homebrew repository xfreebird/utils
  become: false
  community.general.homebrew_tap:
    name: xfreebird/utils

- name: Check for /etc/kcpassword
  stat: path=/etc/kcpassword
  register: kc

- name: Check for CommandLineTools
  stat: path=/Library/Developer/CommandLineTools
  register: cli_tools
  when:
    - not kc.stat.exists
    # - cli_tools.stat.isdir is defined and cli_tools.stat.isdir

- name: Move CommandLineTools from .bck
  command: mv /Library/Developer/CommandLineTools.bck /Library/Developer/CommandLineTools
  when:
    - not kc.stat.exists
    - not cli_tools.stat.exists

- name: Install kcpassword
  community.general.homebrew:
    name: kcpassword
    state: present
  become: false

- name: Enable auto login
  become: false
  ansible.builtin.shell: |
    sleep 1
    enable_autologin {{ dronerunner_user }} {{ dronerunner_password }}
  args:
    creates: /etc/kcpassword
  notify: reboot mac
  when:
    - not kc.stat.exists
  environment:
    PATH: /usr/local/bin:/opt/homebrew/bin:{{ ansible_env.PATH }}

# Done with kcpassword steps
- name: Move CommandLineTools to .bck
  command: mv /Library/Developer/CommandLineTools /Library/Developer/CommandLineTools.bck
  when:
    - not kc.stat.exists

```

