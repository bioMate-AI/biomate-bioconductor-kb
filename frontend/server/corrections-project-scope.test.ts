/**
 * Project scoping of the routing-corrections query.
 *
 * Audit gap (2026-11-09): corrections are stored in correction_log with a
 * projectId, but getUserCorrections keyed only on userId — so a correction made
 * in project A surfaced in project B. These tests pin the SQL WHERE clause the
 * repository now builds for each scope, proving project A's rows (project_id='A')
 * can never match a project-B query (param is 'B', never 'A') and that
 * account-level (project_id IS NULL) corrections are preserved for project-less
 * sessions.
 *
 * The query is asserted at the SQL level (no live Postgres): we capture the
 * Drizzle condition passed to .where() and serialise it with PgDialect.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { PgDialect } from 'drizzle-orm/pg-core';

const h = vi.hoisted(() => ({ captured: { where: null as any } }));

vi.mock('./db', async () => {
  const realSchema = await vi.importActual<any>('../shared/ltm-schema');
  const chain: any = {
    from: () => chain,
    where: (c: any) => {
      h.captured.where = c;
      return chain;
    },
    orderBy: () => chain,
    limit: () => Promise.resolve([]),
  };
  return {
    db: { select: () => chain },
    ltmSchema: realSchema,
    pool: {},
    schema: {},
  };
});

import { UserMemoryRepository } from './memory-repository';

const serialize = () => new PgDialect().sqlToQuery(h.captured.where);

describe('getUserCorrections — project scoping (SQL)', () => {
  const repo = new UserMemoryRepository();

  beforeEach(() => {
    h.captured.where = null;
  });

  it('project id → that project OR account-level (NULL), never another project', async () => {
    await repo.getUserCorrections('user-1', 5, 'project-A');
    const { sql, params } = serialize();
    // User is always constrained.
    expect(params).toContain('user-1');
    // The queried project is a bound param…
    expect(params).toContain('project-A');
    // …and the OR branch for account-level corrections is present.
    expect(sql.toLowerCase()).toContain('is null');
    expect(sql.toLowerCase()).toContain(' or ');
    // A DIFFERENT project's id never enters the query, so project-B rows
    // (project_id='project-B') cannot match a project-A query.
    expect(params).not.toContain('project-B');
  });

  it('project B query does not bind project A — rows are mutually exclusive', async () => {
    await repo.getUserCorrections('user-1', 5, 'project-B');
    const { params } = serialize();
    expect(params).toContain('project-B');
    expect(params).not.toContain('project-A');
  });

  it('null projectId (project-less session) → ONLY account-level (NULL) corrections', async () => {
    await repo.getUserCorrections('user-1', 5, null);
    const { sql, params } = serialize();
    expect(params).toContain('user-1');
    expect(sql.toLowerCase()).toContain('is null');
    // No project equality branch: a project-less session never pulls any
    // project's corrections.
    expect(sql.toLowerCase()).not.toContain(' or ');
  });

  it('undefined projectId (legacy / account-level callers) → no project predicate', async () => {
    await repo.getUserCorrections('user-1', 5);
    const { sql } = serialize();
    expect(sql.toLowerCase()).toContain('user_id');
    expect(sql.toLowerCase()).not.toContain('project_id');
  });
});
