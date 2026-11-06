import type { ExecutionRunStatus } from '../shared/schema';

/** Bridge chain outcomes to the existing Run Manager schema without claiming success. */
export function classifyChainRunStatus(raw: unknown): {
  status: ExecutionRunStatus; terminal: boolean; errorMessage?: string;
} {
  switch (String(raw || 'running').toLowerCase()) {
    case 'succeeded': case 'completed':
      return { status: 'completed', terminal: true };
    case 'partial':
      return { status: 'failed', terminal: true, errorMessage: 'Pipeline partially completed. Some steps failed or were blocked; inspect the step results before using the outputs.' };
    case 'blocked':
      return { status: 'failed', terminal: true, errorMessage: 'Pipeline blocked. Required prerequisite steps did not complete.' };
    case 'failed': case 'error':
      return { status: 'failed', terminal: true, errorMessage: 'Pipeline failed. Inspect the step results for details.' };
    case 'cancelled': case 'canceled':
      return { status: 'cancelled', terminal: true };
    case 'awaiting_approval': case 'paused':
      return { status: 'paused', terminal: false };
    case 'pending': case 'queued':
      return { status: 'queued', terminal: false };
    default:
      return { status: 'running', terminal: false };
  }
}
