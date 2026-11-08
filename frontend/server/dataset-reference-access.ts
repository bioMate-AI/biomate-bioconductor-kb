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
