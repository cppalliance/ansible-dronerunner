# Full Disk Access for remote logins

The bootstrap scripts refuse to run without this, and Ansible tasks that touch
protected locations fail without it too. Transparency, Consent and Control
(TCC) applies to processes, not accounts, so a process in an SSH session gets
`Operation not permitted` on a protected path even when it is running as root.
Granting Full Disk Access to the SSH daemon is what lifts that.

Where the setting lives depends on the release, and the two forms are not in
the same place or even in the same preference pane:

| macOS | Where |
| --- | --- |
| 10.13 High Sierra | Nothing to do. FDA did not exist before 10.14 Mojave. |
| 10.15 Catalina, 12 Monterey | Security & Privacy → Privacy → Full Disk Access, add `sshd-keygen-wrapper` by hand |
| 13 Ventura and later (14, 26) | Sharing → Remote Login → ⓘ → "Allow full disk access for remote users" |

Note that Remote Login itself, the switch that turns SSH on, is in the Sharing
pane on every release. On Catalina and Monterey that pane has nothing to do
with Full Disk Access, which is the easy wrong turn here: the checkbox you may
remember from a newer machine does not exist on these releases.

## Catalina 10.15 and Monterey 12

This is a GUI-only step, so you need a screen session: VNC, or the console.
On hosts running Murus, TCP 5900 is permitted from the `<Sam>` and `<NOC>`
tables, so Screen Sharing still works from there.

1.  → **System Preferences** → **Security & Privacy**, then the **Privacy**
   tab along the top.
2. In the left-hand list, scroll down and select **Full Disk Access**. It sits
   below Accessibility and Input Monitoring.
3. Click the padlock at the bottom left and authenticate, or the list stays
   read-only and the `+` button does nothing.
4. Click **+**. A file dialog opens.
5. Press **Shift-Cmd-G** for "Go to Folder", type
   `/usr/libexec/sshd-keygen-wrapper`, press Return, then click **Open**.
   `/usr/libexec` is hidden, so it cannot be reached by browsing; Shift-Cmd-.
   toggles hidden files if you prefer that.
6. The entry appears in the list with its checkbox ticked. Close the padlock.
7. Reconnect. An SSH session that was already open keeps the permissions it
   started with, so the change will not appear in it.

`sshd-keygen-wrapper` rather than `sshd` because the wrapper is what launchd
actually executes, and TCC attributes the permission to that. Adding
`/usr/sbin/sshd` as well does no harm if you have already done so.

## Ventura 13 and later

1.  → **System Settings** → **General** → **Sharing**.
2. Click the **ⓘ** next to **Remote Login**. The setting is only visible there,
   not in the row itself.
3. Turn on **Allow full disk access for remote users**.

It is on by default on these releases, so usually there is nothing to do and
this is only worth checking if something has turned it off. Nothing needs
adding to the Full Disk Access list in Privacy & Security; this checkbox
replaces that.

## Verifying

From a freshly opened SSH session, which is the same check the bootstrap
scripts make before they will run:

```sh
head -c1 "/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null && echo "FDA enabled"
```

That file is readable only by a process holding Full Disk Access. On 10.13 it
succeeds for the unrelated reason that no release before 10.14 enforces any of
this.

Another quick symptom-level check, if you want to see the failure rather than
infer it: `ls ~/Desktop` returns `Operation not permitted` without FDA and
lists the directory with it.

## Why this is a manual step

It cannot be scripted on a Mac with System Integrity Protection enabled.
`tccutil` only implements `reset`, and the TCC databases are SIP-protected, so
nothing in Ansible or in a bootstrap script can grant this. The one supported
way to automate it is a PPPC configuration profile
(`com.apple.TCC.configuration-profile-policy`) granting `SystemPolicyAllFiles`
to `/usr/libexec/sshd-keygen-wrapper`, and such a profile is honoured only when
it arrives through user-approved MDM. Installed by hand with `profiles` it is
ignored.

So it is one click per machine, before the bootstrap script will run.
