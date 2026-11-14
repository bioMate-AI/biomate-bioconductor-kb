import { afterEach, describe, expect, it, vi } from 'vitest';
import { buildSkillBlock, withDefaultSkill, DEFAULT_SKILL_ID } from './galaxy-assistant';

describe('withDefaultSkill', () => {
  it('prepends the locked default and dedupes', () => {
    expect(withDefaultSkill(['drug-discovery-chemist'])).toEqual([
      DEFAULT_SKILL_ID,
      'drug-discovery-chemist',
    ]);
    expect(withDefaultSkill([DEFAULT_SKILL_ID, 'x'])).toEqual([DEFAULT_SKILL_ID, 'x']);
    expect(withDefaultSkill([])).toEqual([DEFAULT_SKILL_ID]);
    expect(withDefaultSkill(null)).toEqual([DEFAULT_SKILL_ID]);
  });
});

describe('buildSkillBlock — auto-detect + always-on default', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  function stubSkillsApi(opts: {
    detected?: string[];
    block?: string;
  }) {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        const path = String(url);
        const body = init?.body ? JSON.parse(String(init.body)) : {};
        if (path.includes('/api/skills/detect')) {
          return {
            ok: true,
            json: async () => ({
              success: true,
              detected: (opts.detected ?? []).map((id) => ({ id })),
            }),
          };
        }
        if (path.includes('/api/skills/block')) {
          return {
            ok: true,
            json: async () => ({
              success: true,
              block: opts.block ?? `<active_skills>${(body.skill_ids || []).join(',')}</active_skills>`,
              skill_ids: body.skill_ids,
            }),
          };
        }
        return { ok: false, json: async () => ({}) };
      }),
    );
  }

  it('auto-detects when skillPackIds is omitted and always includes biomate-universe', async () => {
    stubSkillsApi({ detected: ['drug-discovery-chemist'] });
    const block = await buildSkillBlock('dock vs EGFR', ['drug_discovery'], {});
    expect(block).toContain(DEFAULT_SKILL_ID);
    expect(block).toContain('drug-discovery-chemist');
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    const blockCall = fetchMock.mock.calls.find(([u]) => String(u).includes('/api/skills/block'));
    expect(JSON.parse(String(blockCall?.[1]?.body)).skill_ids).toEqual([
      DEFAULT_SKILL_ID,
      'drug-discovery-chemist',
    ]);
  });

  it('treats empty skillPackIds as auto-detect (not apply-none)', async () => {
    stubSkillsApi({ detected: ['ml-bioinformatics'] });
    const block = await buildSkillBlock('train a model', ['ml'], { skillPackIds: [] });
    expect(block).toContain('ml-bioinformatics');
    expect(block).toContain(DEFAULT_SKILL_ID);
  });

  it('honours an explicit non-empty selection and still merges the default', async () => {
    stubSkillsApi({});
    const block = await buildSkillBlock('anything', [], {
      skillPackIds: ['clinical-biostatistician'],
    });
    expect(block).toContain(DEFAULT_SKILL_ID);
    expect(block).toContain('clinical-biostatistician');
    const fetchMock = globalThis.fetch as ReturnType<typeof vi.fn>;
    // Must NOT call detect when explicit packs are set.
    expect(fetchMock.mock.calls.some(([u]) => String(u).includes('/api/skills/detect'))).toBe(false);
  });
});
