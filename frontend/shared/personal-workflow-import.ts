/**
 * Personal workflow import allowlist (Import Workflow UI + POST /api/workflows/upload-file).
 *
 * BioMate executes imported personal workflows as Nextflow (`file_content` → Batch).
 * Galaxy `.ga` is temporarily disabled until honest Galaxy-engine (or conversion) exists.
 *
 * Re-enable: flip `GA_IMPORT_ENABLED` to `true` (one change — UI accept, labels, API).
 */
/** TODO: re-enable when .ga execution is supported */
export const GA_IMPORT_ENABLED = false;

const NEXTFLOW_PERSONAL_WORKFLOW_EXTENSIONS: readonly string[] = [
  '.nf',
  '.yml',
  '.yaml',
];

// Commented out until GA_IMPORT_ENABLED — keep visible for one-flip restore:
// '.ga', // TODO: re-enable when .ga execution is supported

export const ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS: readonly string[] = GA_IMPORT_ENABLED
  ? [...NEXTFLOW_PERSONAL_WORKFLOW_EXTENSIONS, '.ga']
  : NEXTFLOW_PERSONAL_WORKFLOW_EXTENSIONS;

/** Human-readable list for labels / errors (e.g. ".nf, .yml, .yaml"). */
export const PERSONAL_WORKFLOW_ACCEPT_LABEL = ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS.join(', ');

/** HTML file input `accept` value. */
export const PERSONAL_WORKFLOW_ACCEPT_ATTR = ALLOWED_PERSONAL_WORKFLOW_EXTENSIONS.join(',');

export const PERSONAL_WORKFLOW_UNSUPPORTED_MESSAGE = GA_IMPORT_ENABLED
  ? `Only ${PERSONAL_WORKFLOW_ACCEPT_LABEL} workflow files are supported`
  : `Galaxy .ga workflows cannot be imported yet — BioMate runs Nextflow only (temporary). Supported: ${PERSONAL_WORKFLOW_ACCEPT_LABEL}`;

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
