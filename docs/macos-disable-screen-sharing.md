# Disabling Screen Sharing on macOS 10.15 (Catalina)

We manage our Mac minis entirely with Ansible over SSH and never use the
graphical console, so Screen Sharing is not something we need.

If the reason Catalina is no longer offered is the Screen Sharing (VNC)
listener on TCP port 5900, it can be removed in two commands. The change
survives reboots on its own, needs nothing installed, and is reversible in two
commands if console access is ever required.

The simplest version of this request: if your provisioning enables Screen
Sharing by default, please leave it off. Everything below is just the
command-line equivalent of that.

## Option 1: turn the service off (preferred)

```sh
sudo launchctl disable system/com.apple.screensharing
sudo launchctl bootout system/com.apple.screensharing
```

This is the same change as unchecking **System Preferences → Sharing → Screen
Sharing**; the command-line form simply does not need a GUI session. The first
command records the state, the second stops the currently running instance.

It persists by itself. `launchctl disable` writes to launchd's own on-disk
database, `/var/db/com.apple.xpc.launchd/disabled.plist`, not to any file under
the read-only system volume, so the service stays off after a reboot with no
extra daemon or login item required. This is also the remediation NIST
publishes for Catalina in its macOS security baseline
(<https://github.com/usnistgov/macos_security>).

Verify, on the machine, and again after the first reboot if you want to be
thorough:

```sh
# Expect no output. While Screen Sharing is enabled, this shows launchd
# holding the socket, because the daemon is started on demand.
sudo lsof -nP -iTCP:5900 -sTCP:LISTEN

# Expect a line showing com.apple.screensharing as disabled.
sudo launchctl print-disabled system | grep screensharing
```

Verify from anywhere else, which is the check that actually matters:

```sh
nc -vz <ip-address> 5900     # expect a refused or timed-out connection
```

If **Remote Management** (Apple Remote Desktop) is enabled instead of Screen
Sharing, it serves the same port, and Apple's documented off switch is:

```sh
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate
```

### Reverting

```sh
sudo launchctl enable system/com.apple.screensharing
sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist
```

Or just re-check the box in System Preferences → Sharing.

## Option 2: leave the service running and block the port

Only if you would rather not change the service state. This uses pf, the packet
filter already built into macOS, through the anchor mechanism that the stock
`/etc/pf.conf` points customizations at. It is more moving parts than Option 1,
which is why Option 1 is preferred.

Create `/etc/pf.anchors/no-screen-sharing`:

```
# Keep loopback working, so a deliberate SSH tunnel still functions.
pass in quick on lo0 proto tcp from any to any port 5900
# Drop everything else aimed at the Screen Sharing port.
block drop in quick proto tcp from any to any port 5900
```

Append two lines to `/etc/pf.conf`. They go at the end, after the existing
`com.apple` anchors, because pf requires filter rules to follow translation
rules:

```
anchor "no-screen-sharing"
load anchor "no-screen-sharing" from "/etc/pf.anchors/no-screen-sharing"
```

Load it now:

```sh
sudo pfctl -e -f /etc/pf.conf
```

As the comments in the stock `/etc/pf.conf` note, pf is not enabled at boot on
macOS, so this needs a launch daemon to come back after a reboot. Create
`/Library/LaunchDaemons/com.no-screen-sharing.pf.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.no-screen-sharing.pf</string>
    <key>ProgramArguments</key>
    <array>
        <string>/sbin/pfctl</string>
        <string>-e</string>
        <string>-f</string>
        <string>/etc/pf.conf</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```

```sh
sudo chown root:wheel /Library/LaunchDaemons/com.no-screen-sharing.pf.plist
sudo chmod 644 /Library/LaunchDaemons/com.no-screen-sharing.pf.plist
sudo launchctl load -w /Library/LaunchDaemons/com.no-screen-sharing.pf.plist
```

`pfctl -e` warns if pf is already enabled, which is harmless: the rules are
still loaded by `-f`.

### Reverting

Remove the two lines from `/etc/pf.conf`, then:

```sh
sudo launchctl unload -w /Library/LaunchDaemons/com.no-screen-sharing.pf.plist
sudo rm /Library/LaunchDaemons/com.no-screen-sharing.pf.plist /etc/pf.anchors/no-screen-sharing
sudo pfctl -f /etc/pf.conf
```

## Summary

- TCP 5900 is the port Screen Sharing listens on. Remote Management, if it is
  enabled instead, also uses port 3283, which is why the `kickstart` command
  above covers it.
- SSH on port 22 is untouched, which is how we manage the machine.
- Both options are reversible, and Option 1 is reversible without a reboot.
