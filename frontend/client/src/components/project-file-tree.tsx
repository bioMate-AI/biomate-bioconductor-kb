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
  Folder,
  FolderOpen,
  File,
  FileText,
  Download,
  Trash2,
  Upload,
  RefreshCw,
  ChevronRight,
  ChevronDown,
  Copy,
  Check,
  Image,
  Database,
  Code2,
  FileArchive,
  Eye,
  EyeOff,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface ProjectFile {
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
    if (f.source === "upload") {
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
    const wfName = firstFile?.workflow_name ?? "Workflow";
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
}: {
  file: ProjectFile;
  projectId: string;
  onDelete: (id: string) => void;
  onDownload: (id: string) => void;
  copiedId: string | null;
  onCopy: (id: string, key: string) => void;
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
        <span className="flex-1 truncate text-xs text-foreground">{file.name}</span>
        {file.step_name && (
          <span className="text-[10px] px-1 py-0.5 rounded bg-blue-100 text-blue-700 shrink-0 font-mono" title={`Produced by step: ${file.step_name}`}>
            {file.step_name}
          </span>
        )}
        <span className="text-xs text-muted-foreground shrink-0 tabular-nums">{formatBytes(file.size)}</span>
        {showPreview && (
          <button
            title={previewOpen ? "Hide preview" : "Preview"}
            onClick={handleTogglePreview}
            className="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-muted"
          >
            {previewOpen ? <EyeOff className="h-3 w-3 text-muted-foreground" /> : <Eye className="h-3 w-3 text-muted-foreground" />}
          </button>
        )}
        <button
          title="Copy S3 path"
          onClick={() => onCopy(file.id, file.s3_key)}
          className="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-muted"
          data-testid={`file-copy-${file.id}`}
        >
          {isCopied ? <Check className="h-3 w-3 text-green-600" /> : <Copy className="h-3 w-3 text-muted-foreground" />}
        </button>
        <button
          title="Download"
          onClick={() => onDownload(file.id)}
          className="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-muted"
          data-testid={`file-download-${file.id}`}
        >
          <Download className="h-3 w-3 text-muted-foreground" />
        </button>
        {file.source === "upload" && (
          <button
            title="Delete"
            onClick={() => onDelete(file.id)}
            className="opacity-0 group-hover:opacity-100 p-0.5 rounded hover:bg-red-50 hover:text-red-600"
            data-testid={`file-delete-${file.id}`}
          >
            <Trash2 className="h-3 w-3" />
          </button>
        )}
      </div>
      {previewOpen && previewUrl && <FilePreview url={previewUrl} name={file.name} />}
      {previewOpen && file.input_context && (file.input_context.intent || file.input_context.inputFiles) && (
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
}

export function ProjectFileTree({ projectId, onPickFile, onFilesChanged }: ProjectFileTreeProps) {
  const [files, setFiles] = useState<ProjectFile[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expandedFolders, setExpandedFolders] = useState<Set<string>>(new Set(["inputs"]));
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [dragOver, setDragOver] = useState(false);
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
      setError(e?.message ?? "Failed to load files");
    } finally {
      setLoading(false);
    }
  }, [projectId]);

  useEffect(() => { load(); }, [load]);

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
      setError(e?.message ?? "Upload failed");
    } finally {
      setUploading(false);
    }
  };

  const handleDelete = async (fileId: string) => {
    if (!confirm("Delete this file?")) return;
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
      setError(e?.message ?? "Delete failed");
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
      setError(e?.message ?? "Download failed");
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

  const tree = buildTree(files);

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
        handleUpload(e.dataTransfer.files);
      }}
      data-testid="project-file-tree"
    >
      {/* Toolbar */}
      <div className="flex items-center gap-2 px-3 py-2 border-b bg-muted/30 shrink-0">
        <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wide flex-1">Files</span>
        {/* Desktop: native file picker. Browser: standard input. */}
        {isDesktop() ? (
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
                setError(e?.message ?? "Upload failed");
              } finally {
                setUploading(false);
              }
            }}
          >
            {uploading ? <RefreshCw className="h-3 w-3 animate-spin" /> : <Upload className="h-3 w-3" />}
            Upload
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
              <Upload className="h-3 w-3" />
            )}
            Upload
          </Button>
        )}
        <Button
          size="sm"
          variant="ghost"
          className="h-6 w-6 p-0"
          onClick={load}
          disabled={loading}
          title="Refresh"
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

      {/* Tree body */}
      <div className="flex-1 overflow-y-auto py-1">
        {error && (
          <div className="text-xs text-red-600 px-3 py-2">{error}</div>
        )}
        {!loading && tree.length === 0 && !error && (
          <div className="flex flex-col items-center justify-center py-10 gap-2 text-muted-foreground">
            <Folder className="h-8 w-8 opacity-30" />
            <p className="text-xs">No files yet</p>
            <p className="text-xs opacity-70">Drag & drop or click Upload</p>
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
