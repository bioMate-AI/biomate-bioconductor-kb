/**
 * ProjectFileTree — VS Code / Jupyter style file browser for a project.
 *
 * Displays the project's uploaded input files and run output files fetched
 * from /api/projects/:id/files. Supports:
 *   - Expand / collapse folder nodes (inputs/, outputs/<runId>/)
 *   - Single-click → copy S3 path to clipboard
 *   - Download button → presigned URL
 *   - Upload via drag-drop or file picker
 *   - Delete uploaded files (source='upload' only)
 */
import { useState, useEffect, useRef, useCallback } from "react";
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
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { t } from "@/lib/i18n";

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

function buildTree(files: ProjectFile[]): TreeNode[] {
  const inputs: FileNode[] = [];
  const outputsByRun: Record<string, FileNode[]> = {};

  for (const f of files) {
    // Only run outputs are "results"; everything else the user ingested
    // (upload, pasted URL, connector pull) is an input, regardless of source.
    if (f.source !== "run_output") {
      inputs.push({ type: "file", name: f.name, file: f });
    } else {
      const run = f.run_id || "unknown";
      if (!outputsByRun[run]) outputsByRun[run] = [];
      outputsByRun[run].push({ type: "file", name: f.name, file: f });
    }
  }

  const root: TreeNode[] = [];
  if (inputs.length > 0) {
    root.push({ type: "folder", name: "inputs", path: "inputs", children: inputs });
  }
  for (const [runId, nodes] of Object.entries(outputsByRun)) {
    const firstFile = nodes[0]?.file;
    const wfName = firstFile?.workflow_name ?? t('workflow.labels.workflow');
    // Format: "nf-core/rnaseq · Jul 11 14:23" — lets users distinguish multiple runs
    const ts = firstFile?.created_at
      ? new Date(firstFile.created_at).toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })
      : runId.slice(0, 8);
    const label = `${wfName} · ${ts}`;
    root.push({
      type: "folder",
      name: label,
      path: `outputs/${runId}`,
      children: nodes,
    });
  }
  if (inputs.length === 0 && Object.keys(outputsByRun).length === 0) {
    return [];
  }
  return root;
}

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
        if (!cancelled && d && typeof d.quality === "string") setQuality(d.quality);
      })
      .catch(() => { /* stay unknown */ });
    return () => { cancelled = true; };
  }, [file.s3_key, file.name, profilable]);

  const cls = QUALITY_DOT[quality] ?? QUALITY_DOT.unknown;
  const title = profilable
    ? t('file_tree.quality', { quality })
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

function FilePreview({ url, name }: { url: string; name: string }) {
  const ext = name.split(".").pop()?.toLowerCase() ?? "";
  const isImage = ["png","jpg","jpeg","gif","webp","svg"].includes(ext);
  const [content, setContent] = useState<string | null>(null);

  useEffect(() => {
    if (isImage) return;
    fetch(url).then(r => r.text()).then(t => setContent(t)).catch(() => setContent("(preview failed)"));
  }, [url, isImage]);

  if (isImage) {
    return <img src={url} alt={name} className="max-w-[200px] max-h-40 rounded mt-1 mb-1 ml-9" />;
  }
  if (content === null) return <div className="ml-9 mt-1 text-xs text-muted-foreground">Loading…</div>;
  const lines = content.split("\n").slice(0, ext === "csv" || ext === "tsv" ? 6 : 20);
  if ((ext === "csv" || ext === "tsv") && lines.length > 0) {
    const sep = ext === "tsv" ? "\t" : ",";
    const rows = lines.map(l => l.split(sep));
    return (
      <div className="ml-9 mt-1 mb-1 overflow-x-auto">
        <table className="text-xs border-collapse">
          {rows.map((row, i) => (
            <tr key={i} className={i === 0 ? "font-semibold bg-muted/40" : ""}>
              {row.map((cell, j) => (
                <td key={j} className="border border-border px-1.5 py-0.5 max-w-[120px] truncate">{cell}</td>
              ))}
            </tr>
          ))}
        </table>
      </div>
    );
  }
  return (
    <pre className="ml-9 mt-1 mb-1 text-xs font-mono bg-muted/40 rounded p-2 overflow-x-auto max-h-40 whitespace-pre-wrap">
      {lines.join("\n")}
    </pre>
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
  canEdit = true,
}: {
  file: ProjectFile;
  projectId: string;
  onDelete: (id: string) => void;
  onDownload: (id: string) => void;
  copiedId: string | null;
  onCopy: (id: string, key: string) => void;
  /** Open this file as a first-class DatasetObject (data hub). */
  onOpenDataset?: (file: ProjectFile) => void;
  canEdit?: boolean;
}) {
  const Icon = fileIcon(file.name, file.content_type);
  const isCopied = copiedId === file.id;
  const [previewOpen, setPreviewOpen] = useState(false);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const showPreview = canPreview(file);

  const handleTogglePreview = async () => {
    if (!previewOpen && !previewUrl) {
      try {
        const res = await fetch(`/api/projects/${projectId}/files/${file.id}/url`, { credentials: "include" });
        if (res.ok) { const d = await res.json(); setPreviewUrl(d.url); }
      } catch { /* ignore */ }
    }
    setPreviewOpen(v => !v);
  };

  return (
    <div>
      <div
        className="group flex items-center gap-1.5 px-2 py-1 rounded hover:bg-muted/60 text-sm cursor-default"
        style={{ paddingLeft: 36 }}
        title={file.s3_key}
      >
        <Icon className="h-3.5 w-3.5 text-muted-foreground shrink-0" />
        <QualityDot file={file} />
        {onOpenDataset ? (
          <button
            type="button"
            onClick={() => onOpenDataset(file)}
            className="flex-1 min-w-0 truncate text-left text-xs text-foreground hover:underline cursor-pointer"
            title={t('file_tree.open_dataset')}
            data-testid={`file-open-${file.id}`}
          >
            {file.name}
          </button>
        ) : (
          <span className="flex-1 truncate text-xs text-foreground">{file.name}</span>
        )}
        {file.step_name && (
          <span className="text-fs-xs px-1 py-0.5 rounded bg-blue-100 text-blue-700 shrink-0 font-mono" title={`Produced by step: ${file.step_name}`}>
            {file.step_name}
          </span>
        )}
        <span className="text-xs text-muted-foreground shrink-0 tabular-nums">{formatBytes(file.size)}</span>
        {showPreview && (
          <button
            title={previewOpen ? t('file_tree.hide_preview') : t('file_tree.preview')}
            onClick={handleTogglePreview}
            className="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-muted"
          >
            {previewOpen ? <EyeOff className="h-3 w-3 text-muted-foreground" /> : <Eye className="h-3 w-3 text-muted-foreground" />}
          </button>
        )}
        <button
          title={t('file_tree.copy_s3')}
          onClick={() => onCopy(file.id, file.s3_key)}
          className="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-muted"
          data-testid={`file-copy-${file.id}`}
        >
          {isCopied ? <Check className="h-3 w-3 text-green-600" /> : <Copy className="h-3 w-3 text-muted-foreground" />}
        </button>
        <button
          title={t('actions.download')}
          onClick={() => onDownload(file.id)}
          className="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-muted"
          data-testid={`file-download-${file.id}`}
        >
          <Download className="h-3 w-3 text-muted-foreground" />
        </button>
        {file.source === "upload" && canEdit && (
          <button
            title={t('actions.delete')}
            onClick={() => onDelete(file.id)}
            className="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-red-50 hover:text-red-600"
            data-testid={`file-delete-${file.id}`}
          >
            <Trash2 className="h-3 w-3" />
          </button>
        )}
      </div>
      {previewOpen && previewUrl && <FilePreview url={previewUrl} name={file.name} />}
      {previewOpen && file.input_context && (typeof file.input_context.intent === 'string' || Array.isArray(file.input_context.inputFiles)) && (
        <div className="ml-9 mt-1 mb-2 rounded border border-border bg-muted/30 p-2 text-xs space-y-1.5">
          {typeof file.input_context.intent === 'string' && (
            <div className="italic text-foreground/80">"{file.input_context.intent}"</div>
          )}
          {Array.isArray(file.input_context.inputFiles) && (file.input_context.inputFiles as string[]).length > 0 && (
            <div><span className="text-muted-foreground">Input files: </span>{(file.input_context.inputFiles as string[]).join(", ")}</div>
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
}: {
  node: FolderNode;
  expanded: boolean;
  onToggle: () => void;
}) {
  const FIcon = expanded ? FolderOpen : Folder;
  const CIcon = expanded ? ChevronDown : ChevronRight;
  return (
    <button
      onClick={onToggle}
      className="flex items-center gap-1.5 w-full px-2 py-1 rounded hover:bg-muted/40 text-left"
      style={{ paddingLeft: 16 }}
      data-testid={`folder-${node.path}`}
    >
      <CIcon className="h-3 w-3 text-muted-foreground shrink-0" />
      <FIcon className="h-3.5 w-3.5 text-yellow-500 shrink-0" />
      <span className="text-xs font-medium text-foreground">{node.name}</span>
      <span className="ml-auto text-xs text-muted-foreground">{node.children.length}</span>
    </button>
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
}

export function ProjectFileTree({ projectId, onPickFile, onFilesChanged, onOpenDataset, canEdit = true, selectFileId }: ProjectFileTreeProps) {
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
      if (!res.ok) throw new Error(await res.text());
      const data = await res.json();
      const loaded: ProjectFile[] = data.files ?? [];
      setFiles(loaded);
      onFilesChanged?.(loaded.filter(f => f.source === "upload").map(f => ({ name: f.name, size: f.size })));
    } catch (e: any) {
      setError(e?.message ?? t('file_tree.err_load'));
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

  const handleUpload = async (fileList: FileList | null) => {
    if (!fileList?.length) return;
    setUploading(true);
    try {
      for (const file of Array.from(fileList)) {
        const form = new FormData();
        form.append("file", file);
        const res = await fetch(`/api/projects/${projectId}/files/upload`, {
          method: "POST",
          credentials: "include",
          body: form,
        });
        if (!res.ok) throw new Error(await res.text());
      }
      await load();
    } catch (e: any) {
      setError(e?.message ?? t('file_tree.err_upload'));
    } finally {
      setUploading(false);
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
        const body = await res.json().catch(() => ({}));
        throw new Error((body as any)?.error || `Import failed (${res.status})`);
      }
      setUrlVal("");
      setUrlOpen(false);
      await load();
    } catch (e: any) {
      setError(e?.message ?? t('file_tree.err_import_url'));
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
      if (!res.ok) throw new Error(await res.text());
      setFiles((prev) => {
        const next = prev.filter((f) => f.id !== fileId);
        onFilesChanged?.(next.filter(f => f.source === "upload").map(f => ({ name: f.name, size: f.size })));
        return next;
      });
    } catch (e: any) {
      setError(e?.message ?? t('file_tree.err_delete'));
    }
  };

  const handleDownload = async (fileId: string) => {
    try {
      const res = await fetch(`/api/projects/${projectId}/files/${fileId}/url`, { credentials: "include" });
      if (!res.ok) throw new Error(await res.text());
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
      setError(e?.message ?? t('file_tree.err_download'));
    }
  };

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

  return (
    <div
      className={cn(
        "flex flex-col h-full border rounded-md bg-background overflow-hidden",
        dragOver && "ring-2 ring-primary"
      )}
      onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
      onDragLeave={() => setDragOver(false)}
      onDrop={(e) => {
        e.preventDefault();
        setDragOver(false);
        if (canEdit) handleUpload(e.dataTransfer.files);
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
              } catch (e: any) {
                setError(e?.message ?? t('file_tree.err_upload'));
              } finally {
                setUploading(false);
              }
            }}
          >
            {uploading ? <RefreshCw className="h-3 w-3 animate-spin" /> : <Upload className="h-3 w-3" />}
            {t('file_tree.add')}
          </Button>
        ) : (
          <Button
            size="sm"
            variant="ghost"
            className="h-6 px-2 text-xs gap-1"
            onClick={() => fileInputRef.current?.click()}
            disabled={uploading}
            data-testid="project-files-upload-btn"
          >
            {uploading ? (
              <RefreshCw className="h-3 w-3 animate-spin" />
            ) : (
              <Plus className="h-3 w-3" />
            )}
            {t('file_tree.add')}
          </Button>
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
          onChange={(e) => handleUpload(e.target.files)}
          data-testid="project-files-input"
        />
      </div>
      {/* Paste-a-URL ingest (design §4.6) — fetches into the project and shows in the tree. */}
      {urlOpen && canEdit && (
        <div className="flex items-center gap-1 px-1 pb-1" data-testid="project-files-url-row">
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

      {/* Scope hint + search (design §4.2.2) */}
      <div className="px-3 pt-1.5 pb-1 space-y-1.5 border-b">
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

      {/* Tree body */}
      <div className="flex-1 overflow-y-auto py-1">
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
        {tree.map((node) => {
          if (node.type === "folder") {
            const isOpen = expandedFolders.has(node.path);
            return (
              <div key={node.path}>
                <FolderRow
                  node={node}
                  expanded={isOpen}
                  onToggle={() => {
                    setExpandedFolders((prev) => {
                      const next = new Set(prev);
                      if (isOpen) next.delete(node.path);
                      else next.add(node.path);
                      return next;
                    });
                  }}
                />
                {isOpen &&
                  node.children.map((child) => {
                    if (child.type === "file") {
                      return (
                        <FileRow
                          key={child.file.id}
                          file={child.file}
                          projectId={projectId}
                          onDelete={handleDelete}
                          onDownload={handleDownload}
                          copiedId={copiedId}
                          onCopy={handleCopy}
                          onOpenDataset={onOpenDataset}
                          canEdit={canEdit}
                        />
                      );
                    }
                    return null;
                  })}
              </div>
            );
          }
          return null;
        })}
      </div>

      {/* Drop hint */}
      {dragOver && (
        <div className="absolute inset-0 flex items-center justify-center bg-background/80 pointer-events-none rounded-md border-2 border-dashed border-primary z-10">
          <p className="text-sm font-medium text-primary">Drop files to upload</p>
        </div>
      )}
    </div>
  );
}
