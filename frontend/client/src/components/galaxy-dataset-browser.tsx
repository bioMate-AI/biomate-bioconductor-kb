import React, { useState, useEffect, useCallback } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Loader2, ChevronRight, ChevronLeft, Search, Database, Clock, HardDrive, Link2, Upload } from "lucide-react";
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
}

interface GalaxyHistory {
  id: string;
  name: string;
  count: number;
  size: number;
  create_time: string;
  update_time: string;
}

interface GalaxyDataset {
  id: string;
  name: string;
  extension: string;
  file_size: number;
  state: string;
  create_time: string;
}

interface GalaxyDatasetBrowserProps {
  open: boolean;
  onClose: () => void;
  sessionDatasets?: SessionDataset[];
  onSelect: (value: string, name: string) => void;
  paramLabel?: string;
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

// Tab: "This session" — shows sessionDatasets prop + inline upload button
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
  const fileRef = React.useRef<HTMLInputElement>(null);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setUploadError('');
    try {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('name', file.name);
      const res = await fetch('/api/datasets/upload', { method: 'POST', body: formData });
      if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
      const data = await res.json();
      const newDs: SessionDataset = {
        id: data.dataset_id || data.id || file.name,
        name: file.name,
        fileType: file.name.split('.').pop() || '',
        galaxyDatasetId: data.dataset_id,
        path: data.file_path,
      };
      onUploaded?.(newDs);
      // Auto-select the just-uploaded file
      const value = newDs.galaxyDatasetId || newDs.path || newDs.id;
      onSelect(value, file.name);
    } catch (err: any) {
      setUploadError(err.message || 'Upload failed');
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  };

  const filtered = datasets.filter(ds => {
    const name = (ds.name || ds.label || '').toLowerCase();
    return name.includes(search.toLowerCase());
  });

  return (
    <div className="space-y-1">
      {/* Upload button — always visible at the top */}
      <div className="flex items-center gap-2 mb-2 pb-2 border-b">
        <input
          ref={fileRef}
          type="file"
          className="hidden"
          onChange={handleFileChange}
        />
        <Button
          size="sm"
          variant="outline"
          className="h-7 text-xs gap-1.5 w-full"
          disabled={uploading}
          onClick={() => fileRef.current?.click()}
        >
          {uploading ? <Loader2 className="h-3 w-3 animate-spin" /> : <Upload className="h-3 w-3" />}
          {uploading ? 'Uploading...' : 'Upload file from computer'}
        </Button>
      </div>
      {uploadError && <p className="text-xs text-destructive px-1">{uploadError}</p>}

      {datasets.length === 0 && !uploading && (
        <div className="flex flex-col items-center justify-center py-8 text-center text-muted-foreground">
          <p className="text-sm font-medium">No datasets yet</p>
          <p className="text-xs mt-1">Upload a file above or import from URL</p>
        </div>
      )}

      {filtered.length === 0 && datasets.length > 0 && (
        <p className="text-sm text-muted-foreground text-center py-8">No datasets match &ldquo;{search}&rdquo;</p>
      )}

      {filtered.map(ds => {
        const name = ds.name || ds.label || ds.id;
        const value = ds.galaxyDatasetId || ds.galaxy_dataset_id || ds.path || ds.id;
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
              Use
            </Button>
          </div>
        );
      })}
    </div>
  );
}

// Tab: "Galaxy histories" — browse all histories + their datasets
function HistoryTab({
  search,
  onSelect,
}: {
  search: string;
  onSelect: (value: string, name: string) => void;
}) {
  const [histories, setHistories] = useState<GalaxyHistory[]>([]);
  const [selectedHistory, setSelectedHistory] = useState<GalaxyHistory | null>(null);
  const [datasets, setDatasets] = useState<GalaxyDataset[]>([]);
  const [loading, setLoading] = useState(false);
  const [datasetsLoading, setDatasetsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load histories on mount
  useEffect(() => {
    setLoading(true);
    setError(null);
    fetch('/api/galaxy/histories')
      .then(r => r.json())
      .then(data => {
        setHistories(data.histories || []);
      })
      .catch(() => setError('Could not load Galaxy histories'))
      .finally(() => setLoading(false));
  }, []);

  // Load datasets when a history is selected
  const openHistory = useCallback((history: GalaxyHistory) => {
    setSelectedHistory(history);
    setDatasetsLoading(true);
    setDatasets([]);
    fetch(`/api/galaxy/histories/${history.id}/datasets`)
      .then(r => r.json())
      .then(data => setDatasets(data.datasets || []))
      .catch(() => setDatasets([]))
      .finally(() => setDatasetsLoading(false));
  }, []);

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
        <Button variant="ghost" size="sm" className="mt-2" onClick={() => window.location.reload()}>
          Retry
        </Button>
      </div>
    );
  }

  // Dataset list view (inside a history)
  if (selectedHistory) {
    const filteredDs = datasets.filter(d =>
      d.name.toLowerCase().includes(search.toLowerCase()) ||
      d.extension?.toLowerCase().includes(search.toLowerCase())
    );

    return (
      <div className="space-y-2">
        <button
          className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
          onClick={() => setSelectedHistory(null)}
        >
          <ChevronLeft className="h-3 w-3" />
          All histories
        </button>
        <div className="flex items-center gap-2 pb-1 border-b">
          <Database className="h-3.5 w-3.5 text-muted-foreground" />
          <span className="text-sm font-medium truncate">{selectedHistory.name}</span>
          <Badge variant="outline" className="text-xs ml-auto shrink-0">
            {selectedHistory.count} items
          </Badge>
        </div>

        {datasetsLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
          </div>
        ) : filteredDs.length === 0 ? (
          <p className="text-sm text-center text-muted-foreground py-6">
            {search ? `No datasets match "${search}"` : 'No datasets in this history'}
          </p>
        ) : (
          <div className="space-y-1">
            {filteredDs.map(ds => (
              <div
                key={ds.id}
                className="flex items-center justify-between gap-3 px-3 py-2.5 rounded-md hover:bg-accent/60 transition-colors"
              >
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
                  disabled={ds.state !== 'ok'}
                  onClick={() => onSelect(ds.id, ds.name)}
                >
                  {ds.state === 'ok' ? 'Use' : ds.state}
                </Button>
              </div>
            ))}
          </div>
        )}
      </div>
    );
  }

  // History list view
  const filteredHistories = histories.filter(h =>
    h.name.toLowerCase().includes(search.toLowerCase())
  );

  if (filteredHistories.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center text-muted-foreground">
        <Database className="h-8 w-8 mb-3 opacity-40" />
        <p className="text-sm font-medium">
          {search ? `No histories match "${search}"` : 'No Galaxy histories found'}
        </p>
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
            <p className="text-sm font-medium truncate">{h.name}</p>
            <div className="flex items-center gap-3 mt-0.5">
              <span className="text-xs text-muted-foreground flex items-center gap-1">
                <Database className="h-3 w-3" />{h.count} datasets
              </span>
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

  const handleImport = async () => {
    if (!url.trim()) return;
    setImporting(true);
    setError(null);
    try {
      const res = await fetch('/api/datasets/import-url', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: url.trim(), filename: url.split('/').pop() }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.message || data.error || `HTTP ${res.status}`);
      }
      const data = await res.json();
      const id = data.galaxy_dataset_id || data.dataset_id || '';
      const name = data.name || url.split('/').pop() || 'imported';
      onImported(id, name);
      setUrl('');
    } catch (e: any) {
      setError(e.message || 'Import failed');
    } finally {
      setImporting(false);
    }
  };

  return (
    <div className="space-y-3 px-1 pb-2">
      <div className="rounded-md bg-muted/50 p-3 text-xs text-muted-foreground space-y-1">
        <p className="font-medium text-foreground">Supported URL formats</p>
        <p><span className="font-mono text-xs">https://…</span> — public files, no credentials needed</p>
        <p><span className="font-mono text-xs">ftp://user:pass@host/path</span> — embed credentials in URL</p>
        <p><span className="font-mono text-xs">s3://bucket/key</span> — uses your AWS credentials from Account Settings</p>
        <p><span className="font-mono text-xs">https://…</span> <em>with auth</em> — add <span className="font-mono">?token=…</span> or use signed URLs</p>
      </div>
      <div className="flex gap-2">
        <Input
          placeholder="https://example.com/data.fastq.gz"
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
          {importing ? <Loader2 className="h-3 w-3 animate-spin" /> : 'Import'}
        </Button>
      </div>
      {error && <p className="text-xs text-red-600">{error}</p>}
    </div>
  );
}

export function GalaxyDatasetBrowser({
  open,
  onClose,
  sessionDatasets = [],
  onSelect,
  paramLabel,
}: GalaxyDatasetBrowserProps) {
  const [activeTab, setActiveTab] = useState<'session' | 'history' | 'url'>('session');
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

  const tabs = [
    { id: 'session' as const, label: `This session${allSessionDatasets.length > 0 ? ` (${allSessionDatasets.length})` : ''}` },
    { id: 'history' as const, label: 'BioMate history' },
    { id: 'url' as const, label: 'From URL', icon: <Link2 className="h-3 w-3 mr-1" /> },
  ];

  return (
    <Dialog open={open} onOpenChange={v => !v && onClose()}>
      <DialogContent className="max-w-lg max-h-[80vh] flex flex-col gap-0 p-0">
        <DialogHeader className="px-4 pt-4 pb-0">
          <DialogTitle className="text-base">
            Select dataset{paramLabel ? ` — ${paramLabel}` : ''}
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
                placeholder="Search datasets..."
                value={search}
                onChange={e => setSearch(e.target.value)}
                className="h-8 pl-8 text-sm"
              />
            </div>
          </div>
        )}

        {/* Tab content */}
        <div className="flex-1 overflow-y-auto px-4 py-3 min-h-0">
          {activeTab === 'session' && (
            <SessionTab
              datasets={allSessionDatasets}
              search={search}
              onSelect={handleSelect}
              onUploaded={ds => setLocalUploads(prev => [...prev, ds])}
            />
          )}
          {activeTab === 'history' && (
            <HistoryTab search={search} onSelect={handleSelect} />
          )}
          {activeTab === 'url' && (
            <UrlImportForm onImported={(id, name) => { handleSelect(id, name); }} />
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
