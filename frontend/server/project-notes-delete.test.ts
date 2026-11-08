import { afterAll, beforeAll, beforeEach, expect, it, vi } from 'vitest';
let user: string | null = 'owner'; let memberRole = ''; let rows: any[] = [];
const query = vi.fn(async (sql: string, args: any[] = []) => {
 if (sql.includes('FROM project_members')) return { rows: memberRole ? [{ role: memberRole }] : [] };
 if (sql.startsWith('DELETE FROM project_knowledge')) { const found = rows.filter(r => r.id === args[0] && r.project_id === args[1] && r.knowledge_type === args[2]); rows = rows.filter(r => !found.includes(r)); return { rows: found }; }
 return { rows: [] };
});
vi.mock('./db', () => ({ pool: { query: (...args: any[]) => query(...args as [string, any[]]) } }));
vi.mock('./auth-middleware', () => ({ authenticateToken: (_req: any, _res: any, next: any) => next() }));
vi.mock('./memory-repository', () => ({ memoryService: { projects: { getProject: async () => ({ userId: 'owner' }) }, ensureLtmUser: async () => {} } }));
vi.mock('./s3-client', () => ({ s3Service: {} }));
let handler: any;
beforeAll(async () => {
 const { registerProjectRoutes } = await import('./project-routes');
 const app = Object.fromEntries(['get', 'post', 'patch', 'delete', 'put'].map(method => [method, (path: string, ...handlers: any[]) => { if (method === 'delete' && path === '/api/projects/:id/notes-list/:noteId') handler = handlers.at(-1); }]));
 registerProjectRoutes(app as any);
});
beforeEach(() => { user = 'owner'; memberRole = ''; rows = [{ id: 12, project_id: 'p', knowledge_type: 'user_notes' }, { id: 13, project_id: 'p', knowledge_type: 'notes_synthesis' }, { id: 14, project_id: 'other', knowledge_type: 'user_notes' }]; query.mockClear(); });
async function remove(id: number) {
 const response: any = { status: 200 }; const res: any = { status: (status: number) => { response.status = status; return res; }, json: (body: any) => { response.body = body; return res; } };
 await handler({ params: { id: 'p', noteId: String(id) }, user: user ? { id: user } : undefined }, res);
 return response;
}
it('deletes only the addressed human note, with project and type isolation', async () => { expect((await remove(12)).status).toBe(200); expect(rows.map(r => r.id)).toEqual([13,14]); expect((await remove(13)).status).toBe(404); expect((await remove(14)).status).toBe(404); });
it('denies anonymous, outsider and reader mutations before deletion', async () => { user = null; expect((await remove(12)).status).toBe(401); user = 'outsider'; expect((await remove(12)).status).toBe(404); memberRole = 'viewer'; expect((await remove(12)).status).toBe(404); expect(rows).toHaveLength(3); });
it('allows an authorized editor and reports persistence errors without deleting', async () => { user = 'editor'; memberRole = 'editor'; expect((await remove(12)).status).toBe(200); query.mockRejectedValueOnce(new Error('db unavailable')); expect((await remove(14)).status).toBe(500); expect(rows).toHaveLength(2); });
