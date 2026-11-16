import { z } from 'zod';
import { dataScopeSchema, versionedParametersSchema } from '@shared/schema';
import { decideRunAccess, type AccessControlledRun } from './run-access';

export interface LegacyAccessibleRun extends AccessControlledRun { id: string }
export interface LegacyRunAccessDependencies {
 resolveRun(id: string): Promise<LegacyAccessibleRun | undefined>;
 getUserProjects(userId: string): Promise<Array<{ id?: string | null }> | undefined>;
}
/** Attach the authorized record and normalize aliases before any legacy handler
 * can call a privileged backend or mutate storage. Unknown raw IDs fail closed. */
export function createLegacyRunGuard(deps: LegacyRunAccessDependencies, access: 'read' | 'write', parameter = 'id') {
 return async (req: any, res: any, next: () => void) => {
  const userId = req.user?.id ? String(req.user.id) : null;
  if (!userId) return res.status(401).json({ error: 'Authentication required' });
  try {
   const run = await deps.resolveRun(req.params[parameter]);
   if (!run) return res.status(404).json({ error: 'Run not found' });
   if (access === 'write') {
    if (!run.userId || String(run.userId) !== userId) return res.status(403).json({ error: 'Only the run owner may modify or restart this run' });
   } else {
    const decision = await decideRunAccess(run, userId, deps.getUserProjects);
    if (!decision.allowed) return res.status(decision.status).json({ error: decision.error });
   }
   req.authorizedLegacyRun = run;
   req.params[parameter] = run.id;
   return next();
  } catch { return res.status(503).json({ error: 'Run access could not be verified' }); }
 };
}
/** Prevent owned-run metadata edits from forging output registrations, execution
 * status, ownership, or trusted training launch snapshots. */
export const legacyRunUpdateSchema = z.object({
 parameters: versionedParametersSchema.optional(),
 dataScope: dataScopeSchema.optional(),
 // User-editable display label only. Owner-gated by createLegacyRunGuard('write');
 // never a path/status/ownership field, so it cannot forge the records above.
 workflowName: z.string().trim().min(1).max(200).optional(),
}).strict();
