import { describe, expect, it } from 'vitest';
import { canControlExecutionFromQc, normalizeQcEvents, qcActionTaken, qcResultLabel } from './qc-assessment';

describe('QC assessment records', () => {
  it('preserves live failures and warnings for reports and export', () => {
    const rows = normalizeQcEvents({ events: [{ type: 'gate', process_name: 'QSAR', timestamp: 'time',
      failures: [{ metric: 'cv_r2', value: 0.2, threshold: 0.5, operator: '<', entity: 'model-v1', source: 'results.json' },
        { metric: 'n_compounds', value: 20, threshold: 50, advisory: true }] }] });
    expect(rows[0]).toMatchObject({ ts: 'time', gate: 'cv_r2', status: 'fail', measured: 0.2,
      threshold: 0.5, entity: 'model-v1', source: 'results.json' });
    expect(rows[1].status).toBe('advisory');
    expect(qcActionTaken(rows[0])).toBe('—');
  });
  it('does not fabricate a pass or a retry', () => {
    expect(normalizeQcEvents([{ gate: 'unknown' }])[0].status).toBe('not_evaluated');
    expect(qcResultLabel(undefined)).toBe('NOT EVALUATED');
    expect(qcActionTaken(normalizeQcEvents([{ status: 'fail' }])[0])).toBe('—');
    expect(qcResultLabel('advisory')).toBe('ADVISORY');
  });
  it('retains explicit actions and is idempotent across proxy and UI', () => {
    const rows = normalizeQcEvents([{ gate: 'DILI', status: 'fail', measured: 0.875,
      action_taken: 'reviewed without rerun' }]);
    expect(normalizeQcEvents(rows)).toEqual(rows);
    expect(qcActionTaken(rows[0])).toBe('reviewed without rerun');
  });
});

describe('QC execution boundaries', () => {
  const hold = { execution_control: 'hold', hold_confirmed: true, pending_steps: ['alignment'] };
  it('never controls a terminal run, including late events', () => {
    for (const status of ['completed', 'failed', 'cancelled', 'paused']) {
      expect(canControlExecutionFromQc(hold, status)).toBe(false);
    }
  });
  it('requires an actual confirmed pending boundary, not a failed metric or suggestion', () => {
    expect(canControlExecutionFromQc({ failures: [{ metric: 'DILI' }] }, 'running')).toBe(false);
    expect(canControlExecutionFromQc({ ...hold, pending_steps: [] }, 'running')).toBe(false);
    expect(canControlExecutionFromQc({ ...hold, hold_confirmed: false }, 'running')).toBe(false);
    expect(canControlExecutionFromQc(hold, 'running')).toBe(true);
  });
});
