# Deploying Mythreach

Mythreach has **two halves** that deploy to **different places**:

| Part | What it is | Where it goes |
|---|---|---|
| **Web client** | The Godot HTML5 export (static `index.html` + `.wasm` + `.pck`) | **Vercel** (static hosting) |
| **Game servers** | `master`, `gateway`, `world` — long-running headless Godot processes (HTTP + WebSocket) | A **persistent host** (Fly.io / Railway / a VPS). **NOT Vercel.** |

> Vercel only serves static files and short serverless functions — it **cannot** run the persistent, stateful WebSocket game servers. Those must live on a normal host.

---

## 1. Deploy the web client to Vercel

### Build it (locally — needs Godot 4.7 + web export templates)
```bash
./build-web.sh        # release export → exports/web/ (+ favicon)
```

### Deploy it
Install the CLI once (`npm i -g vercel`), then from the repo root:
```bash
vercel deploy --prod
```
`vercel.json` serves `exports/web/` as the static site and `.vercelignore` keeps the
upload to just the built client. First deploy will ask you to link/create a project.

**Git integration alternative:** if you connect the repo to Vercel for auto-deploys on
push, you must **commit `exports/web/`** (Vercel has no Godot to build it). The `.pck`
+ `.wasm` are ~65 MB — consider Git LFS, or just use the CLI flow above (no commit needed).

No special COOP/COEP headers are required — the web preset has `thread_support=false`,
so the build is single-threaded and runs on plain static hosting.

---

## 2. Point the client at your live servers

The web client decides which gateway to call in
[`source/common/network/gateway_api.gd`](source/common/network/gateway_api.gd) →
`base_url()`:

- Served from `localhost` → `http://127.0.0.1:8088` (local dev)
- Served from any other host (i.e. Vercel) → **`https://37-60-232-191.sslip.io`**

Change `37-60-232-191.sslip.io` if you move to another server/domain. Because the Vercel page is
HTTPS, the gateway MUST be reachable over **HTTPS** (and the world over **WSS**) — a
secure page cannot talk to `http://`/`ws://` (mixed-content). Put the servers behind a
TLS reverse proxy (Caddy/nginx) that terminates HTTPS/WSS and forwards to them.

---

## 3. Run the game servers (separate host)

Run all three as headless Godot processes (or export the dedicated-server build via the
`ServerUbuntu` preset and run that):
```bash
godot --headless --path . --mode=master-server
godot --headless --path . --mode=gateway-server
godot --headless --path . --mode=world-server
```
- **master** holds accounts/auth + the world registry.
- **gateway** exposes the HTTP API on `:8088` (wallet challenge/login, world list).
- **world** runs the simulation and serves the game over **WebSocket**.

### Reverse proxy (example: Caddy)
```
37-60-232-191.sslip.io {
    handle /v1/* {
        reverse_proxy 127.0.0.1:8088 {
            header_up X-Real-IP {remote_host}
        }
    }

    handle_path /world* {
        reverse_proxy 127.0.0.1:8087
    }

    handle {
        root * /opt/mythreach/web
        file_server
    }
}
```
Expose the world server's WebSocket over `wss://` similarly (the client accepts a full
`wss://…` URL — see `base_multiplayer_endpoint.create`). The enter-world response's
`address`/`port` must resolve to that public WSS endpoint in production.

### Production auth is enforced
The dev-wallet bypass + spectator shortcut only apply when the master runs **from the
editor** (`OS.has_feature("editor")`). Exported/headless production servers enforce real
**ed25519** Phantom signature verification — no bypass. Keep accounts persisted under
`user://master/` (writable) on the host.

---

## 4. Checklist
- [ ] `./build-web.sh` produces `exports/web/index.html`
- [ ] `base_url()` production domain points at your server
- [ ] Servers running behind HTTPS/WSS (Caddy/nginx)
- [ ] `vercel deploy --prod` → open the URL, Connect Wallet works end-to-end
