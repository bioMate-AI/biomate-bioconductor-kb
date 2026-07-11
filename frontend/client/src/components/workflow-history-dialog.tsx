/**
 * Gap 4 — Workflow History Dialog.
 *
 * Shows the user's workflow runs (server-backed). Each row has a status dot,
 * workflow name, timestamp, "Open" (jump to chat session) and "Run again"
 * (re-navigate with prior params via Gap 3 carryover).
 *
 * Doc: docs/20260521_GAP4_SIDEBAR_RUN_HISTORY.md
 */

import { useEffect, useRef, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2, Search, Upload, Play, CheckCircle2, Info, Trash2 } from 'lucide-react';
import { analytics } from '@/lib/analytics';
import { parseNfParams } from '@/lib/parse-nf-params';

interface RunRow {
  runId: string;
  workflowName: string;
  status: string;
  createdAt: string;
  updatedAt: string;
  chatSessionId?: string;
  progressPercent: number;
}

interface PersonalWorkflow {
  id: string;
  workflow_name: string;
  description: string;
  file_type: string;
  file_content?: string;
  created_at: string;
}

interface WorkflowHistoryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onOpenRun?: (row: RunRow) => void;
  onRunAgain?: (row: RunRow) => void;
  /** Open dialog directly on this tab (default: 'runs') */
  initialTab?: 'runs' | 'imports' | 'upload';
}

function statusColor(status: string): string {
  const s = (status || '').toLowerCase();
  if (s === 'running' || s === 'queued' || s === 'pending') return 'oklch(0.65 0.18 230)';
  if (s === 'failed' || s === 'error' || s === 'cancelled') return 'oklch(0.62 0.20 25)';
  if (s === 'completed' || s === 'ok' || s === 'succeeded') return 'oklch(0.65 0.15 145)';
  return 'oklch(0.7 0.01 260)';
}

function formatWhen(iso: string | undefined | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '—';
  const diffMs = Date.now() - d.getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `${days}d ago`;
  return d.toLocaleDateString();
}

const PAGE_SIZE = 50;

export function WorkflowHistoryDialog({ open, onOpenChange, onOpenRun, onRunAgain, initialTab }: WorkflowHistoryDialogProps) {
  const [activeTab, setActiveTab] = useState<'runs' | 'imports' | 'upload'>(initialTab ?? 'runs');
  const [rows, setRows] = useState<RunRow[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // My Imports state
  const [imports, setImports] = useState<PersonalWorkflow[]>([]);
  const [importsLoading, setImportsLoading] = useState(false);
  const [openingId, setOpeningId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [importsSearch, setImportsSearch] = useState('');

  // Upload tab state
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploadName, setUploadName] = useState('');
  const [uploadDesc, setUploadDesc] = useState('');
  const [isUploading, setIsUploading] = useState(false);
  const [uploadResult, setUploadResult] = useState<{ workflow_name: string; message: string } | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const uploadFileRef = useRef<HTMLInputElement>(null);

  function fetchRuns(searchTerm: string, page: number) {
    let cancelled = false;
    setLoading(true);
    setError(null);
    const params = new URLSearchParams({
      scope: 'all_chats',
      limit: String(PAGE_SIZE),
      offset: String(page * PAGE_SIZE),
    });
    if (searchTerm.trim()) params.set('search', searchTerm.trim());

    fetch(`/api/workflows/runs/overview?${params}`, { credentials: 'include' })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((data) => {
        if (cancelled) return;
        const list: RunRow[] = (data?.rows || []).map((row: any) => ({
          runId: row.runId,
          workflowName: row.workflowName || 'Workflow',
          status: row.status || 'unknown',
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          chatSessionId: row.chatSessionId,
          progressPercent: row.progressPercent ?? 0,
        }));
        setRows(list);
        setTotal(data?.total ?? list.length);
      })
      .catch((err) => {
        if (!cancelled) setError(err.message || 'Failed to load run history');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => { cancelled = true; };
  }

  // Fetch on open or when offset changes
  useEffect(() => {
    if (!open) return;
    return fetchRuns(search, offset);
  }, [open, offset]); // eslint-disable-line react-hooks/exhaustive-deps

  // Debounce search — reset to page 0 on new query
  function handleSearch(value: string) {
    setSearch(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setOffset(0);
      fetchRuns(value, 0);
    }, 300);
  }

  function fetchImports(searchTerm: string) {
    setImportsLoading(true);
    const params = new URLSearchParams();
    if (searchTerm.trim()) params.set('search', searchTerm.trim());
    fetch(`/api/workflows/personal?${params}`, { credentials: 'include' })
      .then((r) => r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`)))
      .then((data: PersonalWorkflow[]) => setImports(data))
      .catch(() => setImports([]))
      .finally(() => setImportsLoading(false));
  }

  // Fetch personal imports when tab switches or search changes
  useEffect(() => {
    if (!open || activeTab !== 'imports') return;
    fetchImports(importsSearch);
  }, [open, activeTab]); // eslint-disable-line react-hooks/exhaustive-deps

  function handleImportsSearch(value: string) {
    setImportsSearch(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => fetchImports(value), 300);
  }

  async function handleDeletePersonal(wf: PersonalWorkflow) {
    if (!confirm(`Delete "${wf.workflow_name}"? This cannot be undone.`)) return;
    setDeletingId(wf.id);
    try {
      const res = await fetch(`/api/workflows/personal/${wf.id}`, {
        method: 'DELETE',
        credentials: 'include',
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setImports((prev) => prev.filter((w) => w.id !== wf.id));
      analytics.track('personal_workflow_deleted', { workflow_name: wf.workflow_name });
    } catch {
      // silently keep the row — user can retry
    } finally {
      setDeletingId(null);
    }
  }

  async function handleOpenPersonal(wf: PersonalWorkflow) {
    setOpeningId(wf.id);
    try {
      // Fetch full content (file_content not returned by list endpoint)
      const resp = await fetch(`/api/workflows/personal/${wf.id}`, { credentials: 'include' });
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const full: PersonalWorkflow = await resp.json();

      const params = full.file_type === 'nf' ? parseNfParams(full.file_content || '') : [];
      const required_params = params.filter(p => p.required).map(p => ({
        name: p.name, type: p.type, description: '', default: p.default ?? undefined,
      }));
      const optional_params = params.filter(p => !p.required).map(p => ({
        name: p.name, type: p.type, description: '', default: p.default ?? undefined,
      }));

      const workflowGa = {
        name: full.workflow_name,
        description: full.description || `Imported ${full.file_type.toUpperCase()} workflow`,
        workflow_type: full.file_type === 'ga' ? 'galaxy' : 'nextflow',
        format: full.file_type === 'ga' ? 'galaxy' : 'nextflow',
        // Sentinel nextflow_path — routes.ts will replace with actual file_content execution
        nextflow_path: `personal_workflow/${full.id}.nf`,
        personal_workflow_id: full.id,
        required_params,
        optional_params,
        parameters: {},
        steps: {},
        domain: 'user_import',
      };

      onOpenChange(false);
      // Dispatch after dialog close animation (~150ms) so panel doesn't overlay the closing dialog
      const ga = workflowGa;
      const ft = full.file_type;
      setTimeout(() => {
        window.dispatchEvent(new CustomEvent('biomate:open-personal-workflow', { detail: ga }));
        analytics.track('personal_workflow_opened', { file_type: ft });
      }, 160);
    } catch {
      // silently allow the dialog to stay open; user can retry
    } finally {
      setOpeningId(null);
    }
  }

  async function handleUploadSubmit() {
    if (!uploadFile) { setUploadError('Please select a file.'); return; }
    setIsUploading(true);
    setUploadError(null);
    setUploadResult(null);
    try {
      const form = new FormData();
      form.append('file', uploadFile);
      form.append('workflowName', uploadName || uploadFile.name.replace(/\.[^.]+$/, ''));
      form.append('description', uploadDesc);
      const res = await fetch('/api/workflows/upload-file', { method: 'POST', body: form });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Upload failed');
      setUploadResult({ workflow_name: data.workflow_name, message: data.message });
      analytics.track('workflow_imported', { file_type: uploadFile.name.split('.').pop() });
    } catch (err: any) {
      setUploadError(err.message || 'Upload failed');
    } finally {
      setIsUploading(false);
    }
  }

  function resetUpload() {
    setUploadFile(null);
    setUploadName('');
    setUploadDesc('');
    setUploadResult(null);
    setUploadError(null);
  }

  // Reset state when dialog closes; restore initialTab when it opens
  useEffect(() => {
    if (open) {
      if (initialTab) setActiveTab(initialTab);
    } else {
      setSearch('');
      setOffset(0);
      setRows([]);
      setTotal(0);
      setError(null);
      setImportsSearch('');
      resetUpload();
    }
  }, [open]);

  const totalPages = Math.ceil(total / PAGE_SIZE);
  const currentPage = offset / PAGE_SIZE;
  const showingFrom = total === 0 ? 0 : offset + 1;
  const showingTo = Math.min(offset + PAGE_SIZE, total);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl" data-testid="workflow-history-dialog">
        <DialogHeader>
          <DialogTitle>Workflows</DialogTitle>
        </DialogHeader>

        {/* Tabs */}
        <div className="flex gap-1 border-b pb-0 -mb-px">
          <button
            data-testid="tab-runs"
            onClick={() => setActiveTab('runs')}
            className={`px-3 py-1.5 text-sm font-medium border-b-2 transition-colors ${
              activeTab === 'runs'
                ? 'border-primary text-primary'
                : 'border-transparent text-muted-foreground hover:text-foreground'
            }`}
          >
            Run History
          </button>
          <button
            data-testid="tab-my-imports"
            onClick={() => setActiveTab('imports')}
            className={`px-3 py-1.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-1.5 ${
              activeTab === 'imports'
                ? 'border-primary text-primary'
                : 'border-transparent text-muted-foreground hover:text-foreground'
            }`}
          >
            My Imports
          </button>
          <button
            data-testid="tab-upload"
            onClick={() => { setActiveTab('upload'); resetUpload(); }}
            className={`px-3 py-1.5 text-sm font-medium border-b-2 transition-colors flex items-center gap-1.5 ${
              activeTab === 'upload'
                ? 'border-primary text-primary'
                : 'border-transparent text-muted-foreground hover:text-foreground'
            }`}
          >
            <Upload className="w-3.5 h-3.5" />
            Import Workflow
          </button>
        </div>

        {activeTab === 'runs' && (
          <>
            {/* Search */}
            <div className="relative mt-1">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted-foreground pointer-events-none" />
              <Input
                placeholder="Search by name, status, run ID…"
                value={search}
                onChange={(e) => handleSearch(e.target.value)}
                className="pl-8 h-8 text-sm"
                data-testid="runs-search-input"
              />
            </div>

            <ScrollArea className="h-[340px] pr-3">
              {loading && (
                <div className="flex items-center justify-center py-12 text-sm text-muted-foreground">
                  <Loader2 className="w-4 h-4 animate-spin mr-2" /> Loading…
                </div>
              )}
              {error && (
                <div className="text-sm text-destructive py-4">{error}</div>
              )}
              {!loading && !error && rows.length === 0 && (
                <div className="text-sm text-muted-foreground py-12 text-center">
                  {search ? 'No runs match your search.' : "No runs yet. Run a workflow and it'll show up here."}
                </div>
              )}
              {!loading && !error && rows.length > 0 && (
                <ul className="space-y-1">
                  {rows.map((r) => (
                    <li
                      key={r.runId}
                      data-testid={`run-history-row-${r.runId}`}
                      className="flex items-center gap-3 px-2 py-2 rounded hover:bg-accent"
                    >
                      <span
                        aria-hidden
                        title={r.status}
                        style={{
                          width: 8, height: 8, borderRadius: 999,
                          background: statusColor(r.status), flexShrink: 0,
                        }}
                      />
                      <div className="flex-1 min-w-0">
                        <div className="text-sm font-medium truncate">{r.workflowName}</div>
                        <div className="text-xs text-muted-foreground">
                          {r.status} · {formatWhen(r.createdAt)}
                        </div>
                      </div>
                      <div className="flex items-center gap-1">
                        <Button
                          size="sm"
                          variant="outline"
                          data-testid={`button-open-run-${r.runId}`}
                          disabled={!r.chatSessionId}
                          title={!r.chatSessionId ? 'This run has no linked chat session' : undefined}
                          onClick={() => {
                            onOpenRun?.(r);
                            onOpenChange(false);
                          }}
                        >
                          Open
                        </Button>
                        {(r.status === 'completed' || r.status === 'ok' || r.status === 'succeeded' || r.status === 'failed' || r.status === 'error') && (
                          <Button
                            size="sm"
                            variant="default"
                            data-testid={`button-run-again-${r.runId}`}
                            disabled={!r.chatSessionId}
                            title={!r.chatSessionId ? 'This run has no linked chat session' : undefined}
                            onClick={() => {
                              analytics.track('run_again_clicked', { workflow_name: r.workflowName, source: 'sidebar_history' });
                              onRunAgain?.(r);
                              onOpenChange(false);
                            }}
                          >
                            Run again
                          </Button>
                        )}
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </ScrollArea>

            {/* Footer: count + pagination */}
            {total > 0 && (
              <div className="flex items-center justify-between pt-2 border-t text-xs text-muted-foreground">
                <span>{showingFrom}–{showingTo} of {total} runs</span>
                {totalPages > 1 && (
                  <div className="flex items-center gap-1">
                    <Button
                      size="sm"
                      variant="ghost"
                      className="h-7 px-2 text-xs"
                      disabled={currentPage === 0 || loading}
                      onClick={() => setOffset(offset - PAGE_SIZE)}
                    >
                      ← Prev
                    </Button>
                    <span className="px-1">{currentPage + 1} / {totalPages}</span>
                    <Button
                      size="sm"
                      variant="ghost"
                      className="h-7 px-2 text-xs"
                      disabled={currentPage >= totalPages - 1 || loading}
                      onClick={() => setOffset(offset + PAGE_SIZE)}
                    >
                      Next →
                    </Button>
                  </div>
                )}
              </div>
            )}
          </>
        )}

        {activeTab === 'upload' && (
          <div className="py-2 space-y-4" data-testid="workflow-upload-modal">
            {/* Tip */}
            <div style={{ display: 'flex', gap: 8, padding: '10px 12px', background: 'oklch(0.97 0.01 240)', borderRadius: 6, border: '1px solid oklch(0.88 0.03 240)' }}>
              <Info style={{ width: 14, height: 14, flexShrink: 0, marginTop: 1, color: 'oklch(0.50 0.12 240)' }} />
              <p style={{ fontSize: 12, lineHeight: 1.5, color: 'oklch(0.42 0.04 240)', margin: 0 }}>
                Upload your own <strong>Nextflow (.nf)</strong> or <strong>Galaxy (.ga / .yml)</strong> workflow.
                Once imported it appears in <em>My Imports</em> and can be launched from any chat.
                BioMate will run it on AWS Batch with your configured environment.
              </p>
            </div>

            {uploadResult ? (
              <div className="space-y-3">
                <div className="flex items-center gap-2 text-green-700 dark:text-green-400">
                  <CheckCircle2 className="h-5 w-5 shrink-0" />
                  <p className="text-sm font-medium">{uploadResult.workflow_name} imported successfully</p>
                </div>
                <p className="text-xs text-muted-foreground">{uploadResult.message}</p>
                <div className="flex gap-2">
                  <Button size="sm" variant="outline" onClick={resetUpload}>Import another</Button>
                  <Button size="sm" onClick={() => { setActiveTab('imports'); fetchImports(''); }}>View in My Imports</Button>
                </div>
              </div>
            ) : (
              <>
                <div className="space-y-1.5">
                  <Label htmlFor="dlg-wf-file" className="text-sm">
                    Workflow file <span className="text-muted-foreground text-xs">(.nf, .ga, .yml)</span>
                  </Label>
                  <div className="flex items-center gap-2">
                    <Button type="button" variant="outline" size="sm" className="shrink-0" onClick={() => uploadFileRef.current?.click()}>
                      <Upload className="mr-1.5 h-3.5 w-3.5" />Choose file
                    </Button>
                    <span className="text-xs text-muted-foreground truncate">{uploadFile ? uploadFile.name : 'No file chosen'}</span>
                  </div>
                  <input ref={uploadFileRef} type="file" accept=".nf,.ga,.yml,.yaml" className="hidden" data-testid="workflow-file-input"
                    onChange={(e) => {
                      const f = e.target.files?.[0] ?? null;
                      if (f && f.size > 10 * 1024 * 1024) {
                        setUploadError('File too large — maximum 10 MB for workflow files.');
                        setUploadFile(null);
                        e.target.value = '';
                        return;
                      }
                      setUploadFile(f);
                      setUploadError(null);
                      if (f && !uploadName) setUploadName(f.name.replace(/\.[^.]+$/, ''));
                    }}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="dlg-wf-name" className="text-sm">Workflow name</Label>
                  <Input id="dlg-wf-name" value={uploadName} onChange={e => setUploadName(e.target.value)} placeholder="My custom workflow" className="text-sm" data-testid="workflow-name-input" />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="dlg-wf-desc" className="text-sm">Description <span className="text-muted-foreground text-xs">(optional)</span></Label>
                  <textarea id="dlg-wf-desc" value={uploadDesc} onChange={e => setUploadDesc(e.target.value)} placeholder="What does this workflow do?" rows={3}
                    className="flex w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 resize-none"
                    data-testid="workflow-description-input"
                  />
                </div>
                {uploadError && <p className="text-xs text-destructive">{uploadError}</p>}
                <div className="flex justify-end gap-2 pt-1">
                  <Button onClick={handleUploadSubmit} disabled={isUploading || !uploadFile} data-testid="workflow-upload-submit">
                    {isUploading ? <><Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" />Uploading…</> : 'Import Workflow'}
                  </Button>
                </div>
              </>
            )}
          </div>
        )}

        {activeTab === 'imports' && (
          <>
          <div className="relative mb-2">
            <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted-foreground pointer-events-none" />
            <input
              type="text"
              className="w-full pl-8 pr-3 py-1.5 text-sm border rounded-md bg-background"
              placeholder="Search by name…"
              value={importsSearch}
              onChange={(e) => handleImportsSearch(e.target.value)}
              data-testid="personal-workflows-search"
            />
          </div>
          <ScrollArea className="h-[340px] pr-3">
            {importsLoading && (
              <div className="flex items-center justify-center py-12 text-sm text-muted-foreground">
                <Loader2 className="w-4 h-4 animate-spin mr-2" /> Loading…
              </div>
            )}
            {!importsLoading && imports.length === 0 && (
              <div className="text-sm text-muted-foreground py-12 text-center">
                <Upload className="w-8 h-8 mx-auto mb-3 opacity-30" />
                <p>No imported workflows yet.</p>
                <p className="mt-1 text-xs">Use the "Import Workflow" tab above to upload a .nf or .ga file.</p>
              </div>
            )}
            {!importsLoading && imports.length > 0 && (
              <ul className="space-y-1 mt-1" data-testid="personal-workflows-list">
                {imports.map((wf) => (
                  <li
                    key={wf.id}
                    data-testid={`personal-workflow-row-${wf.id}`}
                    className="flex items-center gap-3 px-2 py-2.5 rounded hover:bg-accent"
                  >
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-medium truncate">{wf.workflow_name}</div>
                      <div className="text-xs text-muted-foreground">
                        .{wf.file_type} · {formatWhen(wf.created_at)}
                        {wf.description ? ` · ${wf.description}` : ''}
                      </div>
                    </div>
                    <Button
                      size="sm"
                      variant="default"
                      data-testid={`button-open-personal-${wf.id}`}
                      disabled={openingId === wf.id || deletingId === wf.id}
                      onClick={() => handleOpenPersonal(wf)}
                    >
                      {openingId === wf.id
                        ? <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        : <><Play className="w-3.5 h-3.5 mr-1" />Open</>
                      }
                    </Button>
                    <Button
                      size="sm"
                      variant="ghost"
                      data-testid={`button-delete-personal-${wf.id}`}
                      disabled={deletingId === wf.id || openingId === wf.id}
                      title="Delete this workflow"
                      onClick={() => handleDeletePersonal(wf)}
                      className="text-muted-foreground hover:text-red-600 hover:bg-red-50 px-2"
                    >
                      {deletingId === wf.id
                        ? <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        : <Trash2 className="w-3.5 h-3.5" />
                      }
                    </Button>
                  </li>
                ))}
              </ul>
            )}
          </ScrollArea>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
