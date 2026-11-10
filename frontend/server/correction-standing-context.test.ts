/**
 * Routing corrections are STANDING, project-scoped context.
 *
 * Audit gaps (2026-11-09) this pins:
 *  (a) the correction block used to be injected ONLY on the first message of a
 *      session (inside the `isFirstMessage` gate). It is now built on every turn
 *      via `_buildStandingLtmPrefix`, independent of message position.
 *  (b) corrections used to be keyed on userId only, bleeding across projects.
 *      They are now scoped to `context.projectId` (null for project-less chats),
 *      so a correction made in project A never surfaces in project B.
 *
 * (a) is verified behaviourally (the standing prefix builds for a NON-first
 * message — previousMessages non-empty) plus a source assertion that the build
 * lives outside the `isFirstMessage` gate; (b) is verified at the block level by
 * threading projectId into the repository query (spied).
 */
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
// Construct the assistant in local-only mode so its constructor uses the local
// messages client instead of instantiating Anthropic (which throws under jsdom).
process.env.BIOMATE_LOCAL_ONLY = '1';
process.env.BIOMATE_LOCAL_LLM_URL = 'http://localhost:8000/v1';
process.env.BIOMATE_LOCAL_LLM_ORIGIN = 'http://localhost:8000';
process.env.BIOMATE_LOCAL_LLM_MODEL = 'trial';

import { GalaxyAssistant } from './galaxy-assistant';
import { memoryService } from './memory-repository';

// Corrections keyed by the project they were made in; `null` = account-level.
const CORRECTIONS: Record<string, any[]> = {
  'project-A': [
    { suggestedApproach: { workflow: 'maxquant' }, correctedApproach: { workflow: 'dia_nn' }, userExplanation: 'A-only: DIA needs DIA-NN', projectId: 'project-A' },
  ],
  'project-B': [
    { suggestedApproach: { workflow: 'star' }, correctedApproach: { workflow: 'salmon' }, userExplanation: 'B-only: prefer salmon', projectId: 'project-B' },
  ],
  account: [
    { suggestedApproach: { workflow: 'bwa' }, correctedApproach: { workflow: 'bowtie2' }, userExplanation: 'account-level: prefer bowtie2', projectId: null },
  ],
};

// Spy honouring the scoping contract: a project id returns that project's
// corrections PLUS account-level; null returns only account-level; undefined
// returns everything (legacy).
async function scopedCorrections(_userId: string, _limit: number, projectId?: string | null): Promise<any[]> {
  if (projectId === undefined) return [...CORRECTIONS['project-A'], ...CORRECTIONS['project-B'], ...CORRECTIONS.account];
  if (projectId === null) return [...CORRECTIONS.account];
  return [...(CORRECTIONS[projectId] || []), ...CORRECTIONS.account];
}

describe('routing corrections: standing + project-scoped', () => {
  const assistant: any = new GalaxyAssistant({ galaxyAPIProxy: {} } as any);
  let spy: any;

  beforeEach(() => {
    spy = vi.spyOn(memoryService.users, 'getUserCorrections').mockImplementation(scopedCorrections as any);
  });
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('(a) builds the correction block on a NON-first message (standing, not first-message-only)', async () => {
    const block = await assistant._buildStandingLtmPrefix({
      userId: 'user-1',
      projectId: 'project-A',
      // A non-first message: prior turns exist — the block must still build.
      previousMessages: [
        { role: 'user', content: 'earlier turn' },
        { role: 'assistant', content: 'earlier reply' },
      ],
    });
    expect(block).toContain('[User routing corrections');
    expect(block).toContain('dia_nn'); // project-A correction present
  });

  it('(b) project A correction is NOT returned for project B', async () => {
    const blockB = await assistant._buildStandingLtmPrefix({ userId: 'user-1', projectId: 'project-B' });
    // Scoped to project B: B's correction + account-level, never A's.
    expect(blockB).toContain('salmon');     // project-B
    expect(blockB).toContain('bowtie2');    // account-level preserved
    expect(blockB).not.toContain('dia_nn'); // project-A must NOT leak
    expect(blockB).not.toContain('A-only');
    // The repository was queried scoped to project B (not just by user).
    expect(spy).toHaveBeenCalledWith('user-1', 5, 'project-B');
  });

  it('(b) project-less session gets ONLY account-level corrections (null scope)', async () => {
    const block = await assistant._buildStandingLtmPrefix({ userId: 'user-1' /* no projectId */ });
    expect(block).toContain('bowtie2');     // account-level preserved
    expect(block).not.toContain('salmon');  // no project leaks in
    expect(block).not.toContain('dia_nn');
    expect(spy).toHaveBeenCalledWith('user-1', 5, null);
  });

  it('no user → empty block, repository not queried', async () => {
    const block = await assistant._buildStandingLtmPrefix({ projectId: 'project-A' });
    expect(block).toBe('');
    expect(spy).not.toHaveBeenCalled();
  });
});

// Source-structure assertions: pin that corrections are wired into the
// standing (always-on) path and NOT inside the first-message gate.
const SRC = readFileSync(
  path.join(path.dirname(fileURLToPath(import.meta.url)), 'galaxy-assistant.ts'),
  'utf8',
);

describe('routing corrections: wiring is standing, not first-message-only', () => {
  it('the standing prefix is built inside the always-on `if (context.userId)` block', () => {
    const marker = 'const standingLtm = await this._buildStandingLtmPrefix(context)';
    expect(SRC).toContain(marker);
    const idxStanding = SRC.indexOf(marker);
    const idxFirstGate = SRC.indexOf('if (isFirstMessage && context.userId)');
    expect(idxStanding).toBeGreaterThan(0);
    expect(idxFirstGate).toBeGreaterThan(0);
    // The standing injection appears BEFORE the first-message gate.
    expect(idxStanding).toBeLessThan(idxFirstGate);
  });

  it('_buildCorrectionContextBlock is no longer called inside the first-message Promise.all', () => {
    // Isolate the first-message block and assert corrections are gone from it.
    const start = SRC.indexOf('if (isFirstMessage && context.userId)');
    const slice = SRC.slice(start, start + 1200);
    expect(slice).toContain('_buildCrossSessionContextBlock');
    expect(slice).toContain('_buildEpisodeMemoryBlock');
    expect(slice).not.toContain('_buildCorrectionContextBlock');
  });
});
