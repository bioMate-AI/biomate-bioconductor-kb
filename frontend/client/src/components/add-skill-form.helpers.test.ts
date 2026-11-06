import { describe, it, expect } from 'vitest';
import { skillSlug, buildSkillMarkdown } from './add-skill-form';

describe('skillSlug — backend rule [a-z0-9]+(?:-[a-z0-9]+)*, max 64', () => {
  it('kebab-cases a normal name', () => {
    expect(skillSlug('Oncology report reviewer')).toBe('oncology-report-reviewer');
  });
  it('collapses punctuation/spaces into single hyphens and trims', () => {
    expect(skillSlug('  E3 §2.6 — reviewer!! ')).toBe('e3-2-6-reviewer');
  });
  it('returns "" when nothing usable remains (name required)', () => {
    expect(skillSlug('')).toBe('');
    expect(skillSlug('   ')).toBe('');
    expect(skillSlug('!!!')).toBe('');
  });
  it('matches the backend name regex', () => {
    const slug = skillSlug('My Custom Expert v2');
    expect(slug).toMatch(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);
    expect(slug.length).toBeLessThanOrEqual(64);
  });
});

describe('buildSkillMarkdown — valid frontmatter the backend can parse', () => {
  const base = { slug: 'rev', title: 'Reviewer', description: 'Reviews write-ups', body: 'Do the thing', triggers: [] as string[], domains: [] as string[] };

  it('emits name (bare slug), JSON-quoted title/description, and the body after the fence', () => {
    const md = buildSkillMarkdown(base);
    expect(md.startsWith('---\n')).toBe(true);
    expect(md).toContain('\nname: rev\n');
    expect(md).toContain('title: "Reviewer"');
    expect(md).toContain('description: "Reviews write-ups"');
    expect(md).toContain('domains: []');
    expect(md.trimEnd().endsWith('Do the thing')).toBe(true);
    // exactly two frontmatter fences
    expect(md.match(/^---$/gm)?.length).toBe(2);
  });

  it('a colon or quote in the title can NOT break the YAML line (JSON-encoded scalar)', () => {
    const md = buildSkillMarkdown({ ...base, title: 'Reviewer: "strict" mode', description: 'a: b' });
    expect(md).toContain('title: "Reviewer: \\"strict\\" mode"');
    expect(md).toContain('description: "a: b"');
  });

  it('omits the triggers key when none, includes it as a JSON array when present', () => {
    expect(buildSkillMarkdown(base)).not.toContain('triggers:');
    const md = buildSkillMarkdown({ ...base, triggers: ['oncology', 'E3'], domains: ['clinical'] });
    expect(md).toContain('triggers: ["oncology","E3"]');
    expect(md).toContain('domains: ["clinical"]');
  });

  it('falls back to the slug for title when none given', () => {
    expect(buildSkillMarkdown({ ...base, title: '' })).toContain('title: "rev"');
  });
});
