import { describe, it, expect, beforeEach } from 'vitest';
import { starredWorkflowsService } from './starred-workflows';
import { recentToolsService } from './recent-tools';
import { projectService } from './projects';

// Self-contained in-memory localStorage shim so this suite does not depend on
// the ambient environment having a particular localStorage configured.
function installLocalStorageShim() {
  const store = new Map<string, string>();
  (globalThis as any).localStorage = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => { store.set(k, String(v)); },
    removeItem: (k: string) => { store.delete(k); },
    clear: () => { store.clear(); },
    key: (i: number) => Array.from(store.keys())[i] ?? null,
    get length() { return store.size; },
  };
}

/**
 * Honest empty-state contract (fix for "mock-as-real" UI bug).
 *
 * None of these services may fabricate demo data and present it as the user's
 * own. When nothing is stored, each must return an EMPTY list so the UI shows
 * its honest "nothing yet" empty state — never seeded example rows.
 */
describe('honest empty-state: no fabricated demo data served as real', () => {
  beforeEach(() => {
    installLocalStorageShim();
    localStorage.clear();
  });

  it('starredWorkflowsService.getAllStarred() returns [] when unseeded (no demo stars)', () => {
    const starred = starredWorkflowsService.getAllStarred();
    expect(Array.isArray(starred)).toBe(true);
    expect(starred).toHaveLength(0);
    // Guard against the removed fabricated defaults sneaking back.
    expect(starred.some(w => w.id?.startsWith('starred-default'))).toBe(false);
  });

  it('recentToolsService.getAllRecent() returns [] when unseeded (no demo tools)', () => {
    const recent = recentToolsService.getAllRecent();
    expect(Array.isArray(recent)).toBe(true);
    expect(recent).toHaveLength(0);
    expect(recent.some(t => t.id?.startsWith('recent-default'))).toBe(false);
  });

  it('projectService.getAllProjects() returns [] when unseeded (no demo projects)', () => {
    const projects = projectService.getAllProjects();
    expect(Array.isArray(projects)).toBe(true);
    expect(projects).toHaveLength(0);
    expect(projects.some(p => p.id?.startsWith('project-demo'))).toBe(false);
  });

  it('services still return genuinely stored rows (empty-state fix did not break persistence)', () => {
    const star = starredWorkflowsService.starWorkflow({
      workflowId: 'wf-real-1',
      title: 'Real starred workflow',
      description: 'added by the user',
      workflowType: 'RNA-seq',
      complexity: 'simple',
    } as any);
    expect(star.workflowId).toBe('wf-real-1');
    const all = starredWorkflowsService.getAllStarred();
    expect(all).toHaveLength(1);
    expect(all[0].workflowId).toBe('wf-real-1');

    const tool = recentToolsService.addRecentTool({
      toolId: 'tool-real-1',
      name: 'Real tool',
      description: 'used by the user',
      category: 'quality-control',
      complexity: 'simple',
    } as any);
    expect(tool.toolId).toBe('tool-real-1');
    expect(recentToolsService.getAllRecent()).toHaveLength(1);
  });
});
