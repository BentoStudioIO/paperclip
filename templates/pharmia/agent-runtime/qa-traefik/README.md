# QA Traefik config for self-hosted Daytona (sandbox exec routing)

These files make the Daytona SDK / Paperclip `executeCommand` work against the self-hosted
stack on the QA host (`PH_38BWrBFFVYaGINxbTb`, 51.222.25.80, `ssh qa`). They are **not** managed
by Dokploy — Dokploy's domain API can't express a path-prefix route or a wildcard-SNI TLS cert,
so they are applied out-of-band to the host's Traefik (the standalone `dokploy-traefik` container).

## The bug they fix

The api advertises `sandbox.toolboxProxyUrl = https://daytona.bentostudio.io/toolbox`
(app host + `/toolbox`; this is **not** derived from `PROXY_DOMAIN`). The SDK therefore POSTs
exec to `https://daytona.bentostudio.io/toolbox/<sandboxId>/process/execute`. But
`daytona.bentostudio.io` routes to `api:3000`, which serves the dashboard SPA catch-all at
`/toolbox` and returns 200 HTML. The SDK can't parse that, so `executeCommand` silently returns
`{"result":"","artifacts":{"stdout":""}}`. The daemon, runner, and proxy were all healthy the
whole time — only the public routing of `/toolbox` (and the wildcard preview host) was missing.

The working endpoint is the `proxy` service (`TOOLBOX_ONLY_MODE=true`), reachable internally as
`http://compose-override-redundant-feed-qo9ky7-proxy-1:4000` on the `dokploy-network`.

## Files

- `traefik.yml` — host static config (`/etc/dokploy/traefik/traefik.yml`). Adds a second ACME
  resolver `cloudflare` using DNS-01 (the only ACME challenge that can issue a wildcard cert),
  separate storage `acme-cloudflare.json` so the existing `letsencrypt` resolver is untouched.
- `daytona-toolbox-path.yml` — dynamic file-provider route (drop in
  `/etc/dokploy/traefik/dynamic/`): `Host(daytona.bentostudio.io) && PathPrefix(/toolbox)` ->
  proxy:4000, priority 1000 (above the api host router, priority 30). This is what makes SDK exec
  work. Reuses the existing `daytona.bentostudio.io` (letsencrypt) cert.
- `daytona-wildcard.yml` — dynamic file-provider route: `HostRegexp(*.daytona.bentostudio.io)`
  -> proxy:4000 for per-sandbox preview ports (`PROXY_TEMPLATE_URL`). Requests the wildcard cert
  via the `cloudflare` resolver. Low priority so the exact `Host()` routers win.

> Both `.yml` files are Go templates to Traefik's file provider — never put `{{...}}` tokens in
> comments or it fails with `function "PORT" not defined`.

## Apply on a fresh / rebuilt QA host

1. Put the CF DNS-edit token (the same one `cfdns` uses, `$CLOUDFLARE_API_TOKEN`) into the
   `dokploy-traefik` container as env `CF_DNS_API_TOKEN` (Lego reads it for the cloudflare
   provider). Traefik is a standalone container, so this means recreating it with the same
   image/ports/binds/networks plus `-e CF_DNS_API_TOKEN=<token>`. Networks at time of writing:
   `dokploy-network` (primary) + `pharmia-qa-xdb2q7`. Ports 80, 443/tcp, 443/udp.
2. Copy `traefik.yml` to `/etc/dokploy/traefik/traefik.yml` and
   `touch /etc/dokploy/traefik/dynamic/acme-cloudflare.json && chmod 600` it.
3. Copy `daytona-toolbox-path.yml` and `daytona-wildcard.yml` into
   `/etc/dokploy/traefik/dynamic/` (Traefik live-reloads; no recreate needed).
4. DNS: ensure `*.daytona.bentostudio.io` and `daytona.bentostudio.io` A records point to the QA
   IP, proxied=false (`cfdns ls bentostudio.io | grep daytona`).

## Verify

```
AK=$(grep DAYTONA_ADMIN_API_KEY ~/.config/daytona/qa-secrets.env | cut -d= -f2- | tr -d '"'"'"' ')
node -e 'const {Daytona}=require("@daytonaio/sdk");(async()=>{const d=new Daytona({apiKey:process.env.AK,apiUrl:"https://daytona.bentostudio.io/api"});const s=await d.create({snapshot:"pharmia-agent-runtime"});const r=await s.process.executeCommand("echo OK && node -v");console.log(JSON.stringify(r));await d.delete(s);})()' # AK=$AK
```

Expect `exitCode:0` with non-empty stdout. The service container name in the route files
(`compose-override-redundant-feed-qo9ky7-proxy-1`) is the Dokploy-generated appName — if the
compose is recreated under a new appName, update the `loadBalancer.servers[].url` accordingly.
