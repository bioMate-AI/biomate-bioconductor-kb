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
