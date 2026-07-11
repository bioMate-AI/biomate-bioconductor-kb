/**
 * desktop.ts — Tauri IPC bridge for BioMate Desktop.
 *
 * All functions gracefully degrade when running in a regular browser (not Tauri),
 * so the same React codebase works for both web and desktop without ifdefs.
 */

// Tauri v2 invoke is injected at runtime when running inside the shell.
// In the browser this import resolves to a no-op shim.
type TauriInvoke = (cmd: string, args?: Record<string, unknown>) => Promise<unknown>;

function getInvoke(): TauriInvoke | null {
  // @ts-ignore — Tauri injects this at runtime
  return (window as any).__TAURI__?.core?.invoke ?? null;
}

/** Returns true when running inside the Tauri desktop shell. */
export function isDesktop(): boolean {
  return getInvoke() !== null;
}

// ── Auth token ─────────────────────────────────────────────────────────────

/** Read the persisted auth token from the desktop's encrypted store. */
export async function desktopGetToken(): Promise<string | null> {
  const invoke = getInvoke();
  if (!invoke) return null;
  return (await invoke("get_token")) as string | null;
}

/** Persist the auth token in the desktop's encrypted store. */
export async function desktopSetToken(token: string): Promise<void> {
  const invoke = getInvoke();
  if (!invoke) return;
  await invoke("set_token", { token });
}

/** Remove the stored token (logout). */
export async function desktopDeleteToken(): Promise<void> {
  const invoke = getInvoke();
  if (!invoke) return;
  await invoke("delete_token");
}

// ── Server URL ─────────────────────────────────────────────────────────────

/** Get the configured server URL (default: https://dev-public.biomate.ai). */
export async function desktopGetServerUrl(): Promise<string> {
  const invoke = getInvoke();
  if (!invoke) return "";
  return (await invoke("get_server_url")) as string;
}

/** Set the server URL — "client" for cloud, "host" for local. */
export async function desktopSetServerUrl(url: string): Promise<void> {
  const invoke = getInvoke();
  if (!invoke) return;
  await invoke("set_server_url", { url });
}

// ── Local file picker ──────────────────────────────────────────────────────

export interface PickedFile {
  path: string;
  name: string;
  size: number;
}

/**
 * Open the native OS file picker. Returns an array of selected files,
 * or an empty array if the user cancelled.
 *
 * In the browser this returns [] — callers should fall back to a
 * standard <input type="file"> upload.
 */
export async function desktopPickFiles(): Promise<PickedFile[]> {
  const invoke = getInvoke();
  if (!invoke) return [];
  return (await invoke("pick_files")) as PickedFile[];
}

/**
 * Open a native folder picker for selecting an output directory.
 * Returns the selected path string or null if cancelled / not in desktop.
 */
export async function desktopPickOutputDirectory(): Promise<string | null> {
  const invoke = getInvoke();
  if (!invoke) return null;
  return (await invoke("pick_output_directory")) as string | null;
}

// ── App info ───────────────────────────────────────────────────────────────

export interface AppInfo {
  version: string;
  platform: "macos" | "windows" | "linux" | string;
  mode: "client" | "host" | "hybrid";
}

/** Returns version / platform / mode info, or null in the browser. */
export async function desktopGetAppInfo(): Promise<AppInfo | null> {
  const invoke = getInvoke();
  if (!invoke) return null;
  return (await invoke("get_app_info")) as AppInfo;
}

// ── OS notifications ───────────────────────────────────────────────────────

/**
 * Fire an OS-level desktop notification. No-op in the browser.
 * Requires `tauri-plugin-notification` to be registered (already done).
 */
export function desktopNotify(title: string, body: string): void {
  const invoke = getInvoke();
  if (!invoke) return;
  invoke("notify", { title, body }).catch(() => {/* best-effort */});
}

// ── Update check ───────────────────────────────────────────────────────────

export interface UpdateInfo {
  available: boolean;
  version?: string;
  currentVersion?: string;
  body?: string;
}

/**
 * Check for a new desktop app version via GitHub Releases.
 * Returns null in the browser. Returns { available: false } when already up to date.
 * The pubkey in tauri.conf.json must be filled in before this is functional.
 */
export async function desktopCheckForUpdate(): Promise<UpdateInfo | null> {
  const invoke = getInvoke();
  if (!invoke) return null;
  try {
    return (await invoke("check_for_update")) as UpdateInfo;
  } catch {
    return null;
  }
}

// ── Deep link handling ─────────────────────────────────────────────────────

/**
 * Returns the URL that launched the app on cold start (e.g. biomate://project/123),
 * or null if the app wasn't launched from a deep link or we're in a browser.
 */
export async function desktopGetPendingDeepLink(): Promise<string | null> {
  const invoke = getInvoke();
  if (!invoke) return null;
  try {
    return (await invoke("get_pending_deep_link")) as string | null;
  } catch {
    return null;
  }
}

/**
 * Subscribe to deep links received while the app is already open.
 * Returns an unsubscribe function — call it in the useEffect cleanup.
 */
export function desktopOnDeepLink(callback: (url: string) => void): () => void {
  if (!isDesktop()) return () => {};
  const listenPromise = (window as any).__TAURI__?.event?.listen(
    'deep-link',
    (event: any) => callback(event.payload as string)
  );
  return () => {
    if (listenPromise) listenPromise.then((f: () => void) => f());
  };
}

// ── Convenience: upload picked files via the BioMate API ──────────────────

/**
 * Pick files via the native picker, then upload each to
 * POST /api/projects/:projectId/files/upload using a ReadableStream
 * sourced from the local path.
 *
 * Falls back to a no-op in the browser (use the standard upload UI instead).
 */
export async function desktopPickAndUpload(
  projectId: string,
  onProgress?: (file: string, done: boolean) => void
): Promise<string[]> {
  const files = await desktopPickFiles();
  if (!files.length) return [];

  const serverUrl = (await desktopGetServerUrl()) || "";
  const token = (await desktopGetToken()) || "";
  const uploaded: string[] = [];

  for (const f of files) {
    onProgress?.(f.name, false);
    try {
      // Read file via fetch with the file:// protocol Tauri allows
      const blob = await fetch(`asset://localhost/${encodeURIComponent(f.path)}`).then(r => r.blob());
      const form = new FormData();
      form.append("file", blob, f.name);

      const res = await fetch(`${serverUrl}/api/projects/${projectId}/files/upload`, {
        method: "POST",
        headers: token ? { Cookie: `biomate_token=${token}` } : {},
        body: form,
        credentials: "include",
      });
      if (res.ok) {
        uploaded.push(f.name);
        onProgress?.(f.name, true);
      }
    } catch {
      // Non-fatal — skip this file, continue with others
    }
  }
  return uploaded;
}
