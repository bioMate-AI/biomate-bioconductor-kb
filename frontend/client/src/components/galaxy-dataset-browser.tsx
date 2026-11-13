import React, { useState, useEffect, useCallback } from 'react';
import { uploadFile as uploadFileShared } from '@/lib/upload';
import { t, tOr } from "@/lib/i18n";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Checkbox } from "@/components/ui/checkbox";
import { Loader2, ChevronRight, ChevronLeft, Search, Database, Clock, HardDrive, Link2, Upload, Info, FolderArchive, Folder } from "lucide-react";
import { cn } from "@/lib/utils";

interface SessionDataset {
  id: string;
  name?: string;
  label?: string;
  type?: string;
  fileType?: string;
  galaxyDatasetId?: string;
  galaxy_dataset_id?: string;
  path?: string;
  s3_uri?: string;
}

interface GalaxyHistory {
  id: string;
  name: string;
  count: number;
  size: number;
  create_time: string;
  update_time: string;
  source?: 'galaxy' | 'run';
  runId?: string;
}

interface GalaxyDataset {
  id: string;
  name: string;
  extension: string;
  file_size: number;
  state: string;
  create_time: string;
  s3_uri?: string;
}

interface GalaxyDatasetBrowserProps {
  open: boolean;
  onClose: () => void;
  sessionDatasets?: SessionDataset[];
  onSelect: (value: string, name: string) => void;
  paramLabel?: string;
  projectId?: string | null;
}

function formatBytes(bytes: number): string {
  if (!bytes || bytes === 0) return '—';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

function formatDate(iso: string): string {
  if (!iso) return '';
  try {
    return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  } catch {
    return '';
  }
}

// A single resolved selection: the value handed to onSelect + its display name.
interface PickedDataset {
  value: string;
  name: string;
}

// A history dataset is selectable only when Galaxy reports it as 'ok'. Error /
// discarded / in-progress states (e.g. a failed "Executed Notebook" ipynb shown
// greyed with its raw state) are NOT usable datasets, so they are hidden and the
// picker shows only real, selectable datasets. 'ok' is the only Galaxy state a
// dataset is readable in — this matches the existing per-row "disabled" gate.
function isUsableDataset(state: string | undefined): boolean {
  return (state || '').toLowerCase() === 'ok';
}

// Galaxy auto-creates one internal history per chat session, named like
// "GalaxyChat-2026-10-10" (or with a trailing session id). That raw identifier
// is an implementation detail — a user never named it and shouldn't see it. We
// render a friendly label instead, keeping the embedded date (the only
// user-meaningful part) when present. Conservative: only names that clearly
// start with the "GalaxyChat" auto prefix are rewritten; everything a user
// actually named passes through untouched.
const AUTO_HISTORY_DATE_RE = /^GalaxyChat[-_ ]?(\d{4}[-_]\d{2}[-_]\d{2})/i;
const AUTO_HISTORY_RE = /^GalaxyChat[-_ ]/i;
function friendlyHistoryName(name: string | undefined): string {
  const raw = (name || '').trim();
  const dated = AUTO_HISTORY_DATE_RE.exec(raw);
  if (dated) {
    return tOr('datasets_dialog.history_auto_label_dated', 'Chat session · {{date}}', { date: dated[1].replace(/_/g, '-') });
  }
  if (AUTO_HISTORY_RE.test(raw)) {
    return tOr('datasets_dialog.history_auto_label', 'Chat session');
  }
  return raw;
}

// Tab: "This session" — shows sessionDatasets prop + inline upload button with drag-drop
function SessionTab({
  datasets,
  search,
  onSelect,
  onUploaded,
}: {
  datasets: SessionDataset[];
  search: string;
  onSelect: (value: string, name: string) => void;
  onUploaded?: (ds: SessionDataset) => void;
}) {
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState('');
  const [isDragging, setIsDragging] = useState(false);
  const fileRef = React.useRef<HTMLInputElement>(null);
  const folderRef = React.useRef<HTMLInputElement>(null);

  const uploadFile = async (file: File): Promise<void> => {
    // Size-branched upload: ≤100 MiB → single POST; larger → real S3 multipart.
    const result = await uploadFileShared(file);
    const newDs: SessionDataset = {
      id: result.datasetId || file.name,
      name: file.name,
      fileType: file.name.split('.').pop() || '',
      galaxyDatasetId: result.galaxyDatasetId,
      // multipart path returns an s3:// URI through s3Key; the simple path
      // returns s3_uri directly. Both stored in newDs.s3_uri for session context.
      s3_uri: result.s3Uri || (result.s3Key ? `s3://${result.s3Key}` : undefined),
    };
    onUploaded?.(newDs);
    // Chip value: use the Galaxy dataset UUID — Claude uses this for run_code/read_file
    // ($DATA_DIR/<uuid>/filename). The s3_uri is forwarded via session_datasets context
    // so Claude can use it for Nextflow params without breaking run_code.
    const value = newDs.galaxyDatasetId || newDs.path || newDs.id;
    onSelect(value, file.name);
  };

  const handleFiles = async (files: File[]) => {
    if (files.length === 0) return;
    setUploading(true);
    setUploadError('');
    try {
      // Upload sequentially so each gets auto-selected in order
      for (const file of files) {
        await uploadFile(file);
      }
    } catch (err: any) {
      setUploadError(err.message || tOr('datasets_dialog.upload_failed', 'Upload failed'));
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? []);
    handleFiles(files);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  };
  const handleDragLeave = () => setIsDragging(false);
  // Accept BOTH files and folders on drop. A dropped folder has no entry in
  // `dataTransfer.files`, so we walk `dataTransfer.items` via the (non-standard
  // but universally-shipped) webkitGetAsEntry API and recurse directories.
  // `webkitGetAsEntry()` must be called synchronously while the drop event is
  // live, so we collect the top-level entries first, then await the walk.
  const collectEntryFiles = async (entries: any[]): Promise<File[]> => {
    const out: File[] = [];
    const walk = (entry: any): Promise<void> =>
      new Promise((resolve) => {
        if (!entry) return resolve();
        if (entry.isFile) {
          entry.file((f: File) => { out.push(f); resolve(); }, () => resolve());
        } else if (entry.isDirectory) {
          const reader = entry.createReader();
          const readBatch = () =>
            reader.readEntries(async (batch: any[]) => {
              if (!batch.length) return resolve();
              await Promise.all(batch.map(walk));
              readBatch(); // directory reads are paginated; keep going until empty
            }, () => resolve());
          readBatch();
        } else resolve();
      });
    await Promise.all(entries.map(walk));
    return out;
  };

  const handleDrop = async (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    const items = e.dataTransfer.items;
    const canTraverse = items && items.length > 0 &&
      typeof (items[0] as any).webkitGetAsEntry === 'function';
    if (canTraverse) {
      const entries: any[] = [];
      for (let i = 0; i < items.length; i++) {
        const entry = (items[i] as any).webkitGetAsEntry?.();
        if (entry) entries.push(entry);
      }
      const files = await collectEntryFiles(entries);
      handleFiles(files.length ? files : Array.from(e.dataTransfer.files));
    } else {
      handleFiles(Array.from(e.dataTransfer.files));
    }
  };

  const filtered = datasets.filter(ds => {
    const name = (ds.name || ds.label || '').toLowerCase();
    return name.includes(search.toLowerCase());
  });

  return (
    <div className="space-y-1">
      {/* Upload zone — supports click + drag-drop + multiple files */}
      <div className="mb-2 pb-2 border-b">
        <input
          ref={fileRef}
          type="file"
          multiple
          className="hidden"
          onChange={handleFileChange}
        />
        {/* Folder selection for click-to-browse (drag-drop already accepts folders).
            webkitdirectory makes the native picker choose a directory; its files
            arrive in e.target.files like any multi-file selection. */}
        <input
          ref={folderRef}
          type="file"
          multiple
          {...({ webkitdirectory: '', directory: '', mozdirectory: '' } as Record<string, string>)}
          className="hidden"
          onChange={handleFileChange}
          data-testid="dataset-folder-input"
        />
        <div
          onDragOver={handleDragOver}
          onDragLeave={handleDragLeave}
          onDrop={handleDrop}
          onClick={() => !uploading && fileRef.current?.click()}
          className={`flex flex-col items-center justify-center gap-1.5 rounded-md border-2 border-dashed px-4 py-3 cursor-pointer transition-colors ${
            isDragging
              ? 'border-primary bg-primary/5'
              : 'border-muted-foreground/25 hover:border-muted-foreground/50 hover:bg-muted/30'
          }`}
        >
          {uploading
            ? <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
            : <Upload className="h-4 w-4 text-muted-foreground" />
          }
          <span className="text-xs text-muted-foreground">
            {uploading
              ? tOr('datasets_dialog.uploading', 'Uploading…')
              : isDragging
                ? tOr('datasets_dialog.drop_active', 'Drop files or folders here')
                : tOr('datasets_dialog.drop_hint', 'Drop files or folders here, or click to browse')}
          </span>
          {!uploading && (
            <span className="text-fs-xs text-muted-foreground/60">
              {tOr('datasets_dialog.files_folders_supported', 'Files and folders supported')}
              {' · '}
              <button
                type="button"
                className="underline hover:text-foreground"
                onClick={(e) => { e.stopPropagation(); folderRef.current?.click(); }}
                data-testid="dataset-browse-folder"
              >
                {tOr('datasets_dialog.browse_folder', 'select a folder')}
              </button>
            </span>
          )}
        </div>
      </div>
      {uploadError && <p className="text-xs text-destructive px-1">{uploadError}</p>}

      {/* One-line hint — full limits/formats live in docs, not this dialog */}
      <p className="flex items-start gap-2 text-fs-xs text-muted-foreground px-1 mb-3">
        <Info className="h-3 w-3 mt-0.5 shrink-0" />
        <span>{tOr('datasets_dialog.session_help_prefix', 'Up to 50 GB per file; drop a folder to upload its files. Already on S3/HTTP/FTP? Use ')}<span className="font-medium text-foreground">{tOr('datasets_dialog.tab_url', 'From URL')}</span>.</span>
      </p>

      {datasets.length === 0 && !uploading && (
        <div className="flex flex-col items-center justify-center py-8 text-center text-muted-foreground">
          <p className="text-sm font-medium">{tOr('datasets_dialog.no_datasets_yet', 'No datasets yet')}</p>
          <p className="text-xs mt-1">{tOr('datasets_dialog.no_datasets_hint', 'Upload a file above or import from URL')}</p>
        </div>
      )}

      {filtered.length === 0 && datasets.length > 0 && (
        <p className="text-sm text-muted-foreground text-center py-8">{tOr('datasets_dialog.no_match_search', 'No datasets match “{{search}}”', { search })}</p>
      )}

      {filtered.map(ds => {
        const name = ds.name || ds.label || ds.id;
        // Prefer the durable S3 URI (survives restart, usable by AWS Batch) over the
        // host-local file_path / id.
        const value = ds.s3_uri || ds.galaxyDatasetId || ds.galaxy_dataset_id || ds.path || ds.id;
        return (
          <div
            key={ds.id}
            className="flex items-center justify-between gap-3 px-3 py-2.5 rounded-md hover:bg-accent/60 transition-colors"
          >
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium truncate">{name}</p>
              {ds.fileType && (
                <p className="text-xs text-muted-foreground">{ds.fileType}</p>
              )}
            </div>
            <Button
              size="sm"
              variant="secondary"
              className="h-7 text-xs shrink-0"
              onClick={() => onSelect(value, name)}
            >
              {tOr('datasets_dialog.use', 'Use')}
            </Button>
          </div>
        );
      })}
    </div>
  );
}

// Tab: "BioMate history" — browse all histories + their datasets
function HistoryTab({
  search,
  onSelect,
  onSelectMany,
}: {
  search: string;
  onSelect: (value: string, name: string) => void;
  // Return several datasets at once (multi-select); closes the dialog once.
  onSelectMany: (items: PickedDataset[]) => void;
}) {
  const [histories, setHistories] = useState<GalaxyHistory[]>([]);
  const [selectedHistory, setSelectedHistory] = useState<GalaxyHistory | null>(null);
  const [datasets, setDatasets] = useState<GalaxyDataset[]>([]);
  const [loading, setLoading] = useState(false);
  const [datasetsLoading, setDatasetsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [datasetsError, setDatasetsError] = useState<string | null>(null);
  const [loadTick, setLoadTick] = useState(0);
  // Checked rows in the current history view, keyed by dataset id.
  const [checked, setChecked] = useState<Record<string, PickedDataset>>({});
  const toggleChecked = useCallback((id: string, item: PickedDataset) => {
    setChecked(prev => {
      const next = { ...prev };
      if (next[id]) delete next[id];
      else next[id] = item;
      return next;
    });
  }, []);

  // Load histories on mount (or on retry)
  useEffect(() => {
    setLoading(true);
    setError(null);
    fetch('/api/galaxy/histories', { credentials: 'include' })
      .then(async r => {
        // A non-2xx means Galaxy or the DB failed — surface the real cause instead
        // of rendering an empty list that looks like "no histories".
        if (!r.ok) {
          const body = await r.json().catch(() => ({}));
          throw new Error(body?.message || body?.error || `HTTP ${r.status}`);
        }
        return r.json();
      })
      .then(data => {
        setHistories(data.histories || []);
      })
      .catch((e: any) => setError(e?.message || tOr('datasets_dialog.load_histories_failed', 'Could not load histories')))
      .finally(() => setLoading(false));
  }, [loadTick]);

  // Load datasets when a history is selected (or on retry)
  const loadDatasets = useCallback((history: GalaxyHistory) => {
    setDatasetsLoading(true);
    setDatasetsError(null);
    setDatasets([]);
    fetch(`/api/galaxy/histories/${history.id}/datasets`)
      .then(async r => {
        // A non-2xx means Galaxy/DB/S3 failed — surface it instead of rendering
        // an empty list that looks like "no datasets in this history".
        if (!r.ok) {
          const body = await r.json().catch(() => ({}));
          throw new Error(body?.message || body?.error || `HTTP ${r.status}`);
        }
        return r.json();
      })
      .then(data => setDatasets(data.datasets || []))
      .catch((e: any) => setDatasetsError(e?.message || tOr('datasets_dialog.load_datasets_failed', 'Could not load datasets')))
      .finally(() => setDatasetsLoading(false));
  }, []);

  const openHistory = useCallback((history: GalaxyHistory) => {
    setSelectedHistory(history);
    setChecked({}); // fresh selection per history
    loadDatasets(history);
  }, [loadDatasets]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-10 text-sm text-muted-foreground">
        <p>{error}</p>
        <Button variant="ghost" size="sm" className="mt-2" onClick={() => setLoadTick(t => t + 1)}>
          {tOr('datasets_dialog.retry', 'Retry')}
        </Button>
      </div>
    );
  }

  // Dataset list view (inside a history)
  if (selectedHistory) {
    const filteredDs = datasets.filter(d =>
      // Only usable ('ok') datasets are shown — errored "Executed Notebook"
      // items and other non-selectable states are hidden (issue 3).
      isUsableDataset(d.state) && (
        d.name.toLowerCase().includes(search.toLowerCase()) ||
        d.extension?.toLowerCase().includes(search.toLowerCase())
      )
    );
    const checkedItems = Object.values(checked);

    return (
      <div className="space-y-2">
        <button
          className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
          onClick={() => { setChecked({}); setSelectedHistory(null); }}
        >
          <ChevronLeft className="h-3 w-3" />
          {tOr('datasets_dialog.all_histories', 'All histories')}
        </button>
        <div className="flex items-center gap-2 pb-1 border-b">
          <Database className="h-3.5 w-3.5 text-muted-foreground" />
          <span className="text-sm font-medium truncate">{friendlyHistoryName(selectedHistory.name)}</span>
        </div>

        {datasetsLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          </div>
        ) : datasetsError ? (
          <div className="text-center py-8 text-sm text-muted-foreground">
            <p>{datasetsError}</p>
            <Button
              variant="ghost"
              size="sm"
              className="mt-2"
              onClick={() => selectedHistory && loadDatasets(selectedHistory)}
            >
              {tOr('datasets_dialog.retry', 'Retry')}
            </Button>
          </div>
        ) : filteredDs.length === 0 ? (
          <p className="text-sm text-center text-muted-foreground py-6">
            {search
              ? tOr('datasets_dialog.no_match_search', 'No datasets match “{{search}}”', { search })
              : tOr('datasets_dialog.no_datasets_in_history', 'No datasets in this history')}
          </p>
        ) : (
          <>
            <div className="space-y-1">
              {filteredDs.map(ds => {
                const value = ds.s3_uri || ds.id;
                const isChecked = !!checked[ds.id];
                return (
                  <div
                    key={ds.id}
                    className="flex items-center justify-between gap-3 px-3 py-2.5 rounded-md hover:bg-accent/60 transition-colors"
                  >
                    <Checkbox
                      checked={isChecked}
                      onCheckedChange={() => toggleChecked(ds.id, { value, name: ds.name })}
                      aria-label={tOr('datasets_dialog.select_dataset_aria', 'Select {{name}}', { name: ds.name })}
                      className="shrink-0"
                    />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium truncate">{ds.name}</p>
                      <div className="flex items-center gap-2 mt-0.5">
                        {ds.extension && (
                          <Badge variant="secondary" className="text-xs h-4 px-1">{ds.extension}</Badge>
                        )}
                        <span className="text-xs text-muted-foreground">{formatBytes(ds.file_size)}</span>
                        {ds.create_time && (
                          <span className="text-xs text-muted-foreground">{formatDate(ds.create_time)}</span>
                        )}
                      </div>
                    </div>
                    <Button
                      size="sm"
                      variant="secondary"
                      className="h-7 text-xs shrink-0"
                      onClick={() => onSelect(value, ds.name)}
                    >
                      {tOr('datasets_dialog.use', 'Use')}
                    </Button>
                  </div>
                );
              })}
            </div>
            {checkedItems.length > 0 && (
              <div className="sticky bottom-0 flex justify-end bg-background/95 backdrop-blur-sm pt-2 pb-1 border-t">
                <Button
                  size="sm"
                  className="h-7 text-xs"
                  data-testid="datasets-use-selected"
                  onClick={() => onSelectMany(checkedItems)}
                >
                  {tOr('datasets_dialog.use_selected', 'Use selected ({{count}})', { count: checkedItems.length })}
                </Button>
              </div>
            )}
          </>
        )}
      </div>
    );
  }

  // History list view. Match against both the raw name and the friendly label so
  // a search for "chat" still finds the de-identified auto histories.
  const q = search.toLowerCase();
  const filteredHistories = histories.filter(h =>
    h.name.toLowerCase().includes(q) || friendlyHistoryName(h.name).toLowerCase().includes(q)
  );

  if (filteredHistories.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center text-muted-foreground">
        <Database className="h-8 w-8 mb-3 opacity-40" />
        <p className="text-sm font-medium">
          {search
            ? tOr('datasets_dialog.no_histories_match', 'No histories match “{{search}}”', { search })
            : tOr('datasets_dialog.no_histories', 'No analysis histories found')}
        </p>
        {!search && (
          <p className="text-xs mt-1">{tOr('datasets_dialog.run_workflow_hint', 'Run a workflow to see your histories here')}</p>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-1">
      {filteredHistories.map(h => (
        <button
          key={h.id}
          className="w-full flex items-center justify-between gap-3 px-3 py-2.5 rounded-md hover:bg-accent/60 transition-colors text-left"
          onClick={() => openHistory(h)}
        >
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <p className="text-sm font-medium truncate">{friendlyHistoryName(h.name)}</p>
              {h.source === 'run' && (
                <Badge variant="outline" className="text-xs h-4 px-1 shrink-0 border-blue-300 text-blue-600">
                  {tOr('datasets_dialog.run_outputs', 'Run outputs')}
                </Badge>
              )}
            </div>
            <div className="flex items-center gap-3 mt-0.5">
              {h.size > 0 && (
                <span className="text-xs text-muted-foreground flex items-center gap-1">
                  <HardDrive className="h-3 w-3" />{formatBytes(h.size)}
                </span>
              )}
              {h.update_time && (
                <span className="text-xs text-muted-foreground flex items-center gap-1">
                  <Clock className="h-3 w-3" />{formatDate(h.update_time)}
                </span>
              )}
            </div>
          </div>
          <ChevronRight className="h-4 w-4 text-muted-foreground shrink-0" />
        </button>
      ))}
    </div>
  );
}

// URL import inline form (used inside the dialog)
function UrlImportForm({ onImported }: { onImported: (id: string, name: string) => void }) {
  const [url, setUrl] = useState('');
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Deferred = Galaxy HDA reference; materialize when a tool/workflow needs bytes.
  // Default immediate for small/previewable files; deferred for large remote WGS/BAM/etc.
  const [urlImportMode, setUrlImportMode] = useState<'immediate' | 'deferred'>('immediate');
  // Examples are secondary — collapsed by default so the input is the focus and
  // the tab isn't a wall of example URIs. Each source keeps its (localized) label.
  const [showExamples, setShowExamples] = useState(false);

  const handleImport = async () => {
    if (!url.trim()) return;
    setImporting(true);
    setError(null);
    try {
      const endpoint = urlImportMode === 'deferred' ? '/api/datasets/deferred' : '/api/datasets/import-url';
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: url.trim(), filename: url.split('/').pop() }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.message || data.error || `HTTP ${res.status}`);
      }
      const data = await res.json();
      const id = data.galaxy_dataset_id || data.dataset_id || data.id || '';
      const name = data.name || url.split('/').pop() || 'imported';
      onImported(id, name);
      setUrl('');
    } catch (e: any) {
      setError(e.message || tOr('datasets_dialog.import_failed', 'Import failed'));
    } finally {
      setImporting(false);
    }
  };

  // Compact "source → one example" row for the collapsible examples list.
  const ExampleRow = ({ label, code, icon }: { label: string; code: string; icon?: React.ReactNode }) => (
    <div className="grid grid-cols-[7rem_1fr] gap-2 items-start">
      <span className="flex items-center gap-1 text-fs-xs font-medium text-foreground/80 pt-1">
        {icon}{label}
      </span>
      <code className="block font-mono bg-background/60 rounded px-2 py-1 text-fs-xs select-all break-all">
        {code}
      </code>
    </div>
  );

  return (
    <div className="space-y-3 px-1 pb-2">
      {/* Primary action — input + Import kept at the top, the focus of the tab */}
      <div className="flex gap-2">
        <Input
          placeholder={tOr('datasets_dialog.url_placeholder', 'https://… or ftp://… or s3://…')}
          value={url}
          onChange={e => setUrl(e.target.value)}
          className="h-8 text-sm font-mono"
          onKeyDown={e => e.key === 'Enter' && !importing && handleImport()}
        />
        <Button
          size="sm"
          className="h-8 shrink-0"
          disabled={!url.trim() || importing}
          onClick={handleImport}
        >
          {importing ? <Loader2 className="h-3 w-3 animate-spin" /> : tOr('datasets_dialog.import', 'Import')}
        </Button>
      </div>
      {error && <p className="text-xs text-red-600">{error}</p>}

      <div className="flex items-center gap-3 text-fs-xs px-0.5" data-testid="url-import-mode">
        <label className="flex items-center gap-1.5 cursor-pointer">
          <input
            type="radio"
            name="url-import-mode"
            checked={urlImportMode === 'immediate'}
            onChange={() => setUrlImportMode('immediate')}
            data-testid="url-import-mode-immediate"
          />
          {tOr('datasets_dialog.url_mode_immediate', 'Download now')}
        </label>
        <label className="flex items-center gap-1.5 cursor-pointer">
          <input
            type="radio"
            name="url-import-mode"
            checked={urlImportMode === 'deferred'}
            onChange={() => setUrlImportMode('deferred')}
            data-testid="url-import-mode-deferred"
          />
          {tOr('datasets_dialog.url_mode_deferred', 'Defer (large files)')}
        </label>
      </div>

      {/* One-line reassurance — always visible, secondary to the input */}
      <p className="flex items-start gap-1.5 text-fs-xs text-muted-foreground px-0.5">
        <Info className="h-3.5 w-3.5 text-blue-500 shrink-0 mt-px" />
        <span>
          {urlImportMode === 'deferred'
            ? tOr('datasets_dialog.url_deferred_hint', 'Registers the URL without downloading now. BioMate fetches when a workflow needs the data.')
            : tOr('datasets_dialog.url_no_limit', 'No size limit — BioMate downloads server-side. Works for files of any size.')}
        </span>
      </p>

      {/* Examples + help — collapsed disclosure so the tab isn't a wall of URIs */}
      <div className="rounded-md bg-muted/50 text-xs">
        <button
          type="button"
          aria-expanded={showExamples}
          onClick={() => setShowExamples(v => !v)}
          className="w-full flex items-center gap-1.5 px-3 py-2 font-medium text-foreground/80 hover:text-foreground transition-colors"
        >
          <ChevronRight className={cn('h-3 w-3 transition-transform', showExamples && 'rotate-90')} />
          {tOr('datasets_dialog.url_examples_toggle', 'Examples & accepted sources')}
        </button>
        {showExamples && (
          <div className="px-3 pb-3 space-y-2 text-muted-foreground border-t pt-2">
            <ExampleRow
              label={tOr('datasets_dialog.url_http_label', 'Public HTTP/HTTPS:')}
              code="https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/GCA_000001405.15_GRCh38_genomic.fna.gz"
            />
            <ExampleRow
              label={tOr('datasets_dialog.url_sra_label', 'NCBI SRA / EBI ENA (public):')}
              code="https://sra-pub-run-odp.s3.amazonaws.com/sra/SRR1518169/SRR1518169"
            />
            <ExampleRow
              label={tOr('datasets_dialog.url_ftp_label', 'Public FTP:')}
              code="ftp://ftp.ncbi.nlm.nih.gov/path/to/file.fastq.gz"
            />
            <ExampleRow
              label={tOr('datasets_dialog.url_s3_label', 'AWS S3 single file (uses your Account Settings credentials):')}
              code="s3://my-bucket/project/sample.bam"
            />
            <ExampleRow
              label={tOr('datasets_dialog.url_cloud_label', 'Google Drive / Dropbox (best for large files — no browser upload):')}
              code="https://drive.google.com/file/d/FILE_ID/view?usp=sharing"
            />
            <p className="text-fs-xs pl-[7.5rem] -mt-1">{tOr('datasets_dialog.url_cloud_help', 'Set the file to "Anyone with the link" and paste it here — the server pulls it directly, so multi-GB files do not go through your browser.')}</p>
            <div className="grid grid-cols-[7rem_1fr] gap-2 items-start">
              <span className="flex items-center gap-1 text-fs-xs font-medium text-foreground/80 pt-px">
                <FolderArchive className="h-3 w-3 text-amber-500 shrink-0" />
                {tOr('datasets_dialog.url_s3_folder_label', 'S3 folder:')}
              </span>
              <p className="text-fs-xs">{tOr('datasets_dialog.url_s3_folder_help', 'Browse a configured S3 workspace folder and select individual files. This importer accepts one object URI, not a folder prefix.')}</p>
            </div>
            <p className="text-fs-xs border-t pt-2">{tOr('datasets_dialog.url_no_credentials', 'Do not place credentials in a URL. Authenticated storage requires a managed connection.')}</p>
          </div>
        )}
      </div>
    </div>
  );
}

function ProjectFilesTab({ projectId, search, onSelect, onSelectMany }: { projectId: string; search: string; onSelect: (value: string, name: string) => void; onSelectMany: (items: PickedDataset[]) => void }) {
  const [files, setFiles] = useState<Array<{ id: string; name: string; size?: number }>>([]);
  const [loading, setLoading] = useState(true);
  // Checked rows keyed by file id. The value is the project_files.id (same
  // contract as single "Use" — the server resolves it to the authorized s3_key).
  const [checked, setChecked] = useState<Record<string, PickedDataset>>({});
  const toggleChecked = useCallback((id: string, item: PickedDataset) => {
    setChecked(prev => {
      const next = { ...prev };
      if (next[id]) delete next[id];
      else next[id] = item;
      return next;
    });
  }, []);
  useEffect(() => {
    setLoading(true);
    fetch(`/api/projects/${projectId}/files`, { credentials: 'include' })
      .then(r => r.ok ? r.json() : Promise.reject())
      .then(data => setFiles(data.files || []))
      .catch(() => setFiles([]))
      .finally(() => setLoading(false));
  }, [projectId]);
  const filtered = files.filter(file => file.name.toLowerCase().includes(search.toLowerCase()));
  const checkedItems = Object.values(checked);
  if (loading) return <div className="flex justify-center py-8"><Loader2 className="h-4 w-4 animate-spin text-muted-foreground" /></div>;
  if (!filtered.length) return <p className="text-sm text-center text-muted-foreground py-6">{search ? tOr('datasets_dialog.no_project_files_match', 'No project files match “{{search}}”', { search }) : tOr('datasets_dialog.no_files_in_project', 'No files in this project')}</p>;
  return <>
    <div className="space-y-1">{filtered.map(file => (
      <div key={file.id} className="flex items-center justify-between gap-3 px-3 py-2.5 rounded-md hover:bg-accent/60">
        <Checkbox
          checked={!!checked[file.id]}
          onCheckedChange={() => toggleChecked(file.id, { value: file.id, name: file.name })}
          aria-label={tOr('datasets_dialog.select_dataset_aria', 'Select {{name}}', { name: file.name })}
          className="shrink-0"
        />
        <div className="flex-1 min-w-0"><p className="text-sm font-medium truncate">{file.name}</p><span className="text-xs text-muted-foreground">{formatBytes(Number(file.size || 0))}</span></div>
        {/* Always send the project_files.id — the server authoritatively resolves
            it to the exact, authorized s3_key at chat time. Never send a URI the
            server would have to trust. */}
        <Button size="sm" variant="secondary" className="h-7 text-xs shrink-0" onClick={() => onSelect(file.id, file.name)}>{tOr('datasets_dialog.use', 'Use')}</Button>
      </div>
    ))}</div>
    {checkedItems.length > 0 && (
      <div className="sticky bottom-0 flex justify-end bg-background/95 backdrop-blur-sm pt-2 pb-1 border-t">
        <Button
          size="sm"
          className="h-7 text-xs"
          data-testid="datasets-use-selected"
          onClick={() => onSelectMany(checkedItems)}
        >
          {tOr('datasets_dialog.use_selected', 'Use selected ({{count}})', { count: checkedItems.length })}
        </Button>
      </div>
    )}
  </>;
}

export function GalaxyDatasetBrowser({
  open,
  onClose,
  sessionDatasets = [],
  onSelect,
  paramLabel,
  projectId,
}: GalaxyDatasetBrowserProps) {
  const [activeTab, setActiveTab] = useState<'session' | 'project' | 'history' | 'url'>('session');
  const [search, setSearch] = useState('');
  // Locally uploaded files in this dialog instance (appended to sessionDatasets)
  const [localUploads, setLocalUploads] = useState<SessionDataset[]>([]);

  const allSessionDatasets = [...sessionDatasets, ...localUploads];

  // Reset to session tab and clear search when dialog opens
  useEffect(() => {
    if (open) {
      setActiveTab('session');
      setSearch('');
      setLocalUploads([]);
    }
  }, [open]);

  const handleSelect = (value: string, name: string) => {
    onSelect(value, name);
    onClose();
  };

  // Multi-select: hand each checked dataset to the existing single-select
  // handler (preserving its contract), then close the dialog exactly once.
  const handleSelectMany = (items: PickedDataset[]) => {
    if (!items.length) return;
    items.forEach(it => onSelect(it.value, it.name));
    onClose();
  };

  const tabs = [
    { id: 'session' as const, label: tOr('datasets_dialog.tab_session', 'This session') },
    ...(projectId ? [{ id: 'project' as const, label: tOr('datasets_dialog.tab_project', 'Project files'), icon: <Folder className="h-3 w-3 mr-1" /> }] : []),
    { id: 'history' as const, label: tOr('datasets_dialog.tab_history', 'BioMate history') },
    { id: 'url' as const, label: tOr('datasets_dialog.tab_url', 'From URL'), icon: <Link2 className="h-3 w-3 mr-1" /> },
  ];

  return (
    <Dialog open={open} onOpenChange={v => !v && onClose()}>
      <DialogContent className="max-w-lg max-h-[80vh] flex flex-col gap-0 p-0">
        <DialogHeader className="px-4 pt-4 pb-0">
          <DialogTitle className="text-base">
            {tOr('datasets_dialog.title', 'Select dataset')}{paramLabel ? ` — ${paramLabel}` : ''}
          </DialogTitle>
        </DialogHeader>

        {/* Tab bar */}
        <div className="flex gap-0 px-4 pt-3 border-b">
          {tabs.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={cn(
                "flex items-center px-3 py-2 text-xs font-medium border-b-2 -mb-px transition-colors",
                activeTab === tab.id
                  ? "border-primary text-foreground"
                  : "border-transparent text-muted-foreground hover:text-foreground"
              )}
            >
              {tab.icon}{tab.label}
            </button>
          ))}
        </div>

        {/* Search (not shown on URL tab) */}
        {activeTab !== 'url' && (
          <div className="px-4 pt-3">
            <div className="relative">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-muted-foreground" />
              <Input
                placeholder={t('file_tree.search_datasets')}
                value={search}
                onChange={e => setSearch(e.target.value)}
                className="h-8 pl-8 text-sm"
              />
            </div>
          </div>
        )}

        {/* Tab content */}
        <div className="flex-1 overflow-y-auto px-4 py-3 min-h-0 pb-0">
          {activeTab === 'session' && (
            <SessionTab
              datasets={allSessionDatasets}
              search={search}
              onSelect={handleSelect}
              onUploaded={ds => setLocalUploads(prev => [...prev, ds])}
            />
          )}
          {activeTab === 'history' && (
            <HistoryTab search={search} onSelect={handleSelect} onSelectMany={handleSelectMany} />
          )}
          {activeTab === 'project' && projectId && (
            <ProjectFilesTab projectId={projectId} search={search} onSelect={handleSelect} onSelectMany={handleSelectMany} />
          )}
          {activeTab === 'url' && (
            <UrlImportForm onImported={(id, name) => { handleSelect(id, name); }} />
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
