import path from 'node:path';
import { realpathSync } from 'node:fs';
const realOrResolved = (value: string): string => {
  try { return realpathSync(value); } catch { return path.resolve(value); }
};

/** File access must be bound to the authorized run, not merely to a shared bucket or /tmp. */
export function isRunFilePathAllowed(filePath: string, run: any, canonicalOutputs: unknown[] = []): boolean {
  if (!filePath || filePath.includes('\0') || filePath.split(/[\\/]/).includes('..')) return false;
  const refs = new Set<string>();
  const visit = (value: unknown): void => {
    if (typeof value === 'string') {
      if (value.startsWith('s3://') || path.isAbsolute(value)) refs.add(value);
    } else if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') Object.values(value).forEach(visit);
  };
  visit(run?.execution?.outputs);
  visit(run?.execution?.nextflowStatus?.s3_output_files);
  visit(canonicalOutputs);
  if (filePath.startsWith('s3://')) return refs.has(filePath);
  // Bare filenames are resolved by the authorized run's Galaxy output list below.
  if (!filePath.includes('/') && !filePath.includes('\\')) return true;
  const resolved = path.resolve(filePath);
  const realFile = realOrResolved(resolved);
  if (refs.has(resolved) && realFile === resolved) return true;
  const status = run?.execution?.nextflowStatus;
  return [status?.work_dir, status?.outdir].some(root => {
    if (typeof root !== 'string' || !path.isAbsolute(root)) return false;
    const normalized = path.resolve(root);
    // These shared directories are not a run-specific authorization boundary.
    if (['/', '/tmp', '/tmp/nextflow_runs', '/app/nf-work'].includes(normalized)) return false;
    const relative = path.relative(realOrResolved(normalized), realFile);
    return relative !== '' && !relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative);
  });
}
