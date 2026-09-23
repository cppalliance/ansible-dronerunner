# GitHub clone authentication proxy

The drone runner on `clang4.cpp.al` runs many pipelines in parallel, and each
Boost pipeline issues a burst of anonymous `git clone` requests inside
`.drone/drone.sh` (the superproject, `boostdep`, and one clone per dependency
module). GitHub throttles unauthenticated git traffic at roughly 60 requests
per hour per source IP, and a throttled request surfaces as:

```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

Raising parallelism does not help; it makes the burst bigger. The fix is to move
the clones into GitHub's *authenticated* bucket, which holds roughly 5,000
requests per hour per source IP.

## The mechanism

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
   `DRONE_RUNNER_ENV_FILE`, so it merges into every pipeline step's environment
   (run by `git` in the container) *and* the built-in clone step's environment:

   ```
   GIT_CONFIG_PARAMETERS="'url.http://10.201.0.1:8080/.insteadOf=https://github.com/'"
   ```

   `GIT_CONFIG_PARAMETERS` is used rather than the newer
   `GIT_CONFIG_COUNT/KEY/VALUE` because the former works on every git in the
   fleet, including git 2.29 in `droneubuntu2004:1`; the latter needs git 2.31.
   No credential appears here — the container only learns the proxy's address.

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
