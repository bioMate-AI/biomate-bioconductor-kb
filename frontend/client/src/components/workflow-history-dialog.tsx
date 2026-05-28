/**
 * Gap 4 — Workflow History Dialog.
 *
 * Replaces the sidebar's previous "Workflows" → StarredWorkflowsDialog wiring
 * with a tabbed surface: Recent Runs (server-backed, the user's actual run
 * history) + Starred (the original favorites list, unchanged).
 *
 * Recent Runs is the new primary reuse surface. Each row shows a status dot,
 * workflow name, when it ran, and an "Open" button that jumps to the chat
 * session where the run lives. The right workflow panel re-attaches there
 * via the existing session-restore reconciliation effect
 * (chat-with-artifacts.tsx:410-436), and "Run again" then pre-fills the
 * panel with submitted params via Gap 3 (useRunAgainParamCarryover).
 *
 * Doc: docs/20260521_GAP4_SIDEBAR_RUN_HISTORY.md
 */

import { useEffect, useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Button } from '@/components/ui/button';
import { Clock, Star as StarIcon, Loader2 } from 'lucide-react';
import { analytics } from '@/lib/analytics';
import { starredWorkflowsService } from '@/lib/starred-workflows';
import type { StarredWorkflow } from '@shared/schema';

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
  /** Fires when user clicks "Open" on a run row. Host should navigate to the chat session. */
  onOpenRun?: (row: RunRow) => void;
  /** Fires when user clicks "Run again" on a completed/failed row. Host should
      navigate to the run's chat session AND auto-confirm with the prior params
      (Gap 3 carryover handles the pre-fill once the panel re-attaches). */
  onRunAgain?: (row: RunRow) => void;
}

function statusColor(status: string): string {
  const s = (status || '').toLowerCase();
  if (s === 'running' || s === 'queued' || s === 'pending') return 'oklch(0.65 0.18 230)'; // blue
  if (s === 'failed' || s === 'error' || s === 'cancelled') return 'oklch(0.62 0.20 25)'; // red
  if (s === 'completed' || s === 'ok' || s === 'succeeded') return 'oklch(0.65 0.15 145)'; // green
  return 'oklch(0.7 0.01 260)'; // gray
}

function formatWhen(iso: string): string {
  const d = new Date(iso);
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

export function WorkflowHistoryDialog({ open, onOpenChange, onOpenRun, onRunAgain }: WorkflowHistoryDialogProps) {
  const [tab, setTab] = useState<'recent' | 'starred'>('recent');
  const [rows, setRows] = useState<RunRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || tab !== 'recent') return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    // scope=all_chats so the user sees every workflow they've run, not just
    // the current chat session's runs.
    fetch('/api/workflows/runs/overview?scope=all_chats&limit=50', {
      credentials: 'include',
    })
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
      })
      .catch((err) => {
        if (!cancelled) setError(err.message || 'Failed to load run history');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [open, tab]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl" data-testid="workflow-history-dialog">
        <DialogHeader>
          <DialogTitle>Workflows</DialogTitle>
        </DialogHeader>
        <Tabs value={tab} onValueChange={(v) => setTab(v as 'recent' | 'starred')}>
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="recent" data-testid="tab-recent-runs">
              <Clock className="w-3.5 h-3.5 mr-1.5" /> Recent runs
            </TabsTrigger>
            <TabsTrigger value="starred" data-testid="tab-starred">
              <StarIcon className="w-3.5 h-3.5 mr-1.5" /> Starred
            </TabsTrigger>
          </TabsList>
          <TabsContent value="recent" className="mt-3">
            <ScrollArea className="h-[420px] pr-3">
              {loading && (
                <div className="flex items-center justify-center py-12 text-sm text-muted-foreground">
                  <Loader2 className="w-4 h-4 animate-spin mr-2" /> Loading run history…
                </div>
              )}
              {error && (
                <div className="text-sm text-destructive py-4">{error}</div>
              )}
              {!loading && !error && rows.length === 0 && (
                <div className="text-sm text-muted-foreground py-12 text-center">
                  No prior runs yet. Run a workflow and it'll show up here.
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
          </TabsContent>
          <TabsContent value="starred" className="mt-3">
            <ScrollArea className="h-[420px] pr-3">
              <StarredInlineList onPick={() => onOpenChange(false)} />
            </ScrollArea>
          </TabsContent>
        </Tabs>
      </DialogContent>
    </Dialog>
  );
}


function StarredInlineList({ onPick }: { onPick: () => void }) {
  const [items, setItems] = useState<StarredWorkflow[]>([]);
  useEffect(() => { setItems(starredWorkflowsService.getAllStarred()); }, []);
  if (items.length === 0) {
    return (
      <div className="text-sm text-muted-foreground py-12 text-center">
        No starred workflows yet. Star one from any workflow card to pin it here.
      </div>
    );
  }
  return (
    <ul className="space-y-1">
      {items.map((w) => (
        <li
          key={w.id}
          data-testid={`starred-row-${w.id}`}
          className="flex items-center gap-3 px-2 py-2 rounded hover:bg-accent cursor-pointer"
          onClick={onPick}
        >
          <StarIcon className="w-3.5 h-3.5 text-yellow-500 flex-shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="text-sm font-medium truncate">{w.title}</div>
            <div className="text-xs text-muted-foreground truncate">{w.description}</div>
          </div>
        </li>
      ))}
    </ul>
  );
}
