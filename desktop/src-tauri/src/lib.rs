use tauri::AppHandle;
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_store::StoreExt;
use serde::{Deserialize, Serialize};

const STORE_FILE: &str = "biomate.bin";
const TOKEN_KEY: &str = "auth_token";
const SERVER_KEY: &str = "server_url";
const DEFAULT_SERVER: &str = "https://dev-public.biomate.ai";

// ── Auth token (stored in encrypted plugin-store) ──────────────────────────

#[tauri::command]
fn get_token(app: AppHandle) -> Option<String> {
    let store = app.store(STORE_FILE).ok()?;
    store.get(TOKEN_KEY)
        .and_then(|v| v.as_str().map(|s| s.to_string()))
}

#[tauri::command]
fn set_token(app: AppHandle, token: String) -> Result<(), String> {
    let store = app.store(STORE_FILE).map_err(|e| e.to_string())?;
    store.set(TOKEN_KEY, serde_json::json!(token));
    store.save().map_err(|e| e.to_string())
}

#[tauri::command]
fn delete_token(app: AppHandle) -> Result<(), String> {
    let store = app.store(STORE_FILE).map_err(|e| e.to_string())?;
    store.delete(TOKEN_KEY);
    store.save().map_err(|e| e.to_string())
}

// ── Server URL (client mode = cloud, host mode = localhost) ────────────────

#[tauri::command]
fn get_server_url(app: AppHandle) -> String {
    let store = app.store(STORE_FILE).ok();
    store
        .and_then(|s| s.get(SERVER_KEY))
        .and_then(|v| v.as_str().map(|s| s.to_string()))
        .unwrap_or_else(|| DEFAULT_SERVER.to_string())
}

#[tauri::command]
fn set_server_url(app: AppHandle, url: String) -> Result<(), String> {
    let store = app.store(STORE_FILE).map_err(|e| e.to_string())?;
    store.set(SERVER_KEY, serde_json::json!(url));
    store.save().map_err(|e| e.to_string())
}

// ── Local file picker ──────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
pub struct PickedFile {
    pub path: String,
    pub name: String,
    pub size: u64,
}

#[tauri::command]
async fn pick_files(app: AppHandle) -> Result<Vec<PickedFile>, String> {
    let files = app
        .dialog()
        .file()
        .add_filter("All supported formats", &[
            "fastq", "fastq.gz", "fq", "fq.gz",
            "fasta", "fa", "fna", "ffn", "faa", "frn",
            "bam", "sam", "cram",
            "vcf", "vcf.gz", "bcf",
            "bed", "gtf", "gff", "gff3",
            "csv", "tsv", "txt",
            "sdf", "mol", "mol2", "pdb",
            "mrc", "mrcs", "tiff", "tif",
            "h5", "hdf5", "loom",
            "pdf", "docx",
        ])
        .blocking_pick_files();

    match files {
        Some(paths) => {
            let mut picked = Vec::new();
            for path in paths {
                let p = path.into_path().map_err(|e| e.to_string())?;
                let meta = std::fs::metadata(&p).map_err(|e| e.to_string())?;
                let name = p.file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or("unknown")
                    .to_string();
                picked.push(PickedFile {
                    path: p.to_string_lossy().to_string(),
                    name,
                    size: meta.len(),
                });
            }
            Ok(picked)
        }
        None => Ok(vec![]), // user cancelled
    }
}

#[tauri::command]
async fn pick_output_directory(app: AppHandle) -> Result<Option<String>, String> {
    let dir = app.dialog().file().blocking_pick_folder();
    Ok(dir.and_then(|p| p.into_path().ok())
         .map(|p| p.to_string_lossy().to_string()))
}

// ── Update check ───────────────────────────────────────────────────────────

#[tauri::command]
async fn check_for_update(app: tauri::AppHandle) -> Result<serde_json::Value, String> {
    use tauri_plugin_updater::UpdaterExt;

    match app.updater() {
        Ok(updater) => {
            match updater.check().await {
                Ok(Some(update)) => Ok(serde_json::json!({
                    "available": true,
                    "version": update.version,
                    "currentVersion": update.current_version,
                    "body": update.body
                })),
                Ok(None) => Ok(serde_json::json!({ "available": false })),
                Err(e) => Err(e.to_string()),
            }
        }
        Err(e) => Err(e.to_string()),
    }
}

// ── Deep link (cold-start: get current URL; warm: event emitted via on_open_urls) ──

#[tauri::command]
fn get_pending_deep_link(app: tauri::AppHandle) -> Option<String> {
    use tauri_plugin_deep_link::DeepLinkExt;
    app.deep_link()
        .get_current()
        .ok()
        .flatten()
        .and_then(|urls| urls.into_iter().next())
        .map(|u| u.to_string())
}

// ── App info ───────────────────────────────────────────────────────────────

#[derive(Serialize)]
struct AppInfo {
    version: String,
    platform: String,
    mode: String,
}

#[tauri::command]
fn get_app_info() -> AppInfo {
    AppInfo {
        version: env!("CARGO_PKG_VERSION").to_string(),
        platform: std::env::consts::OS.to_string(),
        mode: "client".to_string(), // Phase 1: always client mode
    }
}

// ── Entry point ────────────────────────────────────────────────────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            use tauri_plugin_deep_link::DeepLinkExt;
            let handle = app.handle().clone();
            app.deep_link().on_open_urls(move |event| {
                if let Some(url) = event.urls().first() {
                    if let Some(window) = handle.get_webview_window("main") {
                        let _ = window.emit("deep-link", url.to_string());
                    }
                }
            });
            Ok(())
        })
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_deep_link::init())
        .invoke_handler(tauri::generate_handler![
            get_token,
            set_token,
            delete_token,
            get_server_url,
            set_server_url,
            pick_files,
            pick_output_directory,
            get_app_info,
            check_for_update,
            get_pending_deep_link,
        ])
        .run(tauri::generate_context!())
        .expect("error while running BioMate Desktop");
}
