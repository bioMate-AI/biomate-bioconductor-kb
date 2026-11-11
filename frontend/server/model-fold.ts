/**
 * POST /api/models/fold/plan — run protein structure prediction on OUR OWN AWS
 * Batch (Boltz-2), not NVIDIA's hosted API.
 *
 * The Models panel "Run a model" → structure path used to call NVIDIA's hosted
 * BioNeMo Boltz-2 (`/api/inference`), which is down and off-tenant. We already
 * run Boltz-2 on AWS Batch via the `boltz_structure_prediction` Nextflow
 * workflow (`boltz predict` in our ECR image). This route:
 *   1. validates the input sequence (one protein chain);
 *   2. writes it as a FASTA and stages it to the Batch-readable bucket;
 *   3. returns the workflow launch request (workflow_ga + parameters) the client
 *      submits through the ordinary POST /api/workflows/execute — so the fold is
 *      a tracked run (run record, SSE, Run Manager, billing), exactly like the
 *      training path, and nothing leaves our tenancy.
 * Nothing is executed here.
 */

/** The Batch workflow that folds a sequence with Boltz-2 on our own GPUs. */
export const BOLTZ_FOLD_NEXTFLOW_PATH =
  'nextflow_nfcore/subworkflows/structural_biology/boltz_structure_prediction/main.nf';

// Standard one-letter amino-acid codes (X = unknown is allowed by Boltz).
const AA = /^[ACDEFGHIKLMNPQRSTVWYX]+$/i;
const MIN_LEN = 10;
// Boltz-2 monomer fold on a single Batch GPU. The cofold-bench learned the
// practical ceiling empirically — runs were capped at 1200 true tokens because a
// bigger input OOMs on a 16 GB T4 (the same OOM the 840-residue antibody complex
// hit, docs/20261111_MODELS_PANEL_OWN_EXECUTION.md). The spot GPU queue can still
// place a job on a T4, so we cap at 1000 residues here; a larger fold needs the
// ≥24 GB GPU routing decision first.
const MAX_LEN = 1000;

export interface ModelFoldDependencies {
  /** Write `content` as an object under the Batch bucket and return its s3:// URI
   *  (undefined on failure). The key is server-chosen; never from the client. */
  stageFasta(content: string, basename: string): Promise<string | undefined>;
}

export interface ModelFoldPlan {
  workflow_ga: {
    name: string;
    domain: string;
    nextflow_path: string;
    steps: Record<string, unknown>;
    parameters: Record<string, unknown>;
  };
  nextflow_path: string;
  /** s3:// URI of the staged FASTA (for logging / the run record). */
  input_uri: string;
}

/** Clean + validate a pasted protein sequence: strip FASTA headers/whitespace,
 *  upper-case, and require a plausible single chain. Pure + exported for tests. */
export function cleanSequence(raw: unknown): { seq: string } | { error: string } {
  if (typeof raw !== 'string') return { error: 'A protein sequence is required.' };
  const seq = raw
    .split(/\r?\n/)
    .filter((line) => !line.startsWith('>')) // drop FASTA headers
    .join('')
    .replace(/\s+/g, '')
    .toUpperCase();
  if (!seq) return { error: 'A protein sequence is required.' };
  if (seq.length < MIN_LEN) return { error: `Sequence is too short to fold (min ${MIN_LEN} residues).` };
  if (seq.length > MAX_LEN) {
    return { error: `Sequence has ${seq.length} residues; the single-chain fold supports up to ${MAX_LEN}. For a complex, use a structure-prediction workflow.` };
  }
  if (!AA.test(seq)) return { error: 'Sequence has characters that are not standard amino acids.' };
  return { seq };
}

/** Build the FASTA body for a single query chain. */
export function foldFasta(seq: string): string {
  return `>query\n${seq}\n`;
}

export async function planModelFold(
  input: { userId?: string | null; body: unknown },
  deps: ModelFoldDependencies,
): Promise<{ status: number; body: any }> {
  const userId = input.userId ? String(input.userId) : '';
  if (!userId) return { status: 401, body: { error: 'Authentication required' } };
  const body = (input.body && typeof input.body === 'object' && !Array.isArray(input.body))
    ? (input.body as Record<string, unknown>) : null;
  if (!body) return { status: 400, body: { error: 'Request body must be an object' } };

  const cleaned = cleanSequence(body.sequence);
  if ('error' in cleaned) return { status: 400, body: { error: cleaned.error } };

  const rawName = typeof body.name === 'string' ? body.name.trim() : '';
  const name = (rawName || 'Boltz-2 structure prediction').slice(0, 120);

  let inputUri: string | undefined;
  try {
    inputUri = await deps.stageFasta(foldFasta(cleaned.seq), 'query.fasta');
  } catch {
    inputUri = undefined;
  }
  if (!inputUri || !inputUri.startsWith('s3://')) {
    return { status: 502, body: { error: 'Could not stage the sequence for folding. No run was started.' } };
  }

  const plan: ModelFoldPlan = {
    workflow_ga: {
      name,
      domain: 'structural_biology',
      nextflow_path: BOLTZ_FOLD_NEXTFLOW_PATH,
      steps: {}, // lazily fetched by the viewer from /api/nextflow/steps
      parameters: {
        input_fasta: inputUri,
        output_format: 'mmcif',
        use_msa_server: true,
        sampling_steps: 200,
        recycling_steps: 3,
      },
    },
    nextflow_path: BOLTZ_FOLD_NEXTFLOW_PATH,
    input_uri: inputUri,
  };
  return { status: 200, body: plan };
}
