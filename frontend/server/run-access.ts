/**
 * Authorization policy for execution-run data and artifacts.
 *
 * Run IDs are not a credential.  A caller may access a run when they own it,
 * or when the run belongs to a project of which they are a member.  Keep this
 * small policy separate from route plumbing so every output/findings surface
 * applies exactly the same rule.
 */
export interface AccessControlledRun {
  userId?: string | null;
  projectId?: string | null;
}

export type RunAccessDecision =
  | { allowed: true; via: "owner" | "project_member" }
  | { allowed: false; status: 401 | 403; error: string };

export async function decideRunAccess(
  run: AccessControlledRun,
  userId: string | null | undefined,
  getUserProjects?: (userId: string) => Promise<Array<{ id?: string | null }> | undefined>,
): Promise<RunAccessDecision> {
  if (!userId) {
    return { allowed: false, status: 401, error: "Authentication required" };
  }

  if (run.userId && String(run.userId) === String(userId)) {
    return { allowed: true, via: "owner" };
  }

  if (run.projectId && getUserProjects) {
    try {
      const projects = await getUserProjects(userId);
      if (Array.isArray(projects) && projects.some((p) => String(p?.id) === String(run.projectId))) {
        return { allowed: true, via: "project_member" };
      }
    } catch {
      // Fail closed when membership lookup is unavailable.
    }
  }

  return {
    allowed: false,
    status: 403,
    error: "Forbidden — run is not owned by current user and you are not a member of its project",
  };
}
