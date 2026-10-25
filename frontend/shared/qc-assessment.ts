/** Scientific assessment results are independent of workflow execution status. */
export type QcStatus = 'pass' | 'fail' | 'advisory' | 'not_evaluated' | 'unavailable';
export interface QcAssessment {
  ts?: string;
  gate?: string;
  status: QcStatus;
  message?: string;
  measured?: string | number;
  threshold?: string | number;
  operator?: string;
  entity?: unknown;
  source?: unknown;
  action_taken?: string;
  [key: string]: unknown;
}

export function qcStatus(value: unknown): QcStatus {
  const s = String(value ?? '').toLowerCase();
  if (['pass', 'passed', 'ok', '✓'].includes(s)) return 'pass';
  if (['fail', 'failed', 'halt', 'blocked'].includes(s)) return 'fail';
  if (['advisory', 'warning', 'warn'].includes(s)) return 'advisory';
  if (['unavailable', 'error'].includes(s)) return 'unavailable';
  return 'not_evaluated';
}

function display(value: unknown): string | number | undefined {
  if (value == null) return undefined;
  return typeof value === 'number' || typeof value === 'string' ? value : JSON.stringify(value);
}

/** Accept both durable flat rows and the original live process/event envelopes. */
export function normalizeQcEvents(payload: unknown): QcAssessment[] {
  const events = Array.isArray(payload) ? payload : (payload as any)?.events;
  if (!Array.isArray(events)) return [];
  return events.flatMap((event: any): QcAssessment[] => {
    if (!event || typeof event !== 'object') return [];
    const nested = Array.isArray(event.failures) ? event.failures
      : Array.isArray(event.warnings) ? event.warnings : null;
    if (nested?.length) {
      const { failures, warnings, ...envelope } = event;
      return nested.map((item: any) => {
        const row = typeof item === 'string' ? { message: item } : item;
        return {
          ...envelope, ...row,
          ts: row.ts ?? event.ts ?? event.timestamp,
          gate: row.gate ?? row.metric ?? event.process_name,
          status: row.advisory || event.type === 'warning' ? 'advisory' : 'fail',
          measured: display(row.measured ?? row.value),
          threshold: display(row.threshold),
          entity: row.entity ?? event.entity,
          source: row.source ?? event.source,
          action_taken: row.action_taken ?? event.action_taken,
        };
      });
    }
    return [{
      ...event,
      ts: event.ts ?? event.timestamp,
      gate: event.gate ?? event.metric ?? event.process_name,
      status: qcStatus(event.status ?? event.action),
      measured: display(event.measured ?? event.value),
      threshold: display(event.threshold),
    }];
  });
}

export function qcResultLabel(status: unknown): string {
  return ({ pass: 'PASS', fail: 'FAIL', advisory: 'ADVISORY',
    not_evaluated: 'NOT EVALUATED', unavailable: 'UNAVAILABLE' })[qcStatus(status)];
}

export function qcActionTaken(event: QcAssessment): string {
  return event.action_taken || '—';
}

/** Legacy post-process notifications are observations, never execution permission. */
export function canControlExecutionFromQc(event: any, status: string): boolean {
  return status === 'running' && event?.execution_control === 'hold'
    && event?.hold_confirmed === true
    && Array.isArray(event?.pending_steps) && event.pending_steps.length > 0;
}
