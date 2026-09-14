## Bootstrap scripts

Run once, by hand, on a new drone runner, before the Ansible role takes over.
They set up ssh and sudo, install the versions of Xcode that the host can run,
and install the packages drone jobs need.

| Script | Host |
| --- | --- |
| `bootstrap_mac_26.sh` | macOS 26 |
| `bootstrap_mac_14.sh` | macOS 14 |
| `bootstrap_mac_earlier_than_14.sh` | macOS 13, 12, 10.15, 10.13 |
| `bootstrap_ubuntu.sh`, `bootstrap_freebsd.sh`, `bootstrap_win.ps1` | non-mac hosts |

The rest are helpers rather than bootstraps: `supported_xcodes.sh` lists the
Xcode versions a given macOS release can run, `cppal.sh` and
`bootstrap_mac_ansible_minimal.sh` cover pieces of the mac setup on their own.

The macOS 26 and 14 scripts install Xcode with
[xcodes](https://github.com/XcodesOrg/xcodes). Older hosts can't: the xcodes
2.x binary requires macOS 13, and xcodes has never handled the `.dmg` archives
that Xcode 7.3.1 and earlier shipped as. So `bootstrap_mac_earlier_than_14.sh`
downloads and expands the archives itself, and needs to be told where to get
them, by setting either `XCODE_MIRROR` or `ADC_COOKIE`.

### Constructing the mirror

`XCODE_MIRROR` is any location holding the Xcode archives under Apple's own
filenames. It is the better option for more than one host: the machines need no
Apple credentials, and you are not racing the expiry of a download cookie
through a 100GB download.

Note that https://xcodereleases.com is a catalog, not a host. There is nothing
to log into there, and it stores no archives. What it gives you, and what the
bootstrap script relies on, is the canonical list of versions, their download
URLs on Apple's servers, and a SHA1 for each one.

**1. Get an Apple ID.** A free Apple Developer account is enough for released
versions of Xcode. No paid membership needed.

**2. Download the archives.** Any of these work:

From a browser, at https://developer.apple.com/download/all/ . Sign in, search
for e.g. "Xcode 13.4.1", and download. Files arrive already named the way the
mirror wants them.

Or with curl, on any machine, which is the same exchange the bootstrap script
performs. Sign in at the URL above, copy the value of the `myacinfo` cookie out
of the browser's developer tools, and then per version:

```bash
export ADC_COOKIE="myacinfo=<value>"
version=13.4.1
url="https://download.developer.apple.com/Developer_Tools/Xcode_${version}/Xcode_${version}.xip"

# Apple issues a short-lived ADCDownloadAuth cookie for one path at a time.
curl -fsS -o /dev/null -c adc-cookies.txt -H "Cookie: $ADC_COOKIE" \
    "https://developerservices2.apple.com/services/download?path=${url#https://download.developer.apple.com}"
auth=$(awk '$6 == "ADCDownloadAuth" { print $7 }' adc-cookies.txt | tail -n 1)

aria2c -x 8 -s 8 --header "Cookie: $ADC_COOKIE; ADCDownloadAuth=$auth" "$url"
```

Or on a Mac running macOS 15 or newer, with `brew install xcodes` and
`xcodes download 13.4.1`, which handles the Apple login including 2FA. It names
the file after the version and build, something like `Xcode-13.4.1+<build>.xip`,
so rename it as below.

**3. Name the files exactly as Apple does,** because that is what the script
requests. `Xcode_<version>.<xip or dmg>`, with any trailing `.0` dropped, and
`.dmg` for Xcode 7 and earlier:

```
Xcode_13.4.1.xip      for 13.4.1
Xcode_13.xip          for 13.0
Xcode_12.5.1.xip      for 12.5.1
Xcode_8.xip           for 8
Xcode_6.4.dmg         for 6.4
```

**4. Verify, optionally.** xcodereleases publishes a SHA1 per archive:

```bash
file=Xcode_13.4.1.xip
curl -fsSL https://xcodereleases.com/data.json \
    | jq -r --arg f "$file" '.[] | select((.links.download.url // "") | endswith("/" + $f)) | .checksums.sha1'
shasum -a 1 "$file"
```

**5. Serve the directory.** Anything curl can fetch from works, since the
script just appends the filename to `XCODE_MIRROR`. A flat directory, no
subdirectories per version:

```bash
export XCODE_MIRROR=https://your.host/xcode      # nginx, apache, S3, or even
                                                 # python3 -m http.server
export XCODE_MIRROR=file:///Volumes/xcode        # a local disk or an NFS mount
```

Budget the disk space. Most of these archives are several gigabytes each and
the newer ones are over ten, so a full version list runs well past 100GB. The
hosts also need room in `/tmp` for one archive plus its expanded app while
each install runs.

### Downloading directly from Apple instead

For a single host, skip the mirror and set `ADC_COOKIE` to the same
`myacinfo=<value>` described above. The script then performs the cookie
exchange itself, per version.

The catch is lifetime: that session cookie is good for hours, not weeks, and a
long version list can outlast it. A download that fails this way arrives as an
HTML error page rather than an archive, which the script detects by checking
for the xar magic bytes and reports as `is not an Xcode archive`. Refresh the
cookie and run it again. Already installed versions are skipped, so re-running
is cheap.
