/**
 * Workflows library — the unified surface opened from the sidebar "Workflows"
 * entry. Replaces the dead StarredWorkflowsDialog (hardcoded demo data, no-op
 * Run/View) with a real library that combines three sections:
 *
 *   • Browse       — live ranked catalog search (POST /api/ai_assistant/search_ranked)
 *   • My workflows — the user's uploaded/personal workflows (GET /api/workflows/personal)
 *   • Import       — upload a new .nf / .ga / .yml pipeline (POST /api/workflows/upload-file)
 *
 * The Browse/My-workflows/Import tabs and all upload + personal-list logic live
 * in <WorkflowHistoryDialog> (library mode) so nothing is rebuilt. This wrapper
 * only wires "click a catalog result → seed the chat to run it" onto the
 * established, non-destructive /?draft= seed path (App.tsx reads ?draft= and
 * pre-fills the composer for review — same mechanism the project "Analyze with
 * BioMate" flow uses).
 */

import { WorkflowHistoryDialog } from './workflow-history-dialog';
import { stashWorkflowSelection, type WorkflowSelection } from '@/lib/workflow-selection';

interface WorkflowsLibraryDialogProps {
  /** Modal mode: controlled open state. Ignored (treated as always-open) when asPage. */
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  /** Render as a full-page panel (the /workflows route) instead of a modal. */
  asPage?: boolean;
  /**
   * Seed the chat composer with the given prompt. Defaults to navigating to
   * /?draft=<prompt>, which App.tsx consumes to pre-fill (not auto-send) the
   * composer. Injectable so tests can observe the seed without a real navigation.
   */
  onSeedChat?: (prompt: string, selection?: WorkflowSelection) => void;
}

export function WorkflowsLibraryDialog({ open = false, onOpenChange, asPage = false, onSeedChat }: WorkflowsLibraryDialogProps) {
  return (
    <WorkflowHistoryDialog
      open={asPage ? true : open}
      onOpenChange={onOpenChange ?? (() => {})}
      asPage={asPage}
      library
      onSeedChat={(prompt, selection) => {
        if (onSeedChat) { onSeedChat(prompt, selection); return; }
        // The chosen workflow's identity rides with the next send (context.selectedWorkflow);
        // the visible draft stays a plain sentence.
        if (selection) stashWorkflowSelection(selection);
        // Established seed path: /?draft= pre-fills the composer for review/run.
        window.location.assign(`/?draft=${encodeURIComponent(prompt)}`);
      }}
      // Personal "Open" already dispatches biomate:open-personal-workflow (the
      // established run path); these run-history callbacks are inert in library
      // mode (Run History tab is hidden) but kept defined for safety.
      onOpenRun={(row) => { if (row.chatSessionId) window.location.assign(`/?session=${encodeURIComponent(row.chatSessionId)}`); }}
      onRunAgain={(row) => { window.location.assign(`/?reuseWorkflow=${encodeURIComponent(row.runId)}`); }}
    />
  );
}
