# Desktop Build Fixes & OpenRouter LLM Selection

**Date:** 2026-07-11  
**Branch:** `integration/next-phase`  
**Commits:** `b67b35e` → `aac3378`

---

## 1. Desktop Build Fixed

The Tauri desktop app was failing to build with misleading errors. Three root causes were fixed:

### `tauri.conf.json` errors

| Problem | Fix |
|---|---|
| `bundle.macOS.urlSchemes` — Tauri v1 syntax, invalid in v2 | Removed; deep link schemes already correctly in `plugins.deep-link` |
| `frontendDist: "../frontend/client/dist"` — wrong path | Changed to `../../frontend/dist/public` (frontend builds to `frontend/dist/public/`) |

### Rust compilation errors (`src/lib.rs`)

| Error | Fix |
|---|---|
| `on_open_urls` does not exist | Renamed to `on_open_url` (correct Tauri v2 API) |
| `get_webview_window` not in scope | Added `use tauri::Manager` |
| `emit` not in scope | Added `use tauri::Emitter` |

**Result:** Desktop builds to an 11 MB DMG at `desktop/src-tauri/target/release/bundle/dmg/`.

---

## 2. OS Notifications Fixed

`tauri-plugin-notification` was registered but never fired because `desktopNotify()` in `desktop.ts` used `window.__TAURI__?.notification` — which is only available when `withGlobalTauri: true` (we use `false`).

**Fix:** Added a `notify` Rust command in `lib.rs` and routed `desktopNotify()` through `invoke("notify", { title, body })`, consistent with every other plugin call.

```rust
// lib.rs
#[tauri::command]
fn notify(app: AppHandle, title: String, body: String) {
    let _ = app.notification().builder().title(&title).body(&body).show();
}
```

```typescript
// desktop.ts — before (broken)
const notification = (window as any).__TAURI__?.notification;
notification.sendNotification({ title, body });

// desktop.ts — after (works)
invoke("notify", { title, body }).catch(() => {});
```

Notifications fire on run completion via both the SSE path and the polling path in `useUnifiedExecution.ts`.

---

## 3. OpenRouter LLM Selection

Users can now choose any model from OpenRouter (200+ models, including cheap Chinese providers) instead of the default Anthropic Claude.

### Priority order

```
1. User's own OpenRouter key + their chosen model  (Settings → LLM Provider)
2. Server OPENROUTER_API_KEY env var + OPENROUTER_DEFAULT_MODEL
3. Anthropic Claude  (existing default — unchanged)
```

No existing users are affected unless the server env vars are set.

### Server configuration

Add to EC2 environment to enable cheap models for all users:

```bash
OPENROUTER_API_KEY=sk-or-v1-...
OPENROUTER_DEFAULT_MODEL=deepseek/deepseek-chat   # optional — this is the default
```

Users who set their own key in Settings always override the system key.

### User configuration (Settings → LLM Provider)

- Select **OpenRouter**
- Paste API key from `openrouter.ai`
- Type any model slug from `openrouter.ai/models` (filter by DeepSeek, Qwen, etc.)
- Save

No hardcoded model list — the field accepts any slug so it never goes stale.

### Auto-fallback

If the selected model fails (rate limit, model removed, etc.), the backend automatically retries with `deepseek/deepseek-chat` and shows a one-line notice in the chat before the response continues.

```
*(selected-model unavailable, switching to deepseek/deepseek-chat)*
```

If the fallback also fails, an error message is shown.

### Files changed

| File | Change |
|---|---|
| `frontend/server/galaxy-assistant.ts` | Added `openrouterKey`/`selectedModel` to `ChatContext`; added `_generateChatWithOpenRouter()` with fallback retry; updated default from versioned slug to `deepseek/deepseek-chat` alias |
| `frontend/server/routes.ts` | Loads user OR system OpenRouter key; passes to `ChatContext`; updated `GET/PATCH /api/user/llm-api-keys` |
| `frontend/client/src/components/settings-dialog.tsx` | Replaced static model dropdown with free-text slug input; radio for Default vs OpenRouter |
| `frontend/client/src/components/chat-interface.tsx` | Model badge in header when OpenRouter active; × to revert |

### Note on model list

We intentionally do **not** maintain a preset model list — any hardcoded list goes stale within weeks. Users look up current model slugs at `openrouter.ai/models`.

---

## 4. Project Module — Verified Working

Two features were verified as already fully implemented (no changes needed):

**Project context → LLM:** When `projectId` is set on a chat, the backend loads `name + description + research_goal` from `memory_projects` and injects it into the system prompt via `<project_context>` tags in `galaxy-assistant.ts`. Both research and workflow intent paths receive it.

**Files → Chat pre-fill:** "Analyze with BioMate →" on the Files tab builds a message listing all uploaded files with sizes and navigates to `/?q=<encoded>`. `App.tsx` reads `?q=` on load and auto-sends it. Minor fix: added file sizes to the pre-fill message.

---

## 5. What's Still Needed

### Desktop
- **Code signing** — requires Apple Developer ID cert ($99/yr) + `xcrun notarytool` for macOS; EV cert for Windows SmartScreen. Without this, Gatekeeper blocks the app on macOS 13+.
- **GitHub Actions release pipeline** — `.github/workflows/desktop-release.yml` is staged locally but not pushed (needs `workflow` OAuth scope). Grant with: `gh auth login --scopes workflow`
- **Auto-updater pubkey** — `tauri.conf.json` has `"pubkey": ""`. Generate with `tauri signer generate` and fill in to enable in-app update checks.

### OpenRouter
- Run DB migrations on EC2 if not already done:
  ```bash
  psql $DATABASE_URL -f frontend/migrations/0019_user_llm_api_keys.sql
  psql $DATABASE_URL -f frontend/migrations/0020_project_members.sql
  ```
- Set `OPENROUTER_API_KEY` on EC2 if system-level default Chinese model is desired.
