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
import { Loader2, Search } from 'lucide-react';
import { analytics } from '@/lib/analytics';

interface RunRow {
  runId: string;
  workflowName: string;
  status: string;
  createdAt: string;
  updatedAt: string;
  chatSessionId?: string;
  progressPercent: number;
}

interface WorkflowHistoryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onOpenRun?: (row: RunRow) => void;
  onRunAgain?: (row: RunRow) => void;
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

export function WorkflowHistoryDialog({ open, onOpenChange, onOpenRun, onRunAgain }: WorkflowHistoryDialogProps) {
  const [rows, setRows] = useState<RunRow[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [search, setSearch] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

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

  // Reset state when dialog closes
  useEffect(() => {
    if (!open) {
      setSearch('');
      setOffset(0);
      setRows([]);
      setTotal(0);
      setError(null);
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
          <DialogTitle>Workflow Runs</DialogTitle>
        </DialogHeader>

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

        <ScrollArea className="h-[380px] pr-3">
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

        {/* Footer: count + pagination — only shown when there's data */}
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
      </DialogContent>
    </Dialog>
  );
}
