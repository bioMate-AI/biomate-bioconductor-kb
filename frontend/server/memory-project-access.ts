/**
 * Authorization for the project-scoped /api/memory/projects/:projectId routes.
 * They used to check only that the caller was logged in, so any account that knew a project id
 * could read it, rewrite its instructions (injected into every member's prompt) or set userId and
 * take it over (instruction-panel committee audit 2026-11-12). Reads need membership, writes need
 * owner/editor; unauthorised → 404 (same as /api/projects). "search" is a sibling route registered
 * after :projectId — pass it through (it was shadowed).
 */
export type AccessCheck = (projectId: string, uid: string) => Promise<boolean>;

export function memoryProjectAccess(level: 'member' | 'editor', checks: { member: AccessCheck; editor: AccessCheck }) {
  return async (req: any, res: any, next: any) => {
    if (req.params?.projectId === 'search') return next('route');
    const uid = req.user?.id != null ? String(req.user.id) : '';
    const check = level === 'editor' ? checks.editor : checks.member;
    const ok = !!uid && await check(String(req.params?.projectId || ''), uid).catch(() => false);
    if (!ok) return res.status(404).json({ error: 'Project not found' });
    next();
  };
}

/** Fields a project update may change — never id / userId / timestamps. */
export const MEMORY_PROJECT_UPDATABLE = ['name', 'description', 'researchGoal', 'instructions', 'primaryDomain', 'organisms', 'tissueTypes', 'conditions', 'dataModalities', 'status', 'progress'] as const;

export function memoryProjectUpdate(body: unknown): Record<string, unknown> {
  const b = body && typeof body === 'object' ? body as Record<string, unknown> : {};
  return Object.fromEntries(MEMORY_PROJECT_UPDATABLE.filter((k) => k in b).map((k) => [k, b[k]]));
}
