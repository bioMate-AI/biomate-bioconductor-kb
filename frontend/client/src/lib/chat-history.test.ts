import { describe, it, expect, beforeEach } from 'vitest';
import { chatHistoryService } from './chat-history';

// Self-contained in-memory localStorage shim so this suite does not depend on
// the ambient test environment (jsdom vs node) being configured a particular way.
function installLocalStorageShim() {
  const store = new Map<string, string>();
  const shim = {
    getItem: (k: string) => (store.has(k) ? store.get(k)! : null),
    setItem: (k: string, v: string) => { store.set(k, String(v)); },
    removeItem: (k: string) => { store.delete(k); },
    clear: () => { store.clear(); },
    key: (i: number) => Array.from(store.keys())[i] ?? null,
    get length() { return store.size; },
  };
  (globalThis as any).localStorage = shim;
}

/**
 * Regression: marketing "Start free" handoff (/?q=…) mounts the chat and
 * auto-submits the moment `isAuthenticated` flips true — which can happen
 * BEFORE `user.id` is populated. That early send creates its session under the
 * pre-auth storageKey; when setUserId() later switches the key, the in-flight
 * session must NOT be orphaned (else previousMessages goes out empty and the
 * streamed reply can't attach → empty "BioMate" bubble, no workflow card).
 */
describe('chatHistoryService.setUserId — pre-auth session migration', () => {
  beforeEach(() => {
    installLocalStorageShim();
    localStorage.clear();
  });

  const seededSession = (id: string) => ({
    id,
    title: 'New Chat',
    timestamp: new Date().toISOString(),
    lastActivity: new Date().toISOString(),
    messages: [
      { id: 'welcome', role: 'assistant', content: 'Hello! I\'m BioMate' },
      { id: 'u1', role: 'user', content: 'Run differential expression on AChR+ MG PBMC' },
    ],
    workflows: [],
    datasets: [],
    status: 'active',
  });

  it('migrates a session written under the pre-switch key into the new user key', () => {
    // Establish a known active key (userA), then simulate a write under it.
    const userA = 'userA-' + 'fixture';
    const userB = 'userB-' + 'fixture';
    chatHistoryService.setUserId(userA);
    const keyA = `biomate-chat-history-${userA}`;
    const keyB = `biomate-chat-history-${userB}`;
    const sid = 'chat-preauth-1';
    localStorage.setItem(keyA, JSON.stringify([seededSession(sid)]));

    // The key switch that orphaned the session in the real bug.
    chatHistoryService.setUserId(userB);

    const migrated = JSON.parse(localStorage.getItem(keyB) || '[]');
    expect(migrated.map((s: any) => s.id)).toContain(sid);
    expect(migrated.find((s: any) => s.id === sid).messages).toHaveLength(2);
    // Old bucket is cleared so a later switch can't re-absorb stale rows.
    expect(localStorage.getItem(keyA)).toBeNull();
  });

  it('does not clobber existing sessions already under the new user key', () => {
    const userA = 'userC-fixture';
    const userB = 'userD-fixture';
    chatHistoryService.setUserId(userA);
    const keyA = `biomate-chat-history-${userA}`;
    const keyB = `biomate-chat-history-${userB}`;
    localStorage.setItem(keyA, JSON.stringify([seededSession('chat-orphan')]));
    localStorage.setItem(keyB, JSON.stringify([seededSession('chat-existing')]));

    chatHistoryService.setUserId(userB);

    const ids = JSON.parse(localStorage.getItem(keyB) || '[]').map((s: any) => s.id);
    expect(ids).toContain('chat-existing');
    expect(ids).toContain('chat-orphan');
  });

  it('ignores empty (message-less) sessions in the old key', () => {
    const userA = 'userE-fixture';
    const userB = 'userF-fixture';
    chatHistoryService.setUserId(userA);
    const keyA = `biomate-chat-history-${userA}`;
    const keyB = `biomate-chat-history-${userB}`;
    const empty = { ...seededSession('chat-empty'), messages: [] };
    localStorage.setItem(keyA, JSON.stringify([empty]));

    chatHistoryService.setUserId(userB);

    const ids = JSON.parse(localStorage.getItem(keyB) || '[]').map((s: any) => s.id);
    expect(ids).not.toContain('chat-empty');
  });
});

import { cleanSessionTitle } from './chat-history'
import { it as it2, expect as expect2 } from 'vitest'
it2('cleans legacy titles that captured a raw system block', () => {
  expect2(cleanSessionTitle('[BioMate dataset: epar.jsonl (id:')).toBe('epar.jsonl')
  expect2(cleanSessionTitle('Summarise EPAR [Uploaded datasets: x')).toBe('Summarise EPAR')
  expect2(cleanSessionTitle('Plain title')).toBe('Plain title')
})

it2('derives a new chat title from the user words, never from the [BioMate dataset: …] block', () => {
  installLocalStorageShim();
  localStorage.clear();
  chatHistoryService.setUserId('title-fixture');
  const key = 'biomate-chat-history-title-fixture';
  localStorage.setItem(key, JSON.stringify([{
    id: 'chat-title-1', title: 'New Chat', timestamp: new Date().toISOString(), lastActivity: new Date().toISOString(),
    messages: [], workflows: [], datasets: [], status: 'active',
  }]));
  const updated = chatHistoryService.updateSession('chat-title-1', {
    messages: [
      { id: 'u1', role: 'user', content: '[BioMate dataset: epar.jsonl (id: 1b2c)]\n[Uploaded datasets: epar.jsonl: dataset_id=9]', timestamp: new Date() },
      { id: 'a1', role: 'assistant', content: 'ok', timestamp: new Date() },
    ] as any,
  });
  expect2(updated?.title).toBe('epar.jsonl');
});

/**
 * Round 5 (2026-11-12): "Run full QC" opened a chat that was not filed in the project it was started
 * from. The first send files a still-empty, unfiled chat in the active project, and the session row
 * pushed to the server carries that `project_id`.
 */
describe('chatHistoryService.fileEmptySessionInProject — the chat belongs to the project from its first message', () => {
  beforeEach(() => {
    installLocalStorageShim();
    localStorage.clear();
  });

  it('files an empty unfiled chat; the synced session payload carries project_id', async () => {
    const bodies: any[] = [];
    (globalThis as any).fetch = async (url: string, init?: RequestInit) => {
      if (init?.body) bodies.push({ url, method: init.method, body: JSON.parse(String(init.body)) });
      return { ok: init?.method ? true : false, status: init?.method ? 200 : 404, json: async () => ({}) } as Response;
    };
    chatHistoryService.setUserId('round5-' + Date.now());
    const session = chatHistoryService.createNewSession(null);
    expect((session as any).projectId).toBeUndefined();
    chatHistoryService.setBackendSyncActive(true);
    try {
      chatHistoryService.fileEmptySessionInProject(session.id, 'proj-1');
      chatHistoryService.addMessage(session.id, { id: 'u1', role: 'user', content: 'samples.csv: run QC', timestamp: new Date() } as any);
      expect((chatHistoryService.getSession(session.id) as any).projectId).toBe('proj-1');
      await new Promise((r) => setTimeout(r, 2300));
      const push = bodies.filter((b) => b.body?.session_id === session.id).pop();
      expect(push?.body.project_id).toBe('proj-1');
      expect(push?.body.message_count).toBe(1);
    } finally {
      chatHistoryService.setBackendSyncActive(false);
    }
  }, 10_000);

  it('never moves a chat that already has messages or a project', () => {
    chatHistoryService.setUserId('round5b-' + Date.now());
    const used = chatHistoryService.createNewSession(null);
    chatHistoryService.updateSession(used.id, { title: 'Earlier', messages: [{ id: 'm', role: 'user', content: 'x', timestamp: new Date() } as any] });
    chatHistoryService.fileEmptySessionInProject(used.id, 'proj-1');
    expect((chatHistoryService.getSession(used.id) as any).projectId).toBeUndefined();
    const filed = chatHistoryService.createNewSession('proj-2');
    chatHistoryService.fileEmptySessionInProject(filed.id, 'proj-1');
    expect((chatHistoryService.getSession(filed.id) as any).projectId).toBe('proj-2');
  });
});
