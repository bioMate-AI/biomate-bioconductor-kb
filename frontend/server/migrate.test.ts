import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createHash } from 'crypto';

const mocks = vi.hoisted(() => ({
  query: vi.fn(),
  release: vi.fn(),
  connect: vi.fn(),
  readdir: vi.fn(),
  read: vi.fn(),
}));

vi.mock('./db', () => ({ pool: { connect: mocks.connect } }));
vi.mock('fs', () => ({
  readFileSync: mocks.read,
  readdirSync: mocks.readdir,
  default: { readFileSync: mocks.read, readdirSync: mocks.readdir },
}));

beforeEach(() => {
  vi.resetModules();
  vi.clearAllMocks();
  mocks.connect.mockResolvedValue({ query: mocks.query, release: mocks.release });
  mocks.readdir.mockReturnValue(['0001.sql']);
  mocks.read.mockReturnValue('CREATE TABLE existing; ALTER TABLE other ADD COLUMN required text;');
  mocks.query.mockImplementation(async () => ({ rows: [] }));
});

describe('canonical transaction-backed SQL migration owner', () => {
  it.each(['42P07', '42710', '42P06'])(
    'fails closed on partial duplicate %s without claiming the whole migration applied',
    async code => {
      const failure = Object.assign(
        new Error('existing first object; later statements have not run'),
        { code },
      );
      mocks.query.mockImplementation(async (sql: string) => {
        if (sql.startsWith('CREATE TABLE existing;')) throw failure;
        return { rows: [] };
      });
      const { applyPendingMigrations } = await import('./migrate');

      await expect(applyPendingMigrations()).rejects.toBe(failure);

      const statements = mocks.query.mock.calls.map(call => call[0]);
      expect(statements).toContain('BEGIN');
      expect(statements).toContain('ROLLBACK');
      expect(statements).not.toContain('COMMIT');
      expect(statements.some(sql => sql.startsWith('INSERT INTO _migrations'))).toBe(false);
      expect(mocks.release).toHaveBeenCalledTimes(1);
    },
  );

  it('commits SQL and its ledger row in the same transaction', async () => {
    const { applyPendingMigrations } = await import('./migrate');

    expect(await applyPendingMigrations()).toEqual({ applied: ['0001.sql'], skipped: [] });

    const statements = mocks.query.mock.calls.map(call => call[0]);
    const begin = statements.indexOf('BEGIN');
    const insert = statements.findIndex(sql => sql.startsWith('INSERT INTO _migrations'));
    expect(insert).toBeGreaterThan(begin);
    expect(statements.indexOf('COMMIT')).toBeGreaterThan(insert);
    expect(statements).not.toContain('ROLLBACK');
  });

  it('skips a verified existing ledger entry without replaying its SQL', async () => {
    const sha = createHash('sha256').update(mocks.read()).digest('hex');
    mocks.query.mockImplementation(async (sql: string) => ({
      rows: sql.startsWith('SELECT filename') ? [{ filename: '0001.sql', sha256: sha }] : [],
    }));
    const { applyPendingMigrations } = await import('./migrate');

    expect(await applyPendingMigrations()).toEqual({ applied: [], skipped: ['0001.sql'] });
    expect(mocks.query.mock.calls.map(call => call[0])).not.toContain('BEGIN');
  });
});
