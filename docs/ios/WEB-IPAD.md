# Use LightCraft on iPad Safari

The web app is the usable iPad path while the native iOS host is being built. The web library is stored by Safari for this site; keep a separate copy of originals and use **File → Back Up Library…**.

## Build and serve over trusted HTTPS

On the Mac, from the repository root. The web build needs the versioned `wasm-bindgen` CLI; install the version pinned in this checkout if it is not already on `PATH`:

```sh
export CARGO_BUILD_JOBS=2
cargo install wasm-bindgen-cli --version 0.2.129 --locked
cargo xtask web
cargo xtask web --serve 8080
```

`--serve` binds to `127.0.0.1` for local desktop use. Safari will not treat `http://<Mac-LAN-IP>` as a secure context, so OPFS and WebGPU may be unavailable there. To test on the iPad, expose that local server through a temporary HTTPS tunnel:

```sh
brew install cloudflared       # once, if not already installed
cloudflared tunnel --url http://127.0.0.1:8080
```

Keep the tunnel running. Copy the generated `https://…trycloudflare.com` URL into Safari on the iPad. Cloudflare's public quick tunnel makes the test URL reachable outside the LAN while it is running; do not import private photos through it. For private photo testing, deploy the generated `target/web-site/` directory to a trusted HTTPS host you control and open that origin on the iPad. Do not use a plain HTTP LAN IP for storage or WebGPU testing.

## Install and verify

1. Open the HTTPS URL in Safari. Wait for the demo library grid to appear.
2. Tap **Share → Add to Home Screen**, leave the title as **LightCraft**, and tap **Add**.
3. Open the new Home Screen icon. It should launch without Safari's address bar, with the app content inside the safe area.
4. Open a demo photo. Drag a develop slider and confirm the image changes. Use a two-finger pinch to zoom and a two-finger drag to pan. Double-tap the image to switch between fit and the selected click zoom.
5. Tap **File → Import Photos…** and choose a photo from Files. Confirm it appears in the grid; then reload and confirm it remains. Photos in iCloud may need to finish downloading first.
6. Export a JPEG and confirm Safari offers it as a download. Use **File → Back Up Library…** before clearing site data or uninstalling the Home Screen app.

Touch devices receive larger shared egui interaction heights, and the web host limits simultaneous render workers to two on a touch device. The app still uses the browser's WebGL2 path; Safari support varies by iPadOS version. Pencil pressure, long-press secondary click, and native Photos importing are not provided by this PWA.

## Troubleshooting

- If OPFS is unavailable, the browser host falls back to IndexedDB. **Help → About** / browser console diagnostics can show the active backend.
- A page opened by a plain LAN `http://` address is not suitable for validating OPFS/WebGPU. Check that Safari shows the HTTPS tunnel or deployed site.
- If the screen is blank, reload after confirming the Mac's web server and tunnel are both still running.
- Keep only one app tab/window open for this origin. The browser host uses a Web Lock when available to prevent two tabs from writing the same library.
