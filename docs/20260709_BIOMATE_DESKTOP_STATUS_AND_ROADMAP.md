# BioMate Desktop — Current Status & Work Remaining

**Date:** 2026-07-09  
**Version:** 0.1.0  
**Framework:** Tauri v2 (Rust + WebView)  
**Source:** `desktop/` directory in the monorepo

---

## What Is It

BioMate Desktop is a native wrapper around the BioMate web application. It uses **Tauri v2** — a Rust-based framework that embeds the OS's native WebView (WebKit on macOS, WebView2 on Windows, WebKitGTK on Linux) and exposes a thin Rust IPC layer to the frontend JavaScript.

The frontend code is **shared** with the web app (`frontend/client/dist`). The desktop shell adds capabilities the browser cannot provide: native file pickers, encrypted credential storage, system notifications, and the ability to point the app at a local BioMate server instead of the cloud.

---

## Platform Support

| Platform | Artifact | Architecture | Status |
|---|---|---|---|
| macOS | `.app` / `.dmg` | x86_64 + arm64 (Universal Binary possible) | ✅ Supported |
| Windows | `.msi` / `.exe` | x86_64 | ✅ Supported |
| Windows ARM | `.msi` | aarch64 | ⚠️ Not yet built |
| Linux | `.deb` / `.AppImage` | x86_64 | ✅ Supported |
| Linux ARM | `.deb` | aarch64 (Graviton, Pi) | ⚠️ Not yet built |

---

## What Is Already Built

### Rust IPC Commands (`desktop/src-tauri/src/lib.rs`)

| Command | Description |
|---|---|
| `get_token` / `set_token` / `delete_token` | Auth JWT stored in Tauri's encrypted key-value store (`tauri-plugin-store`), persists across app restarts |
| `get_server_url` / `set_server_url` | User's chosen server URL — defaults to `https://dev-public.biomate.ai` |
| `pick_files` | Native OS file picker with bioscience format filters (FASTQ, BAM, VCF, FASTA, SDF, MRC, HDF5, PDF, etc.) |
| `pick_output_directory` | Native folder picker for selecting output directories |
| `get_app_info` | Returns version, platform (macos/windows/linux), and mode (currently always `"client"`) |

### Tauri Plugins Loaded

- `tauri-plugin-store` — encrypted local KV store (replaces raw OS keychain)
- `tauri-plugin-dialog` — native file/folder pickers, alert dialogs
- `tauri-plugin-shell` — open URLs in system browser
- `tauri-plugin-http` — HTTP client from Rust side
- `tauri-plugin-notification` — OS-level desktop notifications (loaded but not yet triggered)
- `tauri-plugin-os` — OS version and type detection

### Frontend Integration (`frontend/client/src/lib/desktop.ts`)

All Rust commands are bridged via `window.__TAURI__`. Every function gracefully degrades to a no-op in the browser, so the same React codebase works for both targets without ifdefs:

```typescript
isDesktop()                    // true only inside Tauri
desktopGetToken() / desktopSetToken(token) / desktopDeleteToken()
desktopGetServerUrl() / desktopSetServerUrl(url)
desktopPickFiles()             // native picker → returns [{path, name, size}]
desktopPickOutputDirectory()   // native folder picker
desktopGetAppInfo()            // {version, platform, mode}
desktopPickAndUpload(projectId) // pick + stream upload to /api/projects/:id/files/upload
```

### UI Integration

- **Settings dialog** — `DesktopConnectionSettings` component shows Connection Mode panel (Cloud / Local / Custom URL) and app version/platform. Rendered only when `isDesktop()` is true.
- **Project file tree** — `ProjectFileTree` uses `desktopPickAndUpload()` on desktop for native file selection; falls back to `<input type="file">` in the browser.

### Window Configuration

```
Default size: 1440 × 900 px
Minimum size: 960 × 640 px
Tray icon:    icons/tray.png (template mode for macOS dark/light)
macOS private API: enabled (allows blur/vibrancy effects)
```

---

## How to Build

### Prerequisites

```bash
# Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# macOS: Xcode command line tools
xcode-select --install

# Windows: Visual Studio Build Tools + WebView2 (usually pre-installed on Win 10/11)

# Linux: webkit2gtk-4.1 + libgtk-3-dev
sudo apt install libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev
```

### Dev Mode (points WebView at localhost:5000)

```bash
# Terminal 1: start the BioMate web server
cd frontend && npm run dev

# Terminal 2: launch the desktop shell
cd desktop && npm run dev   # runs: tauri dev
```

### Production Build

```bash
cd desktop
npm run build               # runs: tauri build
# Output: desktop/src-tauri/target/release/bundle/
#   macOS:   BioMate.app  /  BioMate_0.1.0_x64.dmg
#   Windows: BioMate_0.1.0_x64.msi
#   Linux:   biomate_0.1.0_amd64.deb  /  BioMate_0.1.0_amd64.AppImage
```

### ARM Targets (cross-compile)

```bash
# macOS Universal Binary (Intel + Apple Silicon)
rustup target add aarch64-apple-darwin
tauri build --target universal-apple-darwin

# Windows ARM
rustup target add aarch64-pc-windows-msvc
tauri build --target aarch64-pc-windows-msvc

# Linux ARM64
rustup target add aarch64-unknown-linux-gnu
cargo install cross
tauri build --target aarch64-unknown-linux-gnu
```

---

## Connection Modes

The desktop app currently operates in **client mode only** (Phase 1): it points the embedded WebView at a remote BioMate server (cloud or self-hosted). Users can switch between three modes in Settings:

| Mode | URL | Use Case |
|---|---|---|
| **Cloud** | `https://dev-public.biomate.ai` | Default — full cloud infrastructure, AWS Batch runs |
| **Local** | `http://localhost:5000` | Developer running BioMate locally |
| **Custom** | User-entered URL | Self-hosted institutional deployments |

When the user switches modes, the WebView reloads pointed at the new URL and the auth token is sent via the desktop store.

---

## Work Remaining

### 1. Code Signing & Notarization (BLOCKER for distribution)

**macOS:**
- `signingIdentity: null` in `tauri.conf.json` → app is not signed
- Unsigned `.app` files are blocked by Gatekeeper on macOS 13+ without right-click → Open
- Requires: Apple Developer account ($99/yr), Developer ID certificate, `xcrun notarytool` notarization
- After signing: add `signingIdentity: "Developer ID Application: BioMate AI (XXXXXXXXXX)"` and set `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` env vars in CI

**Windows:**
- `certificateThumbprint: null` → no EV/OV code signing
- Unsigned `.msi` triggers SmartScreen warning on every install
- Requires: EV code signing certificate (~$300-500/yr from DigiCert/Sectigo) or Microsoft Trusted Signing

### 2. Auto-Updater

- `tauri-plugin-updater` is **not** in `Cargo.toml`
- Users must manually download new `.dmg`/`.msi` for every release
- Work required:
  - Add `tauri-plugin-updater = "2"` to Cargo.toml
  - Add update endpoint to `tauri.conf.json`: `"updater": { "active": true, "endpoints": ["https://releases.biomate.ai/{{target}}/{{arch}}/{{current_version}}"] }`
  - Set up the update server (can be a GitHub Releases JSON feed or a simple S3 endpoint)
  - Emit update-available notification from the tray icon

### 3. Release Pipeline (CI/CD)

No GitHub Actions workflow exists for building and publishing desktop artifacts. Need:
- `.github/workflows/desktop-release.yml`
- Triggers on `git tag v*.*.*`
- Matrix builds: `[macos-latest, windows-latest, ubuntu-22.04]`
- Uploads artifacts to GitHub Releases
- macOS runner needs `APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` secrets
- Windows runner needs code signing secrets

### 4. Host Mode (Fully Offline / Air-Gapped)

`get_app_info` returns `mode: "client"` hardcoded. A planned **host mode** would bundle the BioMate backend inside the desktop app so it runs fully offline:

- Bundle Node.js 22 sidecar (`tauri-plugin-shell` sidecar mechanism)
- Bundle a Python 3.11 sidecar for the Galaxy backend
- Start both on app launch via Tauri's sidecar lifecycle
- Switch mode to `"host"` in `get_app_info`
- Required for: air-gapped hospital/pharma deployments, offline field research

This is significant work (bundled binary size would grow to ~500 MB+).

### 5. Run Completion Notifications

`tauri-plugin-notification` is registered but never triggered. When a long workflow run completes on AWS Batch, the desktop app should fire an OS notification even if the window is minimized:

- Backend already sends SSE events on run completion
- Desktop frontend needs to catch `run_completed` SSE events and call `sendNotification({ title: "Run complete", body: workflow.name })`
- Requires: `"notification"` permission already in `capabilities/default.json` ✅

### 6. Deep Link Handling

No `tauri-plugin-deep-link` registered. Useful for:
- `biomate://session/<id>` — open a specific chat session from a link
- `biomate://project/<id>` — open a project directly
- Email notification links that open the desktop app instead of the browser

### 7. Windows ARM & Linux ARM Builds

Cross-compilation targets not yet set up in any build script. Needed for:
- Windows on ARM (Surface Pro X, Snapdragon X Elite machines)
- Linux ARM64 (AWS Graviton CI runners, institutional HPC nodes)

### 8. Mac App Store (Optional)

Distributing via MAS requires additional work beyond standard notarization:
- App Sandbox entitlements (stricter than current `entitlements.plist`)
- Network access declarations for all domains contacted
- In-App Purchase API if any paid features are gated
- macOS-specific review guidelines compliance

### 9. Token Bootstrap on Cold Start

The desktop stores the JWT in `tauri-plugin-store`. On app launch the frontend needs to read it and inject it before any authenticated API calls fire. This flow needs an E2E test to confirm it works reliably across restarts and after token expiry.

---

## File Map

```
desktop/
├── package.json                    # npm scripts: dev / build / icons
├── src-tauri/
│   ├── Cargo.toml                  # Rust dependencies
│   ├── tauri.conf.json             # Window config, bundle targets, signing
│   ├── capabilities/default.json   # Plugin permissions
│   ├── entitlements.plist          # macOS sandbox entitlements
│   ├── icons/                      # App icons (all sizes + .icns + .ico)
│   └── src/
│       ├── main.rs                 # Entry point
│       └── lib.rs                  # All IPC commands

frontend/client/src/
├── lib/desktop.ts                  # JS bridge (gracefully degrades in browser)
└── components/
    └── desktop-connection-settings.tsx  # Settings panel (desktop-only)
```

---

## Priority Order

| Priority | Item | Effort |
|---|---|---|
| 🔴 Blocker | Code signing (macOS + Windows) | 1-2 days + certificates |
| 🔴 Blocker | Release CI/CD pipeline | 1 day |
| 🟠 High | Auto-updater | 0.5 day |
| 🟠 High | Run completion notifications | 0.5 day |
| 🟡 Medium | Deep link handling | 1 day |
| 🟡 Medium | Token cold-start E2E test | 0.5 day |
| 🟢 Low | Windows ARM / Linux ARM builds | 1 day |
| 🟢 Low | Host mode (offline bundling) | 1-2 weeks |
| 🟢 Optional | Mac App Store submission | 3-5 days |
