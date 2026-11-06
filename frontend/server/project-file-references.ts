/**
 * Server-side resolution of chat-selected project-file references.
 *
 * A file the user picks from the chat "Project files" tab arrives on the
 * chat-stream request as a `project_files.id` UUID — NOT a Galaxy dataset id
 * and NOT an s3:// URI. On its own that id cannot be turned into a runnable
 * execution input, and it is not yet authorized against the caller.
 *
 * This module closes that gap without ever trusting a client-supplied URI and
 * without ever substituting a same-named or newer file:
 *
 *   1. Authorize — the caller must be owner or member of the project (the same
 *      gate the GET /api/projects/:id/files list route enforces). This is the
 *      real authorization boundary: `resolveProjectForChat` echoes the client's
 *      projectId with no ownership check, so querying by project_id alone would
 *      leak another user's files (IDOR).
 *   2. Match by EXACT id only, scoped to that project. A reference that is not a
 *      file of the authorized project (cross-project, deleted, unknown) is left
 *      unresolved — the caller keeps it in the "unresolved ids" set and reports
 *      the failure rather than falling back.
 *   3. Stage the file's exact s3_key into the Batch-readable bucket and return
 *      the durable s3_uri, so a *selectable* file is also *runnable*.
 *
 * Dependencies are injected so this is unit-testable without a live DB/S3.
 */

export interface ProjectFileRef {
  id: string;
  name?: string;
}

export interface ResolvedProjectFile {
  /** project_files.id — stable, auditable handle for the exact selected file. */
  id: string;
  name: string;
  type: 'project file';
  projectFileId: string;
  projectId: string;
  s3_key: string;
  /**
   * Durable, Batch-readable s3:// URI produced by staging the exact s3_key.
   * Null only when staging failed at resolution time; downstream then falls
   * back to execute-time staging by filename. It is never fabricated from
   * client input.
   */
  s3_uri: string | null;
}

export interface ProjectFileResolverDeps {
  /** Owner-or-member authorization check for (projectId, uid). */
  isOwnerOrMember: (projectId: string, uid: string) => Promise<boolean>;
  /** Fetch {id, name, s3_key} rows for the given ids, scoped to projectId. */
  queryFilesByIds: (
    projectId: string,
    ids: string[],
  ) => Promise<Array<{ id: string; name: string; s3_key: string }>>;
  /** Copy s3_key into the Batch-readable bucket; resolves to the s3:// URI. */
  stageToBatch: (
    s3Key: string,
    projectId: string,
    fileName: string,
  ) => Promise<string | undefined>;
  /** Optional per-session cache of already-staged URIs, keyed by file id. */
  cacheGet?: (id: string) => string | undefined;
  cacheSet?: (id: string, uri: string) => void;
}

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Resolve the given references to authorized, runnable project-file entries.
 * Returns a Map keyed by the requested id. Ids that do not resolve are simply
 * absent from the map — the caller decides how to report them (never
 * substitute another file).
 */
export async function resolveProjectFileReferences(
  refs: ProjectFileRef[],
  projectId: string | undefined,
  uid: string | undefined,
  deps: ProjectFileResolverDeps,
): Promise<Map<string, ResolvedProjectFile>> {
  const out = new Map<string, ResolvedProjectFile>();

  const ids = [
    ...new Set(
      (refs ?? [])
        .map((ref) => (typeof ref?.id === 'string' ? ref.id.trim() : ''))
        .filter(Boolean),
    ),
  ];
  if (!ids.length || !projectId || !uid) return out;

  // project_files.id is a UUID. Skip non-UUID ids (e.g. Galaxy dataset ids like
  // `f2db41e1fa331b3e`) so a stray id can't turn into a malformed uuid[] cast,
  // and so we never claim to resolve something that structurally cannot be a
  // project file.
  const uuids = ids.filter((id) => UUID_RE.test(id));
  if (!uuids.length) return out;

  // Authorization boundary — must match the file-list route's gate.
  if (!(await deps.isOwnerOrMember(projectId, uid))) return out;

  const rows = await deps.queryFilesByIds(projectId, uuids);
  for (const row of rows) {
    if (!row?.id || !row?.name || !row?.s3_key) continue;
    let s3_uri = deps.cacheGet?.(row.id) ?? null;
    if (!s3_uri) {
      const staged = await deps.stageToBatch(row.s3_key, projectId, row.name);
      if (staged) {
        s3_uri = staged;
        deps.cacheSet?.(row.id, staged);
      }
    }
    out.set(row.id, {
      id: row.id,
      name: row.name,
      type: 'project file',
      projectFileId: row.id,
      projectId,
      s3_key: row.s3_key,
      s3_uri,
    });
  }
  return out;
}
