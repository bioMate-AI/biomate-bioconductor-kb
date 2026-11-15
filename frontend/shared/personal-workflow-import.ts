/**
 * Personal workflow import allowlist (Import Workflow UI + POST /api/workflows/upload-file).
 *
 * BioMate executes imported personal workflows as Nextflow (`file_content` → Batch).
 * Galaxy `.ga` JSON is not convertible / not honest Nextflow — fail-closed: do not offer
 * or accept `.ga` on the import path.
 */
export const ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS: readonly string[] = [
  '.nf',
  '.yml',
  '.yaml',
];

/** Human-readable list for labels / errors (e.g. ".nf, .yml, .yaml"). */
export const PERSONAL_WORKFLOW_ACCEPT_LABEL = ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS.join(', ');

/** HTML file input `accept` value. */
export const PERSONAL_WORKFLOW_ACCEPT_ATTR = ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS.join(',');

export const PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE =
  `Galaxy .ga workflows cannot be imported — BioMate runs Nextflow only. Supported: ${PERSONAL_WORKFLOW_ACCEPT_LABEL}`;

export function personalWorkflowExt(name: string): string {
  const lower = (name || '').toLowerCase();
  const i = lower.lastIndexOf('.');
  if (i < 0) return '';
  return lower.slice(i);
}

export function isAllowedPersonalWorkflowName(name: string): boolean {
  const ext = personalWorkflowExt(name);
  return (ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS as readonly string[]).includes(ext);
}
