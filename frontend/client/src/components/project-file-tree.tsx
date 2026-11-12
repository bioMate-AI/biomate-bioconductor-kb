/**
 * ProjectFileTree — VS Code / Jupyter style file browser for a project.
 *
 * Displays the project's uploaded input files and run output files fetched
 * from /api/projects/:id/files. Supports:
 *   - Expand / collapse folder nodes (inputs/, outputs/<runId>/)
 *   - Single-click → copy S3 path to clipboard
 *   - Download button → presigned URL
 *   - Upload via drag-drop or the "Add ▾ Files / Folder" picker. A folder (picked or
 *     dropped, walked recursively) uploads file-by-file with its folder-relative path,
 *     which the server keeps in the stored name, so the tree shows the folders. One
 *     failed file never aborts the batch; failures are listed per file, localized.
 *   - Delete uploaded files (source='upload' only)
 *   - Rename / move a file (the new name may include folders) and rename / move an input
 *     folder, inline: Enter saves, Esc cancels, a clash (409) is shown on the row. Only the
 *     stored name changes; the bytes, versions and lineage stay with the file.
 */
import { useState, useEffect, useRef, useCallback, type CSSProperties } from "react";
import { isDesktop, desktopPickAndUpload, desktopSaveFile } from "@/lib/desktop";
import {
  Search,
  Folder,
  FolderOpen,
  File,
  FileText,
  Download,
  Trash2,
  Link2,
  Upload,
  RefreshCw,
  ChevronRight,
  ChevronDown,
  Copy,
  Check,
  Plus,
  Image,
  Database,
  Code2,
  FileArchive,
  Eye,
  EyeOff,
  FolderUp,
  FilePlus,
  Pencil,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { t, locale } from "@/lib/i18n";
import { effectiveQuality } from "@/components/datasets/dataset-view-model";
import { filesFromDataTransfer, relativePathOf } from "@/lib/folder-drop";

export interface ProjectFile {
  id: string;
  name: string;
  s3_key: string;
  size: number;
  content_type: string;
  source: "upload" | "run_output" | string;
  run_id: string | null;
  workflow_name: string | null;
  step_name: string | null;
  input_context: Record<string, unknown> | null;
  content_hash?: string | null;
  created_at: string;
}

interface FolderNode {
  type: "folder";
  name: string;
  path: string;
  children: TreeNode[];
}
interface FileNode {
  type: "file";
  name: string;
  file: ProjectFile;
}
type TreeNode = FolderNode | FileNode;

/** Number of files below a folder (recursively) — the count shown on its row. */
function countFiles(node: FolderNode): number {
  return node.children.reduce((n, c) => n + (c.type === "file" ? 1 : countFiles(c)), 0);
}

/** Place an input file under its folder path ("run1/fastq/S1.fq" → inputs/run1/fastq). */
function insertInput(root: FolderNode, f: ProjectFile): void {
  const parts = f.name.split("/").filter(Boolean);
  const leaf = parts.pop() ?? f.name;
  let node = root;
  for (const part of parts) {
    const path = `${node.path}/${part}`;
    let next = node.children.find((c): c is FolderNode => c.type === "folder" && c.path === path);
    if (!next) {
      next = { type: "folder", name: part, path, children: [] };
      node.children.push(next);
    }
    node = next;
  }
  node.children.push({ type: "file", name: leaf, file: f });
}

/** Folders before files at every level; files keep their (newest-first) order. */
function sortFoldersFirst(node: FolderNode): void {
  node.children.sort((x, y) => (x.type === y.type ? 0 : x.type === "folder" ? -1 : 1));
  node.children.forEach((c) => { if (c.type === "folder") sortFoldersFirst(c); });
}

export function buildTree(files: ProjectFile[]): TreeNode[] {
  // The root's PATH stays "inputs" (test ids, expand state, rename paths); its NAME is localized.
  const inputs: FolderNode = { type: "folder", name: t("file_tree.inputs_root"), path: "inputs", children: [] };
  const outputsByRun: Record<string, FileNode[]> = {};
  // Files BioMate generated in this project's chats (run_code reports, tables, plots) are results.
  const analysis: FolderNode = { type: "folder", name: t("file_tree.analysis_outputs"), path: "outputs/analysis", children: [] };

  for (const f of files) {
    if (f.source === "run_code") { analysis.children.push({ type: "file", name: f.name, file: f }); continue; }
    // Only run outputs are "results"; everything else the user ingested
    // (upload, pasted URL, connector pull) is an input, regardless of source.
    if (f.source !== "run_output") {
      insertInput(inputs, f);
    } else {
      const run = f.run_id || "unknown";
      if (!outputsByRun[run]) outputsByRun[run] = [];
      outputsByRun[run].push({ type: "file", name: f.name, file: f });
    }
  }
  sortFoldersFirst(inputs);

  const root: TreeNode[] = [];
  if (inputs.children.length > 0) root.push(inputs);
  if (analysis.children.length > 0) root.push(analysis);
  for (const [runId, nodes] of Object.entries(outputsByRun)) {
    const firstFile = nodes[0]?.file;
    const wfName = firstFile?.workflow_name ?? t('workflow.labels.workflow');
    // Format: "nf-core/rnaseq · Jul 11 14:23" — lets users distinguish multiple runs
    const ts = firstFile?.created_at
      ? new Date(firstFile.created_at).toLocaleString(locale === "zh" ? "zh-CN" : "en-US", { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })
      : runId.slice(0, 8);
    const label = `${wfName} · ${ts}`;
    root.push({
      type: "folder",
      name: label,
      path: `outputs/${runId}`,
      children: nodes,
    });
  }
  return root;
}

/** What the server sends back with a refused upload / import (optional stable code; name clashes). */
export interface UploadErrorBody {
  error?: string;
  code?: string;
  conflicts?: Array<{ name: string; existing: string }>;
}

/** Localized reason for a failed upload response. A 409 is a name clash with an existing file or
 *  folder (the server's `name_conflict`): it names the existing entry, never "server error". */
export function uploadErrorReason(status: number, body?: UploadErrorBody | null): string {
  if (status === 409 || body?.code === "name_conflict") {
    const existing = body?.conflicts?.find((c) => typeof c?.existing === "string" && c.existing)?.existing;
    return existing ? t("data_hub.tree_err_name_conflict_with", { existing }) : t("data_hub.tree_err_name_conflict");
  }
  if (status === 413) return t("data_hub.tree_err_too_large");
  if (status === 401 || status === 403 || status === 404) return t("data_hub.tree_err_forbidden");
  return t("data_hub.tree_err_server", { status });
}

/** What the server sends back with a refused rename (error text; optional stable code; clashes). */
export interface RenameErrorBody {
  error?: string
  /** Stable reason code, when the server sends one (preferred over matching the text). */
  code?: string
  conflicts?: Array<{ name: string; existing: string }>
}

/**
 * Stable reason for a refused rename, in the server's vocabulary (project-file-paths.ts
 * NameErrorCode: run_output, same_name, into_itself, control_chars, dot_segments, empty,
 * segment_too_long, too_deep, limit_after_move, name_conflict). The server's `code` wins;
 * a server that sends none is read from its (English, developer-facing) error text, which
 * names one rule per refusal.
 */
export function renameErrorCode(status: number, body?: RenameErrorBody | null): string {
  if (body?.code) return body.code
  if (status === 409) return "name_conflict"
  if (status === 401) return "signed_out"
  if (status === 403 || status === 404) return "gone"
  if (status !== 400) return "server"
  const e = String(body?.error ?? "")
  if (/run output/i.test(e)) return "run_output"
  if (/already has that name/i.test(e)) return "same_name"
  if (/into itself/i.test(e)) return "into_itself"
  if (/control char/i.test(e)) return "control_chars"
  if (/\.\./.test(e)) return "dot_segments"
  if (/is empty/i.test(e)) return "empty"
  if (/limited to \d+ characters/i.test(e)) return "segment_too_long"
  if (/nested at most/i.test(e)) return "too_deep"
  if (/depth or name length/i.test(e)) return "limit_after_move"
  return "invalid"
}

const RENAME_400_KEYS: Record<string, string> = {
  run_output: "file_tree.rename_err_run_output",
  same_name: "file_tree.rename_err_same_name",
  into_itself: "file_tree.rename_err_into_itself",
  control_chars: "file_tree.rename_err_control_chars",
  dot_segments: "file_tree.rename_err_dot_segment",
  empty: "file_tree.rename_err_empty",
  segment_too_long: "file_tree.rename_err_too_long",
  too_deep: "file_tree.rename_err_too_deep",
  limit_after_move: "file_tree.rename_err_limits",
}

/** Localized reason for a failed rename / move response — one message per server reason. */
export function renameErrorReason(status: number, body?: RenameErrorBody | null): string {
  const code = renameErrorCode(status, body)
  if (code === "name_conflict") {
    const existing = body?.conflicts?.[0]?.existing
    return existing ? t("file_tree.rename_conflict_with", { existing }) : t("file_tree.rename_conflict")
  }
  if (code === "signed_out") return t("file_tree.rename_err_signed_out")
  if (code === "gone") return t("file_tree.rename_err_gone")
  if (code === "server") return t("file_tree.rename_err_server", { status })
  const key = RENAME_400_KEYS[code]
  return key ? t(key) : t("file_tree.rename_invalid")
}

/** "inputs/a/b" → ["inputs", "inputs/a", "inputs/a/b"]: folders to keep open after a move. */
function folderPathsOf(name: string, includeLeaf: boolean): string[] {
  const parts = name.split("/").filter(Boolean);
  if (!includeLeaf) parts.pop();
  const out = ["inputs"];
  let path = "inputs";
  for (const part of parts) { path = `${path}/${part}`; out.push(path); }
  return out;
}

/**
 * Inline name editor shared by file and folder rows: Enter saves, Esc cancels, the server's
 * refusal (e.g. a clash) stays on the row until the user edits or cancels.
 */
function InlineRename({
  initial, onSave, onCancel, testid, depth,
}: {
  initial: string;
  /** Resolves to a localized error, or null on success. */
  onSave: (value: string) => Promise<string | null>;
  onCancel: () => void;
  testid: string;
  depth: number;
}) {
  const [value, setValue] = useState(initial);
  const [err, setErr] = useState<string | null>(null);
  // A concrete example of moving: "data/<this name>" puts it into a folder named data.
  const base = initial.split("/").filter(Boolean).pop() || initial;
  const hint = t("file_tree.rename_hint", { example: `data/${base}`, folder: "data" });
  const [saving, setSaving] = useState(false);
  // The editor (and its hint / error below the input) must be fully visible inside the
  // tree's scroll box — a rename on the last row otherwise leaves the hint cut off.
  const boxRef = useRef<HTMLDivElement>(null);
  useEffect(() => { boxRef.current?.scrollIntoView?.({ block: "nearest" }); }, [err]);
  const save = async () => {
    const v = value.trim();
    if (!v || saving) return;
    if (v === initial) { onCancel(); return; }
    setSaving(true);
    const e = await onSave(v);
    setSaving(false);
    if (e) setErr(e);
  };
  return (
    <div ref={boxRef} className="pr-2 py-1 space-y-0.5" style={{ paddingLeft: treeIndent(depth) }} data-testid={`${testid}-editor`}>
      <input
        value={value}
        autoFocus
        onFocus={(e) => e.currentTarget.select()}
        onChange={(e) => { setValue(e.target.value); setErr(null); }}
        onKeyDown={(e) => {
          if (e.key === "Enter") { e.preventDefault(); void save(); }
          else if (e.key === "Escape") { e.preventDefault(); onCancel(); }
        }}
        disabled={saving}
        aria-label={t("file_tree.rename_label")}
        title={hint}
        className={cn("w-full h-6 px-1.5 text-xs rounded border bg-background font-mono", err && "border-destructive")}
        data-testid={`${testid}-input`}
      />
      {err ? (
        <p className="text-fs-xs text-destructive [overflow-wrap:anywhere]" role="alert" data-testid={`${testid}-error`}>{err}</p>
      ) : (
        <p className="text-fs-xs text-muted-foreground [overflow-wrap:anywhere]" data-testid={`${testid}-hint`}>{hint}</p>
      )}
    </div>
  );
}

/**
 * Row layout contract (U10). The tree is ~280 px wide, so every pixel of indent and every
 * hidden control is taken from the name:
 *   - indent grows 12 px per level and stops growing after INDENT_MAX_DEPTH levels;
 *   - the name is the only flexible item and never shrinks below NAME_MIN_PX;
 *   - hover/focus actions are an absolutely positioned overlay, so while hidden they take
 *     no layout width (they used to reserve ~100 px of invisible buttons on every row).
 */
const INDENT_BASE_PX = 8;
const INDENT_STEP_PX = 12;
const INDENT_MAX_DEPTH = 8;
export const NAME_MIN_PX = 72;
export function treeIndent(depth: number): number {
  return INDENT_BASE_PX + Math.min(Math.max(depth, 0), INDENT_MAX_DEPTH) * INDENT_STEP_PX;
}
const NAME_STYLE: CSSProperties = { flex: "1 1 auto", minWidth: NAME_MIN_PX };
/** Hidden until the row is hovered or a control inside it has keyboard focus; never takes width. */
const ACTIONS_CLASS =
  "absolute inset-y-0 right-1 flex items-center gap-0.5 pl-1 rounded-r bg-muted opacity-0 pointer-events-none " +
  "group-hover:opacity-100 group-hover:pointer-events-auto group-focus-within:opacity-100 group-focus-within:pointer-events-auto";
const ACTIONS_STYLE: CSSProperties = { position: "absolute" };

const MAX_UPLOAD_BYTES = 500 * 1024 * 1024; // server multer limit (project-routes.ts)

function fileIcon(name: string, contentType: string) {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  if (["png", "jpg", "jpeg", "gif", "svg", "webp"].includes(ext)) return Image;
  if (["csv", "tsv", "xlsx", "parquet"].includes(ext)) return Database;
  if (["nf", "py", "r", "sh", "ts", "js", "json", "yaml", "yml"].includes(ext)) return Code2;
  if (["gz", "zip", "tar", "bz2", "zst"].includes(ext)) return FileArchive;
  if (["txt", "md", "log", "fastq", "fasta", "vcf", "bed", "gtf", "gff"].includes(ext)) return FileText;
  return File;
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`;
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

const PREVIEW_EXTS = new Set(["csv","tsv","txt","log","md","png","jpg","jpeg","gif","webp","svg"]);

function canPreview(file: ProjectFile): boolean {
  const ext = file.name.split(".").pop()?.toLowerCase() ?? "";
  return PREVIEW_EXTS.has(ext) && file.size < 1024 * 1024; // < 1 MB
}

// Extensions the perception profiler (backend data_perception.py) can read.
const PROFILABLE_EXTS = new Set([
  "csv","tsv","txt","tab","vcf","fastq","fq","gz",
]);

function isProfilable(file: ProjectFile): boolean {
  const parts = file.name.toLowerCase().split(".");
  // handle .fastq.gz etc — check the last two extension tokens.
  const last = parts[parts.length - 1] ?? "";
  const prev = parts.length > 2 ? parts[parts.length - 2] : "";
  return PROFILABLE_EXTS.has(last) || PROFILABLE_EXTS.has(prev);
}

// Map a perception quality verdict to a dot colour. "unknown" is honest grey —
// no profile has been computed, NOT a claim of good.
const QUALITY_DOT: Record<string, string> = {
  good: "bg-emerald-500",
  watch: "bg-amber-500",
  blocked: "bg-red-500",
  // Identified but not analysed: neutral, never a warning colour.
  unassessed: "bg-muted-foreground/50",
  unknown: "bg-muted-foreground/40",
};

/**
 * QualityDot — a per-row ingest-quality indicator. Lazily profiles the file via
 * POST /api/perception/profile the first time the row is rendered, but only for
 * file types the profiler can read. Everything else stays honest grey/unknown.
 */
function QualityDot({ file }: { file: ProjectFile }) {
  const [quality, setQuality] = useState<string>("unknown");
  const profilable = isProfilable(file);

  useEffect(() => {
    if (!profilable) return;
    let cancelled = false;
    fetch("/api/perception/profile", {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ datasetRef: file.s3_key, name: file.name }),
    })
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => {
        // The same verdict the dataset object shows: an older profile's "watch" whose only
        // reasons are "not analysed" findings is "unassessed" (grey), not a warning.
        if (!cancelled && d && typeof d.quality === "string") setQuality(effectiveQuality(d));
      })
      .catch(() => { /* stay unknown */ });
    return () => { cancelled = true; };
  }, [file.s3_key, file.name, profilable]);

  const cls = QUALITY_DOT[quality] ?? QUALITY_DOT.unknown;
  const title = profilable
    ? t('file_tree.quality', { quality: quality === 'unknown' ? '—' : t(`dataset_obj.quality_${quality}`) })
    : t('file_tree.quality_unprofiled');
  return (
    <span
      className={cn("h-1.5 w-1.5 rounded-full shrink-0", cls)}
      title={title}
      data-testid={`file-quality-${file.id}`}
      data-quality={quality}
    />
  );
}

const PREVIEW_LINES = 20;
const PREVIEW_TABLE_ROWS = 6;
/** The inline preview is a bounded window, never part of the row flow's width. */
const PREVIEW_BOX_STYLE: CSSProperties = { maxHeight: 160, overflow: "auto" };

/**
 * Bounded quick look under a row — only where there is no dataset object view to open
 * (project page Files tab). Fixed max height, scrolls both ways, never wraps: a file's
 * text must not reflow down the tree (the data hub opens the full object instead).
 */
function FilePreview({ url, name, fileId }: { url: string; name: string; fileId: string }) {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  const isImage = ["png","jpg","jpeg","gif","webp","svg"].includes(ext);
  const [content, setContent] = useState<string | null>(null);

  useEffect(() => {
    if (isImage) return;
    fetch(url).then(r => r.text()).then(txt => setContent(txt)).catch(() => setContent(t("data_hub.tree_preview_failed")));
  }, [url, isImage]);

  const boxClass = "mx-2 mt-0.5 mb-1 rounded border bg-muted/30";
  const testid = `file-preview-${fileId}`;
  if (isImage) {
    return (
      <div className={boxClass} style={PREVIEW_BOX_STYLE} data-testid={testid}>
        <img src={url} alt={name} className="max-w-full max-h-36 m-1 rounded" />
      </div>
    );
  }
  if (content === null) return <div className="mx-2 mt-0.5 mb-1 text-xs text-muted-foreground" data-testid={testid}>{t("data_hub.tree_preview_loading")}</div>;
  const isTable = ext === "csv" || ext === "tsv";
  const lines = content.split("\n").slice(0, isTable ? PREVIEW_TABLE_ROWS : PREVIEW_LINES);
  if (isTable && lines.length > 0) {
    const sep = ext === "tsv" ? "\t" : ",";
    const rows = lines.map(l => l.split(sep));
    return (
      <div className={boxClass} style={PREVIEW_BOX_STYLE} data-testid={testid}>
        <table className="text-xs border-collapse">
          <tbody>
            {rows.map((row, i) => (
              <tr key={i} className={i === 0 ? "font-semibold bg-muted/40" : ""}>
                {row.map((cell, j) => (
                  <td key={j} className="border border-border px-1.5 py-0.5 whitespace-nowrap">{cell}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  }
  return (
    <div className={boxClass} style={PREVIEW_BOX_STYLE} data-testid={testid}>
      <pre className="m-0 p-2 text-xs font-mono" style={{ whiteSpace: "pre" }}>{lines.join("\n")}</pre>
    </div>
  );
}

function FileRow({
  file,
  projectId,
  onDelete,
  onDownload,
  copiedId,
  onCopy,
  onOpenDataset,
  onRename,
  canEdit = true,
  label,
  depth = 1,
}: {
  file: ProjectFile;
  projectId: string;
  onDelete: (id: string) => void;
  /** Rename / move to a new full name; resolves to a localized error or null. */
  onRename?: (file: ProjectFile, name: string) => Promise<string | null>;
  onDownload: (id: string) => void;
  copiedId: string | null;
  onCopy: (id: string, key: string) => void;
  /** Open this file as a first-class DatasetObject (data hub). */
  onOpenDataset?: (file: ProjectFile) => void;
  canEdit?: boolean;
  /** Text shown for the row (the basename inside a folder); defaults to file.name. */
  label?: string;
  /** Nesting depth (1 = directly under a top-level folder). */
  depth?: number;
}) {
  const Icon = fileIcon(file.name, file.content_type);
  const shown = label ?? file.name;
  const isCopied = copiedId === file.id;
  const [previewOpen, setPreviewOpen] = useState(false);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  // Where the file opens as a dataset object, that IS the preview — no second, cramped copy
  // of its contents inside the tree. The quick look stays only where there is no object view.
  const showPreview = !onOpenDataset && canPreview(file);
  const [renaming, setRenaming] = useState(false);
  // Run outputs keep the name their run gave them (the server refuses those renames too).
  const canRename = Boolean(onRename) && canEdit && file.source !== "run_output";

  const handleTogglePreview = async () => {
    if (!previewOpen && !previewUrl) {
      try {
        const res = await fetch(`/api/projects/${projectId}/files/${file.id}/url`, { credentials: "include" });
        if (res.ok) { const d = await res.json(); setPreviewUrl(d.url); }
      } catch { /* ignore */ }
    }
    setPreviewOpen(v => !v);
  };

  if (renaming && onRename) {
    return (
      <InlineRename
        initial={file.name}
        depth={depth}
        testid={`file-rename-${file.id}`}
        onCancel={() => setRenaming(false)}
        onSave={async (name) => {
          const e = await onRename(file, name);
          if (!e) setRenaming(false);
          return e;
        }}
      />
    );
  }

  const nameClass = "truncate text-left text-xs text-foreground";
  return (
    <div>
      <div
        className="group relative flex items-center gap-1.5 pr-2 py-1 rounded hover:bg-muted text-sm cursor-default"
        style={{ paddingLeft: treeIndent(depth) }}
        data-testid={`file-row-${file.id}`}
      >
        <Icon className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
        <QualityDot file={file} />
        {/* The full stored name (with its folders) is the name's own tooltip. */}
        {onOpenDataset ? (
          <button
            type="button"
            onClick={() => onOpenDataset(file)}
            className={cn(nameClass, "hover:underline cursor-pointer")}
            style={NAME_STYLE}
            title={file.name}
            aria-label={`${t("file_tree.open_dataset")}: ${file.name}`}
            data-testid={`file-open-${file.id}`}
          >
            {shown}
          </button>
        ) : (
          <span className={nameClass} style={NAME_STYLE} title={file.name} data-testid={`file-name-${file.id}`}>{shown}</span>
        )}
        {file.step_name && (
          <span className="min-w-0 max-w-[30%] truncate text-fs-xs px-1 py-0.5 rounded bg-blue-100 text-blue-700 font-mono" title={t("data_hub.tree_produced_by", { step: file.step_name })}>
            {file.step_name}
          </span>
        )}
        <span className="text-xs text-muted-foreground shrink-0 tabular-nums">{formatBytes(file.size)}</span>
        <div className={ACTIONS_CLASS} style={ACTIONS_STYLE} data-testid={`file-actions-${file.id}`}>
          {showPreview && (
            <button
              type="button"
              title={previewOpen ? t('file_tree.hide_preview') : t('file_tree.preview')}
              aria-label={previewOpen ? t('file_tree.hide_preview') : t('file_tree.preview')}
              aria-expanded={previewOpen}
              onClick={handleTogglePreview}
              className="p-0.5 rounded hover:bg-background"
              data-testid={`file-preview-toggle-${file.id}`}
            >
              {previewOpen ? <EyeOff className="h-3 w-3 text-muted-foreground" /> : <Eye className="h-3 w-3 text-muted-foreground" />}
            </button>
          )}
          <button
            type="button"
            title={t('file_tree.copy_s3')}
            aria-label={t('file_tree.copy_s3')}
            onClick={() => onCopy(file.id, file.s3_key)}
            className="p-0.5 rounded hover:bg-background"
            data-testid={`file-copy-${file.id}`}
          >
            {isCopied ? <Check className="h-3 w-3 text-green-600" /> : <Copy className="h-3 w-3 text-muted-foreground" />}
          </button>
          <button
            type="button"
            title={t('actions.download')}
            aria-label={t('actions.download')}
            onClick={() => onDownload(file.id)}
            className="p-0.5 rounded hover:bg-background"
            data-testid={`file-download-${file.id}`}
          >
            <Download className="h-3 w-3 text-muted-foreground" />
          </button>
          {canRename && (
            <button
              type="button"
              title={t("file_tree.rename")}
              aria-label={t("file_tree.rename")}
              onClick={() => setRenaming(true)}
              className="p-0.5 rounded hover:bg-background"
              data-testid={`file-rename-${file.id}`}
            >
              <Pencil className="h-3 w-3 text-muted-foreground" />
            </button>
          )}
          {file.source === "upload" && canEdit && (
            <button
              type="button"
              title={t('actions.delete')}
              aria-label={t('actions.delete')}
              onClick={() => onDelete(file.id)}
              className="p-0.5 rounded hover:bg-red-50 hover:text-red-600"
              data-testid={`file-delete-${file.id}`}
            >
              <Trash2 className="h-3 w-3" />
            </button>
          )}
        </div>
      </div>
      {previewOpen && previewUrl && <FilePreview url={previewUrl} name={file.name} fileId={file.id} />}
      {previewOpen && file.input_context && (typeof file.input_context.intent === 'string' || Array.isArray(file.input_context.inputFiles)) && (
        <div className="mx-2 mt-0.5 mb-2 rounded border border-border bg-muted/30 p-2 text-xs space-y-1.5 [overflow-wrap:anywhere]">
          {typeof file.input_context.intent === 'string' && (
            <div className="italic text-foreground/80">"{file.input_context.intent}"</div>
          )}
          {Array.isArray(file.input_context.inputFiles) && (file.input_context.inputFiles as string[]).length > 0 && (
            <div><span className="text-muted-foreground">{t("data_hub.tree_input_files")}</span>{(file.input_context.inputFiles as string[]).join(", ")}</div>
          )}
        </div>
      )}
    </div>
  );
}

function FolderRow({
  node,
  expanded,
  onToggle,
  onRename,
  depth = 0,
  selected = false,
}: {
  node: FolderNode;
  expanded: boolean;
  onToggle: () => void;
  /** This folder is the one open in the folder view. */
  selected?: boolean;
  /** Rename / move this input folder (relative path, without "inputs/"); resolves to a localized error or null. */
  onRename?: (from: string, to: string) => Promise<string | null>;
  depth?: number;
}) {
  const FIcon = expanded ? FolderOpen : Folder;
  const CIcon = expanded ? ChevronDown : ChevronRight;
  const [renaming, setRenaming] = useState(false);
  // Only folders rebuilt from input file names can be renamed (not "inputs" itself, not run groups).
  const rel = node.path.startsWith("inputs/") ? node.path.slice("inputs/".length) : null;
  if (renaming && onRename && rel) {
    return (
      <InlineRename
        initial={rel}
        depth={depth}
        testid={`folder-rename-${node.path}`}
        onCancel={() => setRenaming(false)}
        onSave={async (to) => {
          const e = await onRename(rel, to);
          if (!e) setRenaming(false);
          return e;
        }}
      />
    );
  }
  const n = countFiles(node);
  return (
    <div className={cn("group relative flex items-center rounded hover:bg-muted", selected && "bg-muted/60")}>
      <button
        type="button"
        onClick={onToggle}
        className="flex items-center gap-1.5 flex-1 min-w-0 pr-2 py-1 text-left"
        style={{ paddingLeft: treeIndent(depth) }}
        data-testid={`folder-${node.path}`}
        aria-expanded={expanded}
        aria-current={selected ? "true" : undefined}
      >
        <CIcon className="h-3 w-3 text-muted-foreground shrink-0" />
        <FIcon className="h-3.5 w-3.5 text-yellow-500 shrink-0" />
        <span className="truncate text-xs font-medium text-foreground" style={NAME_STYLE} title={rel ?? node.name} data-testid={`folder-name-${node.path}`}>{node.name}</span>
        <span className="shrink-0 text-xs text-muted-foreground tabular-nums" title={t("data_hub.tree_folder_count", { n })}>{n}</span>
      </button>
      {onRename && rel && (
        <div className={ACTIONS_CLASS} style={ACTIONS_STYLE} data-testid={`folder-actions-${node.path}`}>
          <button
            type="button"
            title={t("file_tree.rename_folder")}
            aria-label={t("file_tree.rename_folder")}
            onClick={() => setRenaming(true)}
            className="p-0.5 rounded hover:bg-background"
            data-testid={`folder-rename-${node.path}`}
          >
            <Pencil className="h-3 w-3 text-muted-foreground" />
          </button>
        </div>
      )}
    </div>
  );
}

export interface ProjectFileTreeProps {
  projectId: string;
  /** Called with the S3 key when the user picks a file to use as a workflow input */
  onPickFile?: (s3Key: string, fileName: string) => void;
  /** Called whenever the file list changes (load, upload, delete) */
  onFilesChanged?: (files: { name: string; size?: number }[]) => void;
  /** Open a file row as a first-class DatasetObject (data hub). When set, the
   *  file name becomes a button that opens the dataset instead of only the
   *  inline preview. */
  onOpenDataset?: (file: ProjectFile) => void;
  /** When false, hide upload/delete controls (read-only viewers). Default true. */
  canEdit?: boolean;
  /** Deep-link target: when this file id is present in the loaded list, open it
   *  as an object once (used by `/files?file=<id>` links from other surfaces). */
  selectFileId?: string;
  /** Open an INPUT folder as one object (data hub folder view). Called with the folder path
   *  relative to the inputs root ("" = inputs itself, "pairs", "run1/fastq") on every click of
   *  its row (the click also expands/collapses it). Run-output groups are not folders. */
  onOpenFolder?: (path: string) => void;
  /** The input folder currently open in the folder view (same relative path). */
  selectedFolder?: string | null;
}

export function ProjectFileTree({ projectId, onPickFile, onFilesChanged, onOpenDataset, canEdit = true, selectFileId, onOpenFolder, selectedFolder = null }: ProjectFileTreeProps) {
  const [files, setFiles] = useState<ProjectFile[]>([]);
  // Fire onOpenDataset at most once per deep-link target, so a `?file=<id>`
  // link (from a composer/output/report chip) opens the same object without
  // re-opening it on every re-render.
  const openedSelectRef = useRef<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set(["inputs"]));
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  // Batch upload progress + per-file outcome (localized; never a raw fetch error).
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [uploadReport, setUploadReport] = useState<{
    ok: number;
    deduped: number;
    failures: { name: string; reason: string }[];
  } | null>(null);
  const folderInputRef = useRef<HTMLInputElement>(null);
  const [urlOpen, setUrlOpen] = useState(false);
  const [urlVal, setUrlVal] = useState("");
  const [importingUrl, setImportingUrl] = useState(false);
  const [dragOver, setDragOver] = useState(false);
  const [search, setSearch] = useState("");
  const fileInputRef = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/projects/${projectId}/files`, { credentials: "include" });
      if (!res.ok) throw new Error(t("data_hub.tree_err_with_status", { message: t("file_tree.err_load"), status: res.status }));
      const data = await res.json();
      const loaded: ProjectFile[] = data.files ?? [];
      setFiles(loaded);
      onFilesChanged?.(loaded.filter(f => f.source === "upload").map(f => ({ name: f.name, size: f.size })));
    } catch (e: any) {
      setError(e instanceof Error && e.message.startsWith(t("file_tree.err_load")) ? e.message : t('file_tree.err_load'));
    } finally {
      setLoading(false);
    }
  }, [projectId]);

  useEffect(() => { load(); }, [load]);

  // Deep-link: when a `selectFileId` is supplied and its file has loaded, open
  // it as an object exactly once. This is what makes a dataset reference in the
  // composer/outputs/report resolve to the same object here.
  useEffect(() => {
    if (!selectFileId || !onOpenDataset) return;
    if (openedSelectRef.current === selectFileId) return;
    const match = files.find(f => f.id === selectFileId);
    if (match) {
      openedSelectRef.current = selectFileId;
      onOpenDataset(match);
    }
  }, [selectFileId, files, onOpenDataset]);

  // Refresh when another component saves run outputs to this project.
  useEffect(() => {
    const handler = () => load();
    window.addEventListener('biomate:project-files-updated', handler);
    return () => window.removeEventListener('biomate:project-files-updated', handler);
  }, [load]);

  /**
   * Upload files one request each — a folder's files carry their folder-relative path
   * (webkitRelativePath) so the server stores the structure. One failure never aborts
   * the batch; each failure is reported with a localized reason.
   */
  const handleUpload = async (incoming: File[] | FileList | null) => {
    const files = Array.from(incoming ?? []);
    if (!files.length) return;
    setUploading(true);
    setError(null);
    setUploadReport(null);
    setProgress({ done: 0, total: files.length });
    let ok = 0;
    let deduped = 0;
    const failures: { name: string; reason: string }[] = [];
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const rel = relativePathOf(file);
      const display = rel || file.name;
      if (file.size > MAX_UPLOAD_BYTES) {
        failures.push({ name: display, reason: t("data_hub.tree_err_too_large") });
      } else {
        try {
          const form = new FormData();
          // Field BEFORE the file part; also sent for a plain pick (= file.name) because
          // text fields arrive as UTF-8 while multipart filenames are decoded as latin1.
          form.append("relativePath", rel || file.name);
          form.append("file", file, file.name);
          const res = await fetch(`/api/projects/${projectId}/files/upload`, {
            method: "POST",
            credentials: "include",
            body: form,
          });
          if (!res.ok) {
            const body = await res.json().catch(() => null);
            failures.push({ name: display, reason: uploadErrorReason(res.status, body) });
          } else {
            ok += 1;
            const body = await res.json().catch(() => null);
            if (body?.deduplicated) deduped += 1;
          }
        } catch (e) {
          // fetch rejects with TypeError on a network failure; a DOMException means the
          // browser could not read the file's bytes.
          const reason = e instanceof TypeError ? t("data_hub.tree_err_network") : t("data_hub.tree_err_unreadable");
          failures.push({ name: display, reason });
        }
      }
      setProgress({ done: i + 1, total: files.length });
    }
    setUploadReport({ ok, deduped, failures });
    setProgress(null);
    setUploading(false);
    if (ok > 0) {
      // Uploaded folders open so the new structure is visible.
      setExpandedFolders((prev) => {
        const next = new Set(prev);
        next.add("inputs");
        for (const f of files) {
          const parts = relativePathOf(f).split("/").filter(Boolean).slice(0, -1);
          let path = "inputs";
          for (const part of parts) { path = `${path}/${part}`; next.add(path); }
        }
        return next;
      });
      await load();
    }
  };

  const handleImportUrl = async () => {
    const url = urlVal.trim();
    if (!url) return;
    setImportingUrl(true);
    try {
      const res = await fetch(`/api/projects/${projectId}/files/import-url`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ url }),
      });
      if (!res.ok) {
        // A name clash says which entry holds the name (same reason as an upload's 409).
        if (res.status === 409) {
          const body = await res.json().catch(() => null);
          throw new Error(t("data_hub.tree_err_item", { name: t("file_tree.err_import_url"), reason: uploadErrorReason(409, body) }));
        }
        throw new Error(t("data_hub.tree_err_with_status", { message: t("file_tree.err_import_url"), status: res.status }));
      }
      setUrlVal("");
      setUrlOpen(false);
      await load();
    } catch (e: any) {
      setError(e instanceof Error && e.message.startsWith(t("file_tree.err_import_url")) ? e.message : t('file_tree.err_import_url'));
    } finally {
      setImportingUrl(false);
    }
  };

  const handleDelete = async (fileId: string) => {
    if (!confirm(t('file_tree.confirm_delete'))) return;
    try {
      const res = await fetch(`/api/projects/${projectId}/files/${fileId}`, {
        method: "DELETE",
        credentials: "include",
      });
      if (!res.ok) throw new Error(t("data_hub.tree_err_with_status", { message: t("file_tree.err_delete"), status: res.status }));
      setFiles((prev) => {
        const next = prev.filter((f) => f.id !== fileId);
        onFilesChanged?.(next.filter(f => f.source === "upload").map(f => ({ name: f.name, size: f.size })));
        return next;
      });
    } catch (e: any) {
      setError(e instanceof Error && e.message.startsWith(t("file_tree.err_delete")) ? e.message : t('file_tree.err_delete'));
    }
  };

  const handleDownload = async (fileId: string) => {
    try {
      const res = await fetch(`/api/projects/${projectId}/files/${fileId}/url`, { credentials: "include" });
      if (!res.ok) throw new Error(t("data_hub.tree_err_with_status", { message: t("file_tree.err_download"), status: res.status }));
      const data = await res.json();
      // On desktop: fetch blob and show native save dialog
      if (isDesktop()) {
        const blob = await fetch(data.url).then(r => r.blob());
        const saved = await desktopSaveFile(blob, data.name);
        if (saved) return;
      }
      // Browser fallback
      const a = document.createElement("a");
      a.href = data.url;
      a.download = data.name;
      a.click();
    } catch (e: any) {
      setError(e instanceof Error && e.message.startsWith(t("file_tree.err_download")) ? e.message : t('file_tree.err_download'));
    }
  };

  /** PATCH/POST a rename; on success refresh the tree and keep the destination folders open. */
  const submitRename = async (url: string, method: "PATCH" | "POST", body: Record<string, string>, openName: string, includeLeaf: boolean): Promise<string | null> => {
    try {
      const res = await fetch(url, {
        method,
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => null)) as RenameErrorBody | null;
        return renameErrorReason(res.status, body);
      }
    } catch {
      return t("file_tree.rename_err_network");
    }
    setExpandedFolders((prev) => {
      const next = new Set(prev);
      for (const p of folderPathsOf(openName, includeLeaf)) next.add(p);
      return next;
    });
    await load();
    return null;
  };

  const handleRenameFile = (file: ProjectFile, name: string) =>
    submitRename(`/api/projects/${projectId}/files/${file.id}`, "PATCH", { name }, name, false);

  const handleRenameFolder = (from: string, to: string) =>
    submitRename(`/api/projects/${projectId}/files/rename-folder`, "POST", { from, to }, to, true);

  const handleCopy = (id: string, key: string) => {
    navigator.clipboard.writeText(key).catch(() => {});
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 1500);
    if (onPickFile) {
      const file = files.find((f) => f.id === id);
      if (file) onPickFile(key, file.name);
    }
  };

  const q = search.trim().toLowerCase();
  const tree = buildTree(q ? files.filter((f) => f.name.toLowerCase().includes(q)) : files);

  const toggleFolder = (path: string) => {
    setExpandedFolders((prev) => {
      const next = new Set(prev);
      if (next.has(path)) next.delete(path);
      else next.add(path);
      return next;
    });
  };

  // Recursive tree rows: folders (any depth) then files; a search expands everything.
  const renderNode = (node: TreeNode, depth: number): JSX.Element => {
    if (node.type === "file") {
      return (
        <FileRow
          key={node.file.id}
          file={node.file}
          label={node.name}
          depth={depth}
          projectId={projectId}
          onDelete={handleDelete}
          onDownload={handleDownload}
          copiedId={copiedId}
          onCopy={handleCopy}
          onOpenDataset={onOpenDataset}
          onRename={canEdit ? handleRenameFile : undefined}
          canEdit={canEdit}
        />
      );
    }
    const isOpen = Boolean(q) || expandedFolders.has(node.path);
    // Input folders (rebuilt from file names) open as folder objects; run groups do not.
    const inputRel = node.path === "inputs" ? "" : node.path.startsWith("inputs/") ? node.path.slice("inputs/".length) : null;
    return (
      <div key={node.path}>
        <FolderRow
          node={node}
          depth={depth}
          expanded={isOpen}
          selected={inputRel !== null && inputRel === selectedFolder}
          onToggle={() => {
            toggleFolder(node.path);
            if (inputRel !== null) onOpenFolder?.(inputRel);
          }}
          onRename={canEdit ? handleRenameFolder : undefined}
        />
        {isOpen && node.children.map((child) => renderNode(child, depth + 1))}
      </div>
    );
  };

  return (
    <div
      className={cn(
        "relative flex flex-col h-full border rounded-md bg-background overflow-hidden",
        dragOver && "ring-2 ring-primary"
      )}
      onDragOver={(e) => { e.preventDefault(); if (canEdit) setDragOver(true); }}
      onDragLeave={() => setDragOver(false)}
      onDrop={(e) => {
        e.preventDefault();
        setDragOver(false);
        if (!canEdit) return;
        // Walk dropped folders recursively (webkitGetAsEntry) — the entries must be read
        // synchronously inside the event, which filesFromDataTransfer does before awaiting.
        // A dropped folder's own "directory pseudo-file" is never uploaded.
        void filesFromDataTransfer(e.dataTransfer).then((files) => handleUpload(files));
      }}
      data-testid="project-file-tree"
    >
      {/* Toolbar */}
      <div className="flex items-center gap-2 px-3 py-2 border-b bg-muted/30 shrink-0">
        <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex-1">{t('file_tree.files')}</span>
        {/* Desktop: native file picker. Browser: standard input. Owner/editor only. */}
        {canEdit && (isDesktop() ? (
          <Button
            size="sm"
            variant="ghost"
            className="h-6 px-2 text-xs gap-1"
            disabled={uploading}
            data-testid="project-files-upload-btn"
            onClick={async () => {
              setUploading(true);
              try {
                await desktopPickAndUpload(projectId);
                await load();
              } catch {
                setError(t('file_tree.err_upload'));
              } finally {
                setUploading(false);
              }
            }}
          >
            {uploading ? <RefreshCw className="h-3 w-3 animate-spin" /> : <Upload className="h-3 w-3" />}
            {t('file_tree.add')}
          </Button>
        ) : (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                size="sm"
                variant="ghost"
                className="h-6 px-2 text-xs gap-1"
                disabled={uploading}
                title={t("data_hub.tree_add_menu")}
                data-testid="project-files-upload-btn"
              >
                {uploading ? (
                  <RefreshCw className="h-3 w-3 animate-spin" />
                ) : (
                  <Plus className="h-3 w-3" />
                )}
                {t('file_tree.add')}
                <ChevronDown className="h-3 w-3 opacity-60" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="min-w-[8rem]">
              <DropdownMenuItem onSelect={() => fileInputRef.current?.click()} data-testid="project-files-add-files">
                <FilePlus className="h-3.5 w-3.5 mr-2" />{t("data_hub.tree_add_files")}
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => folderInputRef.current?.click()} data-testid="project-files-add-folder">
                <FolderUp className="h-3.5 w-3.5 mr-2" />{t("data_hub.tree_add_folder")}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        ))}
        {canEdit && (
          <Button
            size="sm"
            variant="ghost"
            className="h-6 px-2 text-xs gap-1"
            onClick={() => setUrlOpen((o) => !o)}
            disabled={uploading}
            title={t('file_tree.import_url_title')}
            data-testid="project-files-url-btn"
          >
            <Link2 className="h-3 w-3" />
            {t('file_tree.add_url')}
          </Button>
        )}
        <Button
          size="sm"
          variant="ghost"
          className="h-6 w-6 p-0"
          onClick={load}
          disabled={loading}
          title={t('file_tree.refresh')}
          data-testid="project-files-refresh-btn"
        >
          <RefreshCw className={cn("h-3 w-3", loading && "animate-spin")} />
        </Button>
        <input
          ref={fileInputRef}
          type="file"
          multiple
          className="hidden"
          onChange={(e) => { const picked = Array.from(e.target.files ?? []); e.currentTarget.value = ""; void handleUpload(picked); }}
          data-testid="project-files-input"
        />
        {/* Folder picker — same attribute set as the chat composer / upload panel. */}
        <input
          ref={folderInputRef}
          type="file"
          multiple
          {...({ webkitdirectory: "", directory: "", mozdirectory: "" } as Record<string, string>)}
          className="hidden"
          onChange={(e) => { const picked = Array.from(e.target.files ?? []); e.currentTarget.value = ""; void handleUpload(picked); }}
          data-testid="project-files-folder-input"
        />
      </div>
      {/* Paste-a-URL ingest (design §4.6) — fetches into the project and shows in the tree. */}
      {urlOpen && canEdit && (
        <div className="flex items-center gap-1 px-1 pb-1 shrink-0" data-testid="project-files-url-row">
          <input
            type="url"
            value={urlVal}
            onChange={(e) => setUrlVal(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && !importingUrl) handleImportUrl(); }}
            placeholder={t('file_tree.import_url_placeholder')}
            className="flex-1 rounded border bg-background px-2 py-1 text-xs"
            data-testid="project-files-url-input"
            autoFocus
          />
          <Button
            size="sm"
            className="h-6 px-2 text-xs"
            onClick={handleImportUrl}
            disabled={importingUrl || !urlVal.trim()}
            data-testid="project-files-url-import"
          >
            {importingUrl ? <RefreshCw className="h-3 w-3 animate-spin" /> : t('file_tree.import')}
          </Button>
        </div>
      )}

      {/* Upload progress + per-file outcome (localized). */}
      {(progress || uploadReport) && (
        <div className="px-3 py-1.5 border-b text-xs space-y-1 shrink-0" data-testid="project-files-upload-status">
          {progress ? (
            <p role="status" className="text-muted-foreground" data-testid="project-files-upload-progress">
              {t("data_hub.tree_uploading", { done: progress.done, total: progress.total })}
            </p>
          ) : uploadReport && (
            <>
              <div className="flex items-start gap-2">
                <p className={cn("flex-1", uploadReport.failures.length ? "text-destructive" : "text-muted-foreground")} data-testid="project-files-upload-summary">
                  {t("data_hub.tree_upload_summary", { ok: uploadReport.ok, failed: uploadReport.failures.length })}
                </p>
                <button
                  type="button"
                  onClick={() => setUploadReport(null)}
                  title={t("data_hub.tree_dismiss")}
                  aria-label={t("data_hub.tree_dismiss")}
                  className="p-0.5 rounded hover:bg-muted"
                  data-testid="project-files-upload-dismiss"
                >
                  <X className="h-3 w-3" />
                </button>
              </div>
              {uploadReport.deduped > 0 && (
                <p className="text-muted-foreground">{t("data_hub.tree_upload_deduped", { n: uploadReport.deduped })}</p>
              )}
              {uploadReport.failures.length > 0 && (
                <ul className="max-h-24 overflow-y-auto space-y-0.5" data-testid="project-files-upload-failures">
                  {uploadReport.failures.map((f, i) => (
                    <li key={i} className="text-destructive [overflow-wrap:anywhere]">
                      {t("data_hub.tree_err_item", { name: f.name, reason: f.reason })}
                    </li>
                  ))}
                </ul>
              )}
            </>
          )}
        </div>
      )}

      {/* Scope hint + search (design §4.2.2) */}
      <div className="px-3 pt-1.5 pb-1 space-y-1.5 border-b shrink-0" data-testid="project-files-header">
        <p className="text-fs-xs text-muted-foreground">{t('file_tree.scope_hint')}</p>
        <div className="relative">
          <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t('file_tree.search_files')}
            aria-label={t('file_tree.search_files')}
            data-testid="project-files-search"
            className="w-full h-7 pl-7 pr-2 text-xs rounded border bg-background"
          />
        </div>
      </div>

      {/* Tree body — the only part that scrolls; the toolbar, upload status and search above
          never shrink (they used to be squeezed and clipped when the status list appeared). */}
      <div className="flex-1 min-h-0 overflow-y-auto overflow-x-hidden px-1 pt-1 pb-3" data-testid="project-files-body">
        {error && (
          <div className="text-xs text-red-600 px-3 py-2">{error}</div>
        )}
        {!loading && tree.length === 0 && !error && (
          <div className="flex flex-col items-center justify-center py-10 gap-2 text-muted-foreground">
            <Folder className="h-8 w-8 opacity-30" />
            <p className="text-xs">{t('file_tree.no_files')}</p>
            <p className="text-xs opacity-70">{t('file_tree.drop_hint')}</p>
          </div>
        )}
        {tree.map((node) => renderNode(node, 0))}
      </div>

      {/* Drop hint */}
      {dragOver && (
        <div className="absolute inset-0 flex items-center justify-center bg-background/80 pointer-events-none rounded-md border-2 border-dashed border-primary z-10">
          <p className="text-sm font-medium text-primary">{t("data_hub.tree_drop_overlay")}</p>
        </div>
      )}
    </div>
  );
}
