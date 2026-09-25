# GitHub clone access for the drone runner

The drone runner on `clang4.cpp.al` runs many pipelines in parallel, and each
Boost pipeline issues a burst of anonymous `git clone` requests inside
`.drone/drone.sh` (the superproject, `boostdep`, and one clone per dependency
module). Past a certain rate GitHub throttles the anonymous traffic, and a
throttled request surfaces as:

```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

Raising parallelism does not help; it makes the burst bigger.

### What the limit actually is

Worth stating plainly, because it is easy to quote the wrong number: the
familiar **60 per hour unauthenticated / 5,000 per hour authenticated** figures
are documented for the **REST API**, not for git. GitHub publishes no per-IP,
per-hour quota for `git clone` over HTTPS. The
[May 2025 changelog](https://github.blog/changelog/2025-05-08-updated-rate-limits-for-unauthenticated-requests/)
says the tightened unauthenticated limits apply to cloning, without giving a
number. The only git-specific figure GitHub publishes is in
[Repository limits](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits):

> Git read operations (e.g. fetches, clones): The recommended maximum limit is
> 15 operations per second per repository. […] Consider optimizing your CI's
> clone strategy and/or using a repository cache server. Note that shallow
> clones will impose less cost and burden on the server than full clones.

Per *second*, per *repository* — a different axis entirely, and a soft
recommendation rather than an enforced quota. Two consequences shape the design
below. GitHub's throttling appears to be **cost-weighted rather than
request-counted**, so making each request cheaper matters as much as making
fewer of them. And GitHub's *secondary* limits (including a concurrency
ceiling) apply to authenticated traffic too, so authentication alone is not
guaranteed to be sufficient.

## Two modes

`dronerunner_github_mode` selects the implementation. Both put the same
listener at the same address, so the rewrite inside the containers is identical
and switching is a host-side change that does not restart the runner.

| Mode | What nginx forwards to | Fixes authentication | Fixes volume |
|---|---|---|---|
| `proxy` | `github.com`, token added | yes | no |
| `mirror` | local `git-cache-proxy` | yes | yes |
| `false` | nothing installed | — | — |

`proxy` was the first implementation and remains the fallback. `mirror` is what
`clang4` runs. Falling back is one word in host_vars plus an ansible run; the
role tears down whichever mode is not selected.

## Mode `proxy`: the mechanism

Git clones are redirected, transparently, to a small nginx reverse proxy
running on the runner host itself. The proxy forwards to `github.com` and adds
a read-only token upstream.

```
pipeline container                    host                        github.com
-------------------                   ----                        ----------
git clone https://github.com/...      nginx on 10.201.0.1:8080    (real origin)
   |  url.*.insteadOf rewrites  ----> | proxy_pass + token -----> | authenticated
```

Three pieces cooperate:

1. **`templates/git-auth.env.j2`** — written to
   `/opt/drone/scripts/git-auth.env` and passed to the runner as
   `DRONE_RUNNER_ENV_FILE`, so it merges into every pipeline step's
   environment, which is where `.drone/drone.sh` runs its burst of clones:

   ```
   GIT_CONFIG_PARAMETERS="'url.http://10.201.0.1:8080/.insteadOf=https://github.com/'"
   ```

   `GIT_CONFIG_PARAMETERS` is used rather than the newer
   `GIT_CONFIG_COUNT/KEY/VALUE` because the former works on every git in the
   fleet, including git 2.29 in `droneubuntu2004:1`; the latter needs git 2.31.
   No credential appears here — the container only learns the proxy's address.

   **This does not reach Drone's built-in clone step.** Observed in job logs:
   the clone step reports `From https://github.com/...` while steps inside the
   pipeline report `From http://10.201.0.1:8080/...`, and git prints the URL
   *after* `insteadOf` rewriting, so the clone step is plainly not being
   rewritten. That one clone per job therefore still goes to github.com
   anonymously, in both modes. It is a small share of the traffic — the burst
   that caused the original throttling is the submodule clones inside
   `drone.sh`, which are covered — but it is not zero, and the gap predates
   mirror mode rather than being caused by it.

2. **`templates/gitproxy.conf.j2`** — the nginx `server` block, listening only
   on the docker bridge gateway address. It rewrites `Host` back to
   `github.com`, enables `proxy_ssl_server_name on` so the SNI name is
   `github.com` not the bridge IP, and injects the only copy of the token:

   ```nginx
   proxy_set_header Authorization "basic <base64 of x-access-token:<token>>";
   proxy_buffering off;      # git smart-HTTP streams packfiles
   proxy_read_timeout 300s;  # large repositories
   ```

3. **`tasks/linux.yml`** — the nginx install, vhost install/removal, and gateway
   detection. The proxy listens on the IP of the docker `bridge` network's
   gateway rather than `0.0.0.0`, so it is reachable only by containers on that
   bridge and not from the internet. The gateway is read at runtime with
   `docker network inspect bridge`, not hardcoded:

   ```yaml
   dronerunner_githubproxy_gateway: "{{ (docker_bridge_inspect.stdout | from_json)[0].IPAM.Config[0].Gateway }}"
   ```

   So the `default-address-pools` change to the docker daemon (`10.201.0.0/16`,
   size 26) that moved `docker0` to `10.201.0.0/26` with gateway `10.201.0.1`
   is absorbed automatically.

## Security posture

The token lives in exactly one place — `/etc/nginx/conf.d/gitproxy.conf` on the
host — and never enters a container, an `env` dump, or a `set -x` log, because
the environment variable only carries the proxy address, not the credential.
That is the advantage over injecting the token directly into pipeline
environments, where any step that runs `env` or `set -x` would print it.

The proxy is plain HTTP on the bridge, not TLS; that is acceptable on a trusted
local network, and the token is applied upstream, on the proxy's TLS connection
to GitHub, not on the bridge.

The token must be a machine-account token, read-only, with no write scopes.
Rotate it freely; revocation is cheap. It is per-host, defined in host_vars,
never in `defaults/main.yml`.

## Mode `mirror`: the caching mirror

`proxy` authenticates the clones but GitHub still generates and sends a
complete packfile for every one of them. With 15 parallel jobs cloning the same
superproject and the same few dozen submodules, that is the same expensive work
repeated 15 times within a few minutes — and it is the *cost* axis, which is
the one the evidence above suggests GitHub actually throttles on.

`mirror` splits the cheap part of a clone from the expensive part:

```
pipeline container            host                                  github.com
-------------------           ----                                  ----------
git clone https://github...   nginx 10.201.0.1:8080                 (real origin)
  | insteadOf rewrite  ---->  | proxy_pass 127.0.0.1:8081
                              |   git-cache-proxy
                              |     bare mirror per repo
                              |     git fetch --prune  ----------->  | cheap: refs
                              |     git upload-pack  (local)         |   only, no
                              |     packfile built here              |   packfile
```

Ref discovery and negotiation still go to GitHub on every clone, so the mirror
is never stale for the ref a client asked for — including a pull request head
pushed seconds ago. The packfile, which is all the CPU and all the bytes, is
built locally. Concurrent clients for the same repo are serialized behind one
per-repo lock, so a burst of identical clones triggers a single upstream fetch.

Four pieces, all installed only when the mode is `mirror`:

1. **`templates/git-cache-proxy.service.j2`** — a systemd unit running
   [`git-cache-proxy`](https://github.com/rolandjitsu/git-cache-proxy) as an
   ordinary unprivileged process, not a container (see *Why not a container*
   below). `--upstream https://github.com` means any path works, so anything a
   pipeline clones is mirrored — there is no per-organisation allowlist, and
   the occasional clone from outside `boostorg` is handled like any other.

2. **`templates/gitmirror.env.j2`** — a systemd `EnvironmentFile` holding
   `GITCACHEPROXY_UPSTREAM_AUTH_HEADER`. This is where the token lives in this
   mode. Passing it by environment rather than argv keeps it out of `ps` and
   out of the unit file; the daemon hands it to git as `http.extraHeader` on
   upstream fetches only. systemd opens the file as root before dropping to
   the service account, so it stays root-owned `0600` and the daemon's own
   user cannot read it.

3. **`templates/gitmirror.conf.j2`** — the nginx vhost, same listener address
   as the `proxy` one but forwarding to loopback. It adds no `Authorization`
   header: the mirror authenticates upstream itself. It does pass the client's
   `Git-Protocol: version=2` header straight through, which is load-bearing.

4. **`tasks/linux.yml`** — builds the daemon, installs the above, and tears
   down the mirror service, unit, vhost and env file when the mode is
   anything else.

### Why not a container

It was one originally, and the reasons not to were better. A container is one
more entry in `docker ps` next to the job containers, which is exactly where
you don't want something that must not be swept up by a cleanup. It makes the
mirror depend on docker — mildly circular, since the `Restart docker` handler
for the address pool would take it down with it. And the security argument runs
the *wrong* way: the published image has no `USER`, so it runs as root with the
cache bind-mounted, whereas a plain unit gets `User=`, `ProtectSystem=strict`,
and a `ReadWritePaths=` confined to the cache.

The binary is root-owned and the service account cannot rewrite it; the account
only owns the cache.

### Building from source

Upstream publishes no release binaries, so the role builds the pinned tag. Two
things make that less painful than it sounds.

It is keyed on the installed binary's own `--version`, so the eight build tasks
are skipped on every steady-state run. Bumping
`dronerunner_githubmirror_version` is what re-triggers a build, and `--locked`
means the dependency versions come from upstream's committed `Cargo.lock`
rather than whatever the registry offers that day.

The toolchain comes from rustup into `/usr/local/rustup` and `/usr/local/cargo`
rather than from apt, and that is not a preference — the crate is edition 2024,
which needs rustc 1.85 or newer, and no Debian or Ubuntu release ships one. The
toolchain is build-time only; the running service needs nothing but the binary
and `git`.

A C compiler is required despite this being Rust, because the TLS stack is
rustls over `ring` and `ring` builds its own assembly. No `libssl-dev` — there
is no openssl in the dependency tree at all.

### Force-pushes need no special handling

A common worry, and the answer is a property of how the mirror is built rather
than anything the daemon does. `git clone --mirror` configures the refspec
`+refs/*:refs/*`, and the leading `+` accepts non-fast-forward updates — so a
force-pushed branch (a rebased pull request, most often) is simply followed on
the next fetch. `--prune` covers branches deleted upstream. The intuition that
a force-push "breaks the pull" comes from `git pull` in a working tree, which
is not what a bare mirror does.

What can genuinely wedge a mirror is narrower: a stale `.lock` from a fetch
killed mid-flight, a disk-full, or corruption. The daemon does not self-heal
from those, so a periodic sweep that removes any mirror failing
`git fsck --connectivity-only` is worth adding; an absent mirror is
transparently re-cloned on next request.

### Operational notes

`--fetch-ttl-seconds` is the freshness dial. `0` revalidates against GitHub on
every clone; the default `10` collapses a simultaneous burst into one fetch and
is far below the gap between a push and the build it triggers. Raise it if the
binding constraint turns out to be request count rather than bytes.

`--cache-max-mb` is set because the daemon's own default is unlimited with no
accounting. Mirrors are evicted least-recently-used and re-cloned on demand.
Switching away from mirror mode removes the vhost, the unit and the credential,
but deliberately leaves the cache, the binary and the service account in place,
so switching back costs seconds rather than a rebuild and a few hundred clones.

Endpoints for checking on it, on the loopback port:

```bash
curl -s localhost:8081/healthz
curl -s localhost:8081/metrics | grep -E 'upstream|cache_size'
systemctl status git-cache-proxy
journalctl -u git-cache-proxy -f
du -sh /var/cache/git-cache-proxy
```

**If one repo consistently fails** with a `502` from the mirror, that repo's
cache directory is wedged — most likely a stale `.lock` from a fetch killed
mid-flight. `rm -rf` it and it is re-cloned on the next request. There is no
periodic fsck sweep on purpose: the failure is loud rather than silent (the
daemon returns `502` and increments a per-repo error counter in `/metrics`
instead of serving stale), the blast radius is one repo, and walking hundreds
of mirrors nightly costs more IO than the problem is worth.

The cache must be owned by the service account, because git 2.35.2 and later
refuse to operate on a repository owned by a different user. The role sets
ownership on the cache directory but does not recurse, since a populated cache
is millions of files. **Migrating a cache created by some other uid therefore
needs a one-time `chown -R`** — or just delete it and let it re-clone.

The daemon is read-only: it refuses `git-receive-pack`, so nothing can be
pushed through it. It also has **no per-repo authorization** — it serves
whatever its upstream credential can read to anyone who can reach the port.
That is why it publishes on `127.0.0.1` and nginx is the only thing in front of
it.

Upstream describes itself as early, single-maintainer software, which is why
`dronerunner_githubmirror_version` pins a tag, and why `proxy` is kept as a
working fallback rather than deleted.

## Manual test (no drone, no runner)

The environment variable is normally injected by the runner; for a manual test
you set it yourself. The rewrite is applied by `git`, so a plain clone already
proves the redirect, but not the authentication. Do two checks.

1. **Redirect works** — run a container and point git at the proxy. If the
   proxy is up, the clone resolves through it instead of `github.com`:

   ```sh
   docker run --rm cppalliance/droneubuntu2004:1 bash -c \
     'export GIT_CONFIG_PARAMETERS="'"'"'url.http://10.201.0.1:8080/.insteadOf=https://github.com/'"'"'"; \
      git clone --depth 1 https://github.com/boostorg/boost.git /tmp/boost'
   ```

   To *prove* the rewrite rather than just succeed, point the rewrite at a
   dead address — the clone then fails trying to reach that address instead of
   GitHub:

   ```sh
   export GIT_CONFIG_PARAMETERS="'url.http://10.201.0.1:9999/.insteadOf=https://github.com/'"
   git ls-remote https://github.com/boostorg/boost.git develop
   # fatal: unable to access 'http://10.201.0.1:9999/boostorg/boost.git/': ...
   ```

2. **Authentication works** — the tell is GitHub's response to a bad token.
   Anonymous public clones return `200`; a request carrying an invalid token
   returns `401`, because GitHub actually evaluated the credential. So hit the
   proxy's upstream endpoint both ways and compare:

   ```sh
   echo "anonymous (expect 200):"
   curl -s -o /dev/null -w '%{http_code}\n' \
     'https://github.com/boostorg/boost.git/info/refs?service=git-upload-pack'

   echo "bad token (expect 401):"
   curl -s -o /dev/null -w '%{http_code}\n' \
     -H "Authorization: basic $(printf 'x-access-token:ghp_FAKE' | base64)" \
     'https://github.com/boostorg/boost.git/info/refs?service=git-upload-pack'
   ```

   With the real token wired into the proxy, the same `curl` against
   `http://10.201.0.1:8080/boostorg/boost.git/info/refs?service=git-upload-pack`
   returns `200` with the token, where a *bogus* token through the proxy would
   produce the throttling signature you originally saw. This is the contrast to
   check when you suspect the token in the vhost is stale or mistyped.

## `server_name` and other hostnames

The vhost uses `server_name _;`, which in nginx means "any hostname not matched
by another `server` block". Two things make this safe rather than sloppy:

- It shares the `listen` directive with nothing else. It listens only on
  `10.201.0.1:8080`; a future public vhost would listen on the public interface
  on `80`/`443`. nginx selects a server per `address:port`, so a catch-all on
  one `address:port` cannot shadow a vhost on a different one.
- On a single `address:port`, nginx allows only one default server. Two vhosts
  both claiming the same listen with `server_name _;` (or both marked
  `default_server`) is a configuration error at reload. Different listen
  addresses keep that from ever arising between the proxy and any public vhost.

`server_name` can be an IP literal — `server_name 10.201.0.1;` is legal — but it
would only match when the client's `Host` header is literally `10.201.0.1`, and
git sends `Host: 10.201.0.1:8080`, so the port would make it miss. `_` matches
the real `Host` value (IP with port) robustly, which is why it is used.

## `raw.githubusercontent.com` is a different service

The 60/hour anonymous limit applies to raw downloads in the same changelog that
covers anonymous clones. But raw cannot be fixed the same way, because it
**ignores `Authorization` headers** — a request with a valid token and one
without both return `200` anonymous. There is no authenticated raw endpoint to
point a proxy at with token injection.

If raw downloads ever do hit the limit, the authenticated path is the repository
Contents API, which is a URL *and header* change, not a proxy change:

```sh
curl -H "Authorization: token <token>" \
     -H "Accept: application/vnd.github.raw+json" \
     "https://api.github.com/repos/OWNER/REPO/contents/PATH?ref=BRANCH"
```

For the Boost CI in particular, raw is used sparingly — `functions.star` fetches
a handful of small script files per pipeline — so it is orders of magnitude
below the clone burst and not worth proxying today.
