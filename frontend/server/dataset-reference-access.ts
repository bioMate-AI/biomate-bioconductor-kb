/** Private dataset refs are resolved through the project file registry, never arbitrary server paths. */
export function projectDatasetKey(ref: unknown, bucket: string): string | null {
  if (typeof ref !== 'string' || /[\x00-\x1f]/.test(ref)) return null;
  let key = ref;
  if (ref.startsWith('s3://')) {
    const match = /^s3:\/\/([^/]+)\/(.+)$/.exec(ref);
    if (!match || !bucket || match[1] !== bucket) return null;
    key = match[2];
  }
  if (!/^projects\/[^/]+\/.+/.test(key) || key.split('/').includes('..')) return null;
  return key;
}

export async function authorizeDatasetReference(
  ref: unknown, userId: unknown, bucket: string,
  canRead: (key: string, userId: string) => Promise<boolean>,
): Promise<{ allowed: true; key: string } | { allowed: false; status: 401 | 403 }> {
  if (!userId) return { allowed: false, status: 401 };
  const key = projectDatasetKey(ref, bucket);
  if (!key || !await canRead(key, String(userId))) return { allowed: false, status: 403 };
  return { allowed: true, key };
}

type QueryFn = (text: string, params?: unknown[]) => Promise<{ rows: any[] }>;

/** The project file a dataset key belongs to, as the profile / rows / datasets proxies see it. */
export interface DatasetFile { id: string; project_id: string; name: string; source: string; current: boolean }

/**
 * The project file whose CURRENT key, or one of whose ARCHIVED VERSION keys, is `key`, in a
 * project `userId` owns or is a member of — else null. Archived versions are readable because
 * an object key is never rewritten (an edit / restore gives the file a new current key and keeps
 * the old bytes as a version): a panel holding the key it opened, Compare and the version views
 * all name version keys, and a member may read every version of a file they can read. Any other
 * key (another project's, a deleted file's — its versions are deleted with it — or an unregistered
 * one) is refused. A current-key match is preferred when a restore made a version key current.
 */
export const DATASET_FILE_SQL = `SELECT f.id::text AS id, f.project_id::text AS project_id, f.name, f.source, (f.s3_key = $1) AS current
  FROM (SELECT id AS file_id FROM project_files WHERE s3_key = $1
        UNION ALL SELECT file_id FROM project_file_versions WHERE s3_key = $1) k
  JOIN project_files f ON f.id = k.file_id
  JOIN projects p ON p.id = f.project_id
  WHERE (p.user_id::text = $2 OR EXISTS (
    SELECT 1 FROM project_members m WHERE m.project_id = p.id AND m.user_id::text = $2
  ))
  ORDER BY (f.s3_key = $1) DESC LIMIT 1`;

export async function findAccessibleDatasetFile(query: QueryFn, key: string, userId: string): Promise<DatasetFile | null> {
  const r = await query(DATASET_FILE_SQL, [key, userId]);
  const row = r.rows[0];
  return row ? { id: String(row.id), project_id: String(row.project_id), name: String(row.name), source: String(row.source), current: Boolean(row.current) } : null;
}

/**
 * Express gate for the dataset proxies (/api/perception/*, /api/datasets/*): the request's ONE
 * dataset reference (body.datasetRef, or the path segment for /api/datasets/:ref/<action>) must
 * resolve to a project file key the user may read (findAccessibleDatasetFile). On success the
 * resolved key and file are attached as req.datasetKey / req.datasetFile for later middleware.
 */
export function datasetAccessGate(deps: { query: QueryFn; bucket: () => string }, refFromPath = false) {
  return async (req: any, res: any, next: () => void) => {
    try {
      const pathname = new URL(req.originalUrl, 'http://internal').pathname;
      const ref = refFromPath
        ? decodeURIComponent(pathname.slice('/api/datasets/'.length, pathname.lastIndexOf('/')))
        : req.body?.datasetRef;
      let file: DatasetFile | null = null;
      const decision = await authorizeDatasetReference(ref, req.user?.id, deps.bucket(), async (key, uid) => {
        file = await findAccessibleDatasetFile(deps.query, key, uid);
        return file !== null;
      });
      if (!decision.allowed) return res.status(decision.status).json({ error: 'Dataset is not accessible to this user' });
      req.datasetKey = decision.key;
      req.datasetFile = file;
      next();
    } catch (error) {
      console.error('[dataset access]', error instanceof Error ? error.message : error);
      res.status(403).json({ error: 'Dataset access could not be verified' });
    }
  };
}
