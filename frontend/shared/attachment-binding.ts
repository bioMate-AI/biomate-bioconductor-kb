/**
 * Binding attached files to workflow inputs.
 *
 * A chat message that carries uploads ends with the client-appended blocks
 *
 *   [Attached files: 6Z43.pdb, nanobody_candidates.fasta]
 *   [Uploaded datasets: 6Z43.pdb: dataset_id=…, galaxy_dataset_id=…, s3_uri=…; …]
 *
 * Those files must end up bound to the chosen workflow's file inputs. The
 * pre-existing mapping (`extractUploadedFileParams` in server/galaxy-assistant)
 * is name-based only: it knows a fixed list of canonical parameter names
 * (samplesheet / matrix / reads / …) and a fixed list of filename patterns. A
 * workflow whose input is called `input_smiles`, `ligand_file`, `structure` …
 * never received the upload, so the panel showed its required input unbound
 * while the user had attached exactly the right file.
 *
 * This module binds by the SCHEMA instead (rule-first, per CLAUDE.md's hybrid
 * extraction rule — no LLM needed for this): a parameter is a candidate only
 * when it really is a file/path parameter, and a file is a candidate for it
 * only when the file's extension matches the kind of data the parameter's
 * name / label / description asks for.
 *
 * Pure module (no I/O, no React, no node APIs) — used by the server binding
 * chokepoint and by the client's clarification bridge.
 */

export interface AttachedFile {
  /** File name as the user sees it, e.g. "bace_assays.csv". */
  name: string;
  datasetId?: string;
  galaxyDatasetId?: string;
  s3Uri?: string;
}

/** A workflow parameter as the backend describes it in workflow_ga. */
export interface BindableParam {
  name?: string;
  label?: string;
  description?: string;
  type?: string;
  /** nf-core JSON-schema format, e.g. "file-path". */
  format?: string;
  mimetype?: string;
  /** Backend flag for files the workflow reads. */
  data_input?: boolean;
  required?: boolean;
  value?: unknown;
  default?: unknown;
  defaultValue?: unknown;
}

export interface AttachmentBinding {
  /** Parameter name the file is bound to. */
  param: string;
  /** The (first) file bound to it. */
  file: AttachedFile;
  /** Every file bound to it — more than one only for list/multi-file params. */
  files: AttachedFile[];
  /** The reference(s) the executor resolves, comma-separated for a list param. */
  value: string;
  score: number;
  /** Why this pair was chosen — logged, never shown to the user. */
  reason: string;
}

// ──────────────────────────────────────────────────────────────────────────
// Parsing the message blocks
// ──────────────────────────────────────────────────────────────────────────

/**
 * Every file the user attached to this message, with its dataset references
 * when the upload succeeded. Files named in `[Attached files: …]` but absent
 * from `[Uploaded datasets: …]` are returned WITHOUT references — the caller
 * still knows data was attached (so it must not claim the data was used).
 */
export function parseAttachedFiles(message: string): AttachedFile[] {
  const out: AttachedFile[] = [];
  const byName = new Map<string, AttachedFile>();
  const text = String(message || '');

  for (const block of text.matchAll(/\[Uploaded datasets?:\s*([^\]]+)\]/gi)) {
    for (const entry of block[1].split(/;\s*/)) {
      const name = entry.match(/^([^:]+):/)?.[1]?.trim();
      if (!name) continue;
      const file: AttachedFile = {
        name,
        datasetId: entry.match(/(?:^|[\s,])dataset_id=([A-Za-z0-9-]+)/i)?.[1],
        galaxyDatasetId: entry.match(/galaxy_dataset_id=([A-Za-z0-9-]+)/i)?.[1],
        s3Uri: entry.match(/s3_uri=((?:s3|gs|https?):\/\/[^\s,;\]]+)/i)?.[1],
      };
      if (!byName.has(name.toLowerCase())) {
        byName.set(name.toLowerCase(), file);
        out.push(file);
      }
    }
  }

  for (const block of text.matchAll(/\[Attached files?:\s*([^\]]+)\]/gi)) {
    for (const raw of block[1].split(/,\s*/)) {
      const name = raw.trim();
      if (!name || byName.has(name.toLowerCase())) continue;
      const file: AttachedFile = { name };
      byName.set(name.toLowerCase(), file);
      out.push(file);
    }
  }
  return out;
}

/**
 * Every file attached anywhere in a conversation, newest message first (so the
 * most recent attachment wins when two turns attached files with the same name).
 */
export function attachedFilesFromMessages(
  messages: ReadonlyArray<{ role?: string; content?: unknown }>,
): AttachedFile[] {
  const out: AttachedFile[] = [];
  const seen = new Set<string>();
  for (let i = (messages?.length ?? 0) - 1; i >= 0; i--) {
    const m = messages[i];
    if (m?.role && m.role !== 'user') continue;
    if (typeof m?.content !== 'string') continue;
    for (const f of parseAttachedFiles(m.content)) {
      const key = f.name.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(f);
    }
  }
  return out;
}

/** The reference value the executor resolves for this file, if any. */
export function attachmentRefValue(file: AttachedFile): string | undefined {
  return file.s3Uri || file.datasetId || file.galaxyDatasetId || undefined;
}

/**
 * Resolve a param value back to a co-attached file when the value is that
 * file's bare name, s3:// URI, dataset id, or a staged basename that ends
 * with `_<original_name>` (e.g. `e252cce1b1_nanobody_constraints.json`).
 */
export function resolveAttachedFileForValue(
  value: unknown,
  files: readonly AttachedFile[],
): AttachedFile | undefined {
  if (typeof value !== 'string') return undefined;
  const v = value.trim();
  if (!v) return undefined;
  const lower = v.toLowerCase();
  const slash = lower.lastIndexOf('/');
  const basename = slash >= 0 ? lower.slice(slash + 1) : lower;
  for (const f of files) {
    const name = f.name.trim().toLowerCase();
    if (!name) continue;
    if (lower === name) return f;
    if (f.s3Uri && f.s3Uri.trim().toLowerCase() === lower) return f;
    if (f.datasetId && f.datasetId.trim().toLowerCase() === lower) return f;
    if (f.galaxyDatasetId && f.galaxyDatasetId.trim().toLowerCase() === lower) return f;
    if (basename === name || basename.endsWith(`_${name}`)) return f;
  }
  return undefined;
}

/** Lower-case extension without the `.gz`/`.bz2` wrapper ("reads_R1.fastq.gz" → "fastq"). */
export function fileExtension(name: string): string {
  const base = String(name || '').trim().toLowerCase().replace(/\.(gz|bz2|zip|xz)$/, '');
  const dot = base.lastIndexOf('.');
  return dot > 0 ? base.slice(dot + 1) : '';
}

// ──────────────────────────────────────────────────────────────────────────
// Kinds: what a file holds vs what a parameter asks for
// ──────────────────────────────────────────────────────────────────────────

type Kind =
  | 'structure' | 'sequence' | 'reads' | 'alignment' | 'variants'
  | 'chemistry' | 'table' | 'config' | 'matrix' | 'intervals' | 'image';

/** Extensions that can satisfy a parameter of this kind. */
const KIND_EXTENSIONS: Record<Kind, readonly string[]> = {
  structure: ['pdb', 'cif', 'mmcif', 'ent', 'pdbqt'],
  sequence: ['fasta', 'fa', 'faa', 'fna', 'fsa', 'seq', 'txt'],
  reads: ['fastq', 'fq'],
  alignment: ['bam', 'cram', 'sam'],
  variants: ['vcf', 'bcf'],
  // A compound/SMILES input is routinely supplied as a table or a chemistry file.
  chemistry: ['smi', 'smiles', 'sdf', 'mol', 'mol2', 'csv', 'tsv', 'txt'],
  table: ['csv', 'tsv', 'txt', 'tab', 'xlsx'],
  config: ['json', 'yaml', 'yml', 'toml', 'ini', 'cfg'],
  matrix: ['csv', 'tsv', 'txt', 'h5', 'h5ad', 'loom', 'mtx', 'rds'],
  intervals: ['bed', 'gtf', 'gff', 'gff3', 'saf'],
  image: ['mrc', 'tif', 'tiff', 'png', 'jpg', 'svs', 'ndpi'],
};

/** Parameter-text signals for each kind. */
const KIND_PARAM_RE: Record<Kind, RegExp> = {
  structure: /\b(structure|pdb|mmcif|receptor|apo|holo|complex|crystal|conformer)\b/i,
  sequence: /\b(fasta|sequences?|antibod\w*|nanobod\w*|peptides?|proteins?|antigen|epitope|aa_seq|amino.?acid|genome_fasta|reference_fasta|query|subject)\b/i,
  reads: /\b(reads?|fastq|read1|read2|r1|r2|sequencing_data)\b/i,
  alignment: /\b(bam|cram|sam|alignments?)\b/i,
  variants: /\b(vcf|variants?|genotypes?)\b/i,
  chemistry: /\b(smiles|ligands?|compounds?|molecules?|chem\w*|library|scaffold|drugs?|mols?|inhibitors?)\b/i,
  table: /\b(csv|tsv|table|sheet|samplesheet|metadata|assays?|design|contrasts?|clinical|annotations?|manifest|dataset|data)\b/i,
  config: /\b(config\w*|constraints?|settings|spec|schema|params_file|yaml|json)\b/i,
  matrix: /\b(matrix|matrices|counts?|expression|abundance|h5ad|anndata|adata)\b/i,
  intervals: /\b(bed|gtf|gff|intervals?|regions?|targets_bed|gene_model|annotation_gtf)\b/i,
  image: /\b(images?|micrographs?|movies?|tiff?|slides?|wsi|mrc)\b/i,
};

const ALL_KINDS = Object.keys(KIND_PARAM_RE) as Kind[];

function paramText(p: BindableParam): string {
  return `${p.name || ''} ${p.label || ''} ${p.description || ''}`;
}

/** The kinds of data this parameter asks for, from its name/label/description. */
export function paramKinds(p: BindableParam): Kind[] {
  const text = paramText(p).replace(/_/g, ' ');
  return ALL_KINDS.filter((k) => KIND_PARAM_RE[k].test(text));
}

/** Inline content (a JSON blob, a SMILES string, a sequence) — never a path. */
function defaultLooksInline(p: BindableParam): boolean {
  const d = p.default ?? p.defaultValue;
  if (typeof d !== 'string') return false;
  const s = d.trim();
  if (!s) return false;
  if (s.startsWith('[') || s.startsWith('{')) return true;
  // A value with no path separator and no file extension is a literal, not a path.
  return !s.includes('/') && !/\.[A-Za-z0-9]{2,6}$/.test(s);
}

const FILE_WORD_RE =
  /\b(file|files|filename|filepath|path|paths?|directory|folder|csv|tsv|fasta|fastq|bam|cram|vcf|bed|gtf|gff|sdf|smi|pdb|mmcif|h5ad|json file|yaml file|samplesheet|sheet|manifest|upload(ed)?)\b/i;

/**
 * True when a parameter takes a FILE the user supplies — the only kind an
 * attachment may be bound to.
 *
 * Schema metadata decides it when present (`type: 'file'`, nf-core
 * `format: file-path` / `mimetype`, the backend's `data_input` flag). For the
 * plain strings a `.nf` parse produces, the evidence has to come from the text:
 * `params.input_smiles = null  // path to SMILES file (one "SMILES id" per line)`
 * is a file input; `params.reference_smiles = 'CC(=O)Nc1ccc(O)cc1'` is not, and
 * `params.antibodies = '[{"id": …}]'` is inline content, not a path.
 */
export function isFilePathParam(p: BindableParam): boolean {
  const name = String(p.name || '').trim();
  if (!name || name.startsWith('__')) return false;
  // Base type with any list suffix removed: a multi-file input declares itself
  // as "file[]" (e.g. SNF/MOFA2 `omics`), which is still a file parameter — the
  // per-file assembly below binds every attachment to it.
  const baseType = String(p.type || '').toLowerCase().replace(/\[\]$/, '');
  if (baseType === 'file' || p.data_input === true) return true;
  if (p.format === 'file-path' || !!p.mimetype) return true;
  if (p.type && !['string', 'text', 'path'].includes(baseType)) return false;
  if (defaultLooksInline(p)) return false;
  if (/_(file|path|dir|sheet|csv|tsv|fasta|fastq|bam|vcf|json)$/i.test(name)) return true;
  if (FILE_WORD_RE.test(paramText(p).replace(/_/g, ' '))) return true;
  const d = p.default ?? p.defaultValue;
  return typeof d === 'string' && d.includes('/') && /\.[A-Za-z0-9]{2,6}$/.test(d);
}

/**
 * Bundle documentation and provenance shipped alongside the data (README.md,
 * provenance.json, checksums.json). They describe the bundle; they are never a
 * workflow input.
 */
export function isNonInputAttachment(file: AttachedFile): boolean {
  const n = String(file?.name || '').toLowerCase();
  return /^(readme|license|licence|notice|changelog|notes|demo_notes)\b/.test(n)
    || /^(provenance|checksums|checksum|manifest_sha|md5sums)\.(json|txt|csv|yaml|yml)$/.test(n);
}

/**
 * Evaluation truth that must never be fed back in as a feature
 * (ground_truth.csv, true_drivers.csv, an answer key…). Binding one silently
 * would leak the answer into the analysis, so it is bound only to a parameter
 * that explicitly asks for truth labels.
 */
export function isEvaluationTruthAttachment(file: AttachedFile): boolean {
  const n = String(file?.name || '').toLowerCase();
  return /\b(ground[_-]?truth|true[_-]?(drivers?|labels?|values?|clusters?)|answer[_-]?key|gold[_-]?standard)\b/.test(n)
    || /^(truth|labels)\.[a-z0-9]+$/.test(n);
}

/** A parameter that really does ask for the evaluation truth. */
const TRUTH_PARAM_RE = /\b(truth|gold|answer[_-]?key|reference[_-]?labels?|known[_-]?(drivers?|labels?))\b/i;

/**
 * A parameter that takes SEVERAL files — e.g. MOFA2's `omics`, "one
 * features×samples CSV per modality". Each matching attachment is bound, as the
 * comma-separated list the panel and the executor already read for list params.
 */
export function paramAcceptsMultipleFiles(p: BindableParam): boolean {
  const type = String(p.type || '').toLowerCase();
  if (type.endsWith('[]') || /\b(list|array|multiple|multi)\b/.test(type)) return true;
  const text = paramText(p);
  if (/\b(comma[- ]separated|list of|one or more|multiple files|several files|each (modality|layer|omic|assay|view|block))\b/i.test(text)) return true;
  if (/\bone\b[^.]{0,60}\bper\s+(modality|layer|omic\w*|assay|view|block|dataset|cohort)\b/i.test(text)) return true;
  return /^(omics|views|blocks|layers|modalities|matrices|inputs|input_files|files|datasets)$/i.test(String(p.name || ''));
}

/** Output locations and run metadata are never bound to an attachment. */
const NON_INPUT_PARAM_RE = /^(outdir|out_dir|output_dir|output|publish_dir|publish_dir_mode|work_dir|tracedir|email|email_on_fail|multiqc_title|hook_url)$/i;

function isBound(v: unknown): boolean {
  if (v === undefined || v === null) return false;
  if (Array.isArray(v)) return v.length > 0;
  return String(v).trim() !== '';
}

/** Words that say nothing about which input a file belongs to. */
const TOKEN_STOPLIST = new Set(['the', 'and', 'for', 'with', 'file', 'files', 'data', 'input', 'output', 'final', 'new', 'raw']);

function tokens(s: string): string[] {
  return String(s || '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length >= 3 && !TOKEN_STOPLIST.has(t))
    // crude singularisation so "ligands.sdf" overlaps "ligand_file"
    .map((t) => (t.length > 4 && t.endsWith('s') && !t.endsWith('ss') ? t.slice(0, -1) : t));
}

/**
 * Optional parameters that override a pipeline/genome default (reference FASTA,
 * GTF, blacklist, adapters…). The user's attachment must not silently replace a
 * reference just because the extensions line up — only a filename that names the
 * parameter is accepted for these.
 */
const REFERENCE_OVERRIDE_RE =
  /\b(reference|igenomes|genome|gtf|gff|annotation|blacklist|rrna|adapters?|primer|whitelist|background|decoy)\b/i;

/** The minimum score a (param, file) pair needs before it is bound. */
export const BIND_SCORE_THRESHOLD = 4;

/**
 * Score one (param, file) pair. 0 means "never bind this pair".
 * Exported for tests and for the clarification bridge (single-param case).
 */
export function scoreBinding(
  param: BindableParam,
  file: AttachedFile,
): { score: number; reason: string; overlap: boolean } {
  const name = String(param.name || '');
  if (!name || NON_INPUT_PARAM_RE.test(name)) return { score: 0, reason: 'not an input param', overlap: false };
  if (!isFilePathParam(param)) return { score: 0, reason: 'not a file parameter', overlap: false };
  const ext = fileExtension(file.name);
  if (!ext) return { score: 0, reason: 'file has no extension', overlap: false };
  // Bundle documentation is never an input; evaluation truth only goes to a
  // parameter that asks for it (never as a feature layer).
  if (isNonInputAttachment(file)) return { score: 0, reason: 'bundle documentation', overlap: false };
  if (isEvaluationTruthAttachment(file) && !TRUTH_PARAM_RE.test(paramText(param).replace(/_/g, ' '))) {
    return { score: 0, reason: 'evaluation truth — not an input feature', overlap: false };
  }

  const kinds = paramKinds(param);
  const matched = kinds.filter((k) => KIND_EXTENSIONS[k].includes(ext));
  const asksForAKind = kinds.length > 0;
  // A parameter that names a data kind but NOT this file's kind is a hard no:
  // a .pdb must never land in a SMILES input.
  if (asksForAKind && matched.length === 0) {
    return { score: 0, reason: `kind mismatch (${kinds.join('/')} vs .${ext})`, overlap: false };
  }

  // A parameter the schema itself types as a file ("omics", type: file, no
  // descriptive text) is a declared data input: any real data file may go
  // there. A plain string that merely looks path-ish needs the kind match.
  // Base type with any list suffix removed, so a multi-file input declared as
  // "file[]" (SNF/MOFA2 `omics`) scores as a typed file too — matching the
  // isFilePathParam baseType fix (8edfc2); otherwise an OPTIONAL file[] input
  // lost the +1 and could fall below the bind threshold.
  const baseType = String(param.type || '').toLowerCase().replace(/\[\]$/, '');
  const typedAsFile = baseType === 'file' || param.data_input === true || param.format === 'file-path';
  let score = asksForAKind ? 4 : typedAsFile ? 3 : 2;
  const reasons: string[] = asksForAKind ? [`kind ${matched.join('/')}`] : ['declared file input'];

  const text = paramText(param).toLowerCase();
  if (new RegExp(`\\b${ext}\\b`).test(text)) { score += 3; reasons.push(`mentions .${ext}`); }
  if (param.required) { score += 2; reasons.push('required'); }
  if (typedAsFile) { score += 1; reasons.push('typed as file'); }
  const nameTokens = new Set(tokens(name + ' ' + (param.label || '')));
  // Compare the file's STEM: a shared extension ("my_transcripts.fasta" vs the
  // `fasta` genome-reference param) is not the filename naming the parameter.
  const shared = tokens(file.name.replace(/\.[^.]+$/, '')).filter((t) => nameTokens.has(t));
  if (shared.length > 0) { score += 2; reasons.push(`name overlap ${shared.join(',')}`); }

  // A reference/genome override is only bound when the file names it.
  if (!param.required && shared.length === 0 && param.data_input !== true &&
      REFERENCE_OVERRIDE_RE.test(paramText(param))) {
    return { score: 0, reason: 'optional reference override, filename does not name it', overlap: false };
  }

  return { score, reason: reasons.join('; '), overlap: shared.length > 0 };
}

/** Highest-scoring co-attached file that may bind to this param, if any. */
export function bestAttachmentForParam(
  param: BindableParam,
  files: readonly AttachedFile[],
): { file: AttachedFile; score: number; reason: string } | undefined {
  let best: { file: AttachedFile; score: number; reason: string } | undefined;
  for (const f of files) {
    if (!attachmentRefValue(f)) continue;
    const { score, reason } = scoreBinding(param, f);
    if (score < BIND_SCORE_THRESHOLD) continue;
    if (!best || score > best.score) best = { file: f, score, reason };
  }
  return best;
}

/**
 * Bind attached files to the workflow's unbound file parameters.
 *
 * Greedy highest-score-first, one file per parameter and one parameter per
 * file. Parameters that already carry a value are left alone, as are files
 * that have no dataset reference (a failed upload cannot be bound).
 */
export function bindAttachmentsToParams(
  files: readonly AttachedFile[],
  params: readonly BindableParam[],
): AttachmentBinding[] {
  const usableFiles = files.filter((f) => !!attachmentRefValue(f));
  if (usableFiles.length === 0) return [];
  const candidates: AttachmentBinding[] = [];
  for (const p of params) {
    // A multi-file input (SNF/MOFA2 `omics`, type file[]) is topped up even when an
    // earlier single-file extractor already set it to ONE file — otherwise the other
    // modality tables are dropped and the panel still asks "Which omics?" (dev 2026-11-11:
    // omics pre-bound to rna.csv, protein/methyl never added). A single-value param keeps
    // its binding — UNLESS that binding is a kind mismatch (coldstart Batch F:
    // protein_diffusion `dataset` pre-filled with *_constraints.json while a
    // co-attached .pdb/.cif is the structure-set pointer the trainer accepts).
    if (isBound(p.value) && !paramAcceptsMultipleFiles(p)) {
      const boundFile = resolveAttachedFileForValue(p.value, usableFiles);
      const wrongKind = !!boundFile && scoreBinding(p, boundFile).score < BIND_SCORE_THRESHOLD;
      if (!wrongKind) continue;
    }
    // An optional parameter already carrying a default is an override, not an
    // empty input — leave the pipeline default in place.
    if (!p.required && isBound(p.default ?? p.defaultValue)) continue;
    for (const f of usableFiles) {
      const { score, reason } = scoreBinding(p, f);
      if (score < BIND_SCORE_THRESHOLD) continue;
      candidates.push({
        param: String(p.name), file: f, files: [f],
        value: attachmentRefValue(f)!, score, reason,
      });
    }
  }
  candidates.sort(
    (a, b) =>
      b.score - a.score ||
      a.param.localeCompare(b.param) ||
      a.file.name.localeCompare(b.file.name),
  );
  const usedParams = new Set<string>();
  const usedFiles = new Set<string>();
  const out: AttachmentBinding[] = [];
  for (const c of candidates) {
    if (usedParams.has(c.param) || usedFiles.has(c.file.name)) continue;
    usedParams.add(c.param);
    usedFiles.add(c.file.name);
    out.push(c);
  }

  // Multi-file inputs (MOFA2's `omics`: "one features×samples CSV per
  // modality") take every remaining fitting attachment, not just the first —
  // otherwise two of the user's three modality tables are silently dropped and
  // the panel still asks "Which omics?". Files keep the order they were
  // attached in, and the value is the comma-separated list the panel and the
  // executor already read for list params.
  for (const b of out) {
    const p = params.find((q) => String(q.name) === b.param);
    if (!p || !paramAcceptsMultipleFiles(p)) continue;
    const extra = usableFiles.filter(
      (f) => !usedFiles.has(f.name) && scoreBinding(p, f).score >= BIND_SCORE_THRESHOLD,
    );
    if (extra.length === 0) continue;
    for (const f of extra) usedFiles.add(f.name);
    b.files = usableFiles.filter((f) => f === b.file || extra.includes(f));
    b.value = b.files.map((f) => attachmentRefValue(f)!).join(',');
    b.reason += `; multi-file (${b.files.length})`;
  }
  return out;
}

/** What the binding pass did, recorded on the generated workflow. */
export interface AttachmentBindingReport {
  attached: string[];
  bound: Array<{ param: string; file: string }>;
  unbound: string[];
}

/**
 * The attached files the chosen workflow does not read at all — the reply must
 * not present it as built from, or running on, that data.
 *
 * Only when NOTHING was bound and no required data input is still waiting: a
 * workflow that is merely waiting for its input gets the "needs input" reply
 * instead, and a partially bound workflow does use the user's data.
 */
export function attachmentsNotUsed(
  report: AttachmentBindingReport | undefined | null,
  opts: { runnableWorkflow: boolean; unboundRequiredInputs: number },
): string[] {
  if (!report || !opts.runnableWorkflow) return [];
  if ((report.bound?.length ?? 0) > 0) return [];
  if (opts.unboundRequiredInputs > 0) return [];
  return [...(report.attached || [])];
}

// ──────────────────────────────────────────────────────────────────────────
// Filename values that upstream extraction produced
// ──────────────────────────────────────────────────────────────────────────

/**
 * An extractor (LLM or rule) that saw "[Attached files: nanobody_candidates.fasta]"
 * sometimes emits the bare FILE NAME as a parameter value. A bare name resolves
 * to nothing at run time and renders as a phantom value in the panel. Rewrite it
 * to the file's dataset reference when the parameter really takes a file, and
 * drop it otherwise (an inline-content parameter must not receive a path).
 *
 * Kind safety (Batch F / structure-set): when the named file is the wrong kind
 * for the parameter (e.g. `*_constraints.json` on protein_diffusion `dataset`,
 * which expects a PDB/mmCIF structure set), do NOT promote the JSON — remap to
 * the best co-attached structure file, or drop so a later bind pass can fill it.
 */
export function rebindFilenameValues<T extends Record<string, any>>(
  params: T,
  files: readonly AttachedFile[],
  specs: readonly BindableParam[] = [],
): { params: Record<string, any>; rebound: string[]; dropped: string[] } {
  const out: Record<string, any> = {};
  const rebound: string[] = [];
  const dropped: string[] = [];
  const specFor = (k: string) => specs.find((s) => String(s.name || '') === k);

  for (const [k, v] of Object.entries(params || {})) {
    if (typeof v !== 'string') { out[k] = v; continue; }
    const file = resolveAttachedFileForValue(v, files);
    if (!file) { out[k] = v; continue; }
    const spec = specFor(k);
    if (spec && !isFilePathParam(spec)) {
      dropped.push(k);
      continue;
    }
    // Kind mismatch: constraints JSON must not become a structure-set pointer.
    if (spec && scoreBinding(spec, file).score < BIND_SCORE_THRESHOLD) {
      const better = bestAttachmentForParam(spec, files);
      if (better) {
        out[k] = attachmentRefValue(better.file)!;
        rebound.push(k);
      } else {
        dropped.push(k);
      }
      continue;
    }
    const ref = attachmentRefValue(file);
    if (ref) {
      out[k] = ref;
      rebound.push(k);
    } else {
      dropped.push(k);
    }
  }
  return { params: out, rebound, dropped };
}

// ──────────────────────────────────────────────────────────────────────────
// Clarification answers that refer to an attachment
// ──────────────────────────────────────────────────────────────────────────

/** "use the attached file", "用附件", "the uploaded csv", … (EN + ZH). */
const ATTACHMENT_REFERENCE_RE =
  /(attached|attachment|uploaded|upload|the file i|my file|this file|that file|the file|the csv|the data file)|附件|附上|上传的?(文件|数据|csv)?|我(上传|提供)的|这个文件|该文件|刚(刚)?上传/i;

/**
 * Resolve a free-text clarification answer that refers to an attachment.
 *
 * Returns the file the user means — by name ("bace_assays.csv", "bace_assays"),
 * or by reference ("use the attached file" / "用附件") when exactly one file is
 * attached, or when `param` is given and exactly one attachment fits it. Returns
 * null for an answer that is a real value (then the caller keeps the text).
 */
export function resolveAttachmentAnswer(
  answer: string,
  files: readonly AttachedFile[],
  param?: BindableParam,
): AttachedFile | null {
  const a = String(answer || '').trim();
  if (!a || files.length === 0) return null;
  const low = a.toLowerCase();

  // 1. Named directly (full name, or the name without its extension).
  for (const f of files) {
    const n = f.name.toLowerCase();
    const stem = n.replace(/\.[^.]+$/, '');
    if (low === n || low === stem || low.includes(n) || (stem.length >= 4 && low.includes(stem))) {
      return f;
    }
  }

  // 2. Referred to generically.
  if (!ATTACHMENT_REFERENCE_RE.test(a)) return null;
  const usable = files.filter((f) => !!attachmentRefValue(f));
  if (usable.length === 0) return null;
  if (usable.length === 1) return usable[0];
  if (!param) return null;
  const scored = usable
    .map((f) => ({ f, ...scoreBinding(param, f) }))
    .filter((s) => s.score >= BIND_SCORE_THRESHOLD)
    .sort((x, y) => y.score - x.score);
  if (scored.length === 0) return null;
  if (scored.length > 1 && scored[0].score === scored[1].score) return null; // genuinely ambiguous
  return scored[0].f;
}

/**
 * What a clarification answer should put into the parameter.
 *
 * "use the attached file" / "用附件" / "bace_assays.csv" must bind the FILE —
 * the panel showed the literal sentence as the parameter value and the input
 * stayed unbound. Any other answer is a real value and passes through unchanged.
 */
export function bindClarificationAnswer(
  answer: string,
  files: readonly AttachedFile[],
  param?: BindableParam,
): { value: string; file?: AttachedFile; bound: boolean } {
  const file = resolveAttachmentAnswer(answer, files, param);
  const ref = file ? attachmentRefValue(file) : undefined;
  if (!file || !ref) return { value: String(answer ?? ''), bound: false };
  return { value: ref, file, bound: true };
}

// ──────────────────────────────────────────────────────────────────────────
// nf-core samplesheets whose cells must be resolvable URIs (not bare names)
// ──────────────────────────────────────────────────────────────────────────

function fileByName(files: readonly AttachedFile[], name: string): AttachedFile | undefined {
  const want = name.trim().toLowerCase();
  return files.find((f) => f.name.trim().toLowerCase() === want && !!attachmentRefValue(f));
}

function refOrEmpty(f: AttachedFile | undefined): string {
  return (f && attachmentRefValue(f)) || '';
}

/**
 * Build a schema-valid nf-core `input` samplesheet whose path cells are already
 * resolvable dataset refs / s3:// URIs from the co-attached uploads.
 *
 * Cold-start fixtures ship CSVs with bare basenames (`normal_R1.fastq.gz`).
 * Chat uploads land each file under a distinct S3 prefix, so those relative
 * cells fail nf-schema `exists:true` and surface as
 * "Validation of pipeline parameters failed". Resolving here (rule-first) is
 * the single upstream fix for sarek + proteinfold cold-start launches.
 *
 * Returns null when the attached set cannot form a valid sheet for this workflow.
 */
export function buildResolvedNfcoreInputSamplesheet(
  workflowName: string,
  files: readonly AttachedFile[],
): { csv: string; reason: string } | null {
  const wf = String(workflowName || '').toLowerCase();

  // nf-core/sarek — patient,sample,sex,status,lane,fastq_1,fastq_2
  if (/\bsarek\b/.test(wf) || files.some((f) => /sequencing_samples\.csv$/i.test(f.name))) {
    const n1 = fileByName(files, 'normal_R1.fastq.gz');
    const n2 = fileByName(files, 'normal_R2.fastq.gz');
    const t1 = fileByName(files, 'tumor_R1.fastq.gz');
    const t2 = fileByName(files, 'tumor_R2.fastq.gz');
    if (n1 && n2 && t1 && t2) {
      const csv = [
        'patient,sample,sex,status,lane,fastq_1,fastq_2',
        `demo,normal,NA,0,1,${refOrEmpty(n1)},${refOrEmpty(n2)}`,
        `demo,tumor,NA,1,1,${refOrEmpty(t1)},${refOrEmpty(t2)}`,
        '',
      ].join('\n');
      return { csv, reason: 'sarek tumor/normal pair from attached FASTQs' };
    }
    if (n1 && n2) {
      const csv = [
        'patient,sample,sex,status,lane,fastq_1,fastq_2',
        `demo,normal,NA,0,1,${refOrEmpty(n1)},${refOrEmpty(n2)}`,
        '',
      ].join('\n');
      return { csv, reason: 'sarek germline pair from attached FASTQs' };
    }
  }

  // nf-core/proteinfold — id,fasta (schema_input requires fasta + id|sequence)
  if (/\bproteinfold\b/.test(wf) || files.some((f) => /proteinfold_samplesheet\.csv$/i.test(f.name))) {
    const complex = fileByName(files, '1BXL.fasta');
    const peptides = fileByName(files, 'peptide_candidates.fasta');
    const lysozyme = fileByName(files, '1LYZ.fasta');
    const pick = complex || peptides || lysozyme
      || files.find((f) => /\.(fa|fasta|faa)$/i.test(f.name) && !!attachmentRefValue(f));
    if (pick) {
      const id = pick.name.replace(/\.(fa|fasta|faa)$/i, '').replace(/[^\w.-]+/g, '_');
      const csv = ['id,fasta', `${id},${refOrEmpty(pick)}`, ''].join('\n');
      return { csv, reason: `proteinfold samplesheet from ${pick.name}` };
    }
  }

  return null;
}

/** True when a string is an inline nf-core samplesheet (not a path / URI). */
export function looksLikeInlineSamplesheet(value: unknown): boolean {
  if (typeof value !== 'string') return false;
  const head = value.trim().split(/\r?\n/, 1)[0] || '';
  return /^(patient,sample\b|id,fasta\b|sample,fastq_1\b)/i.test(head);
}
