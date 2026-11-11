/**
 * Deterministic, rule-based classifier for a failed workflow run.
 *
 * Goal (organic-user issue #3, 2026-11-09): when a run FAILS, a first-time user
 * must be told, in one message, WHY it failed — the specific cause, the input/
 * param at fault, and a concrete next action — without having to ask "why".
 *
 * This maps the raw Nextflow / executor error text onto a small set of common
 * failure classes with a plain-language cause + remediation. It is a classifier,
 * NOT an LLM: rules are exact, zero-cost and testable. When the error does not
 * match any known class the result is `known:false` and we DO NOT invent a cause —
 * the caller shows the raw error and offers to investigate instead.
 *
 * Shared by the chat path (`frontend/server/galaxy-assistant.ts`, which feeds the
 * classified cause into the assistant's reply) and the After-Run panel
 * (`frontend/client/src/v2/AfterRunReport.tsx`, FailedRunSection banner), so both
 * surfaces say the same thing.
 */

export interface RunFailureExplanation {
  /** Stable classification key (for tests / analytics). 'unknown' = not classified. */
  klass:
    | 'workflow_not_found'
    | 'bad_contrast'
    | 'missing_column'
    | 'empty_input'
    | 'too_few_rows'
    | 'out_of_memory'
    | 'container_tool'
    | 'missing_input_file'
    | 'bad_parameter'
    | 'tool_error'
    | 'unknown';
  /** False when no rule matched — callers must NOT present an invented cause. */
  known: boolean;
  /** Plain-language cause (empty when `known` is false). */
  cause: string;
  /** The input / parameter / file at fault, when the error names it. */
  culprit?: string;
  /** One concrete next action the user can take. */
  nextAction: string;
  /** Failing Nextflow process / step, when detectable. */
  process?: string;
  /** Process exit code, when present. */
  exitCode?: string;
  /** The most specific raw error line, for the "show raw error" expansion. */
  raw: string;
  /** Named values the cause/culprit/next sentences refer to (file, column, …). */
  vars?: Record<string, string>;
  /** i18n keys (+ interpolation vars) for cause / culprit / next. The English
   *  sentences above stay the fallback (and what the server-side chat reply uses);
   *  UI surfaces render these through tOr so a zh session never shows English. */
  i18n: { cause?: string; culprit?: string; next: string; vars: Record<string, string> };
}

/** Pull the failing Nextflow process name out of raw error text, if present. */
function extractProcess(raw: string): string | undefined {
  return (
    /Error executing process > '([^']+)'/.exec(raw)?.[1] ||
    /process[\s>]+['"`]?([A-Z][A-Z0-9_:]+)['"`]?\s+(?:terminated|failed)/.exec(raw)?.[1] ||
    undefined
  );
}

/** Pull a process exit code out of raw error text, if present. */
function extractExit(raw: string): string | undefined {
  return (
    /terminated with an error exit status \((\d+)\)/.exec(raw)?.[1] ||
    /exit(?:\s+status|\s*:)?\s*\(?(\d{1,3})\)?/i.exec(raw)?.[1] ||
    undefined
  );
}

/** The exception the tool itself raised (Python `ValueError: …`, Java `…Exception: …`,
 *  R `Error in f(): …`), when the log carries one. This is the tool's own statement
 *  of why it stopped, so it outranks any heuristic on the surrounding executor text. */
function toolException(raw: string): { type: string; message: string; line: string } | undefined {
  const lines = (raw || '').split('\n').map(l => l.trim());
  for (let i = lines.length - 1; i >= 0; i--) {
    const m = /^(?:[\w.]+\.)?([A-Z]\w*(?:Error|Exception)):\s+(.+)$/.exec(lines[i]) ||
      /^(Error) in [^:]+:\s*(.+)$/.exec(lines[i]);
    if (m) return { type: m[1], message: m[2].slice(0, 300), line: lines[i].slice(0, 400) };
  }
  return undefined;
}

/** The single most specific line of the raw error — never a bare "Caused by:". */
export function mostSpecificErrorLine(raw: string): string {
  const exc = toolException(raw);
  if (exc) return exc.line;
  const line = (raw || '')
    .split('\n')
    .map(l => l.trim())
    .find(
      l =>
        l &&
        !/^Caused by:?$/i.test(l) &&
        !/^(DEBUG|WARN)\b/.test(l) &&
        !/\b(RetryConfig|FileHelper)\b/.test(l) &&
        !/^Error executing process >/.test(l),
    );
  return (line || raw.split('\n').map(l => l.trim()).find(Boolean) || '').slice(0, 400);
}

/** Try to extract the file path the error is complaining about. */
function fileNear(raw: string): string | undefined {
  const m =
    /(?:file|path|input)\s+['"`]?([^\s'"`,;:)]+\.[A-Za-z0-9]{1,6})/i.exec(raw) ||
    /['"`]([^\s'"`,;:)]+\.[A-Za-z0-9]{1,6})['"`]/.exec(raw) ||
    /\b([^\s'"`,;:)]+\.(?:fa|fasta|fastq|fq|gz|bam|sam|vcf|csv|tsv|txt|bed|gtf|gff|h5|h5ad|mzml)(?:\.gz)?)\b/i.exec(raw);
  return m?.[1];
}

/**
 * Classify a failed run's raw error text into a plain-language explanation.
 *
 * @param rawError  Assembled error text (recorded error + log/trace lines joined by "\n").
 * @param opts.process  Failing process/step, if the caller already knows it.
 */
export function classifyRunFailure(
  rawError: string | null | undefined,
  opts: { process?: string } = {},
): RunFailureExplanation {
  return withI18n(classifyCore(rawError, opts));
}

type CoreExplanation = Omit<RunFailureExplanation, 'i18n'>;

/** Attach locale keys: `failure.<klass>.cause[_named]`, `.culprit[_named]`, `.next[_step]`. */
function withI18n(e: CoreExplanation): RunFailureExplanation {
  const vars: Record<string, string> = {
    step: e.process ? ` '${e.process}'` : '',
    process: e.process || '',
    exit: e.exitCode ? ` (exit ${e.exitCode})` : '',
    culprit: e.culprit || '',
    ...(e.vars || {}),
  };
  const k = `failure.${e.klass}`;
  if (e.klass === 'unknown') {
    return { ...e, i18n: { next: !e.raw ? 'failure.no_error.next' : e.process ? `${k}.next_step` : `${k}.next`, vars } };
  }
  const named = Object.keys(e.vars || {}).length > 0;
  const culpritKey =
    !e.culprit ? undefined
    : e.klass === 'workflow_not_found' ? undefined          // a literal path: shown verbatim
    : e.klass === 'out_of_memory' || e.klass === 'container_tool' || e.klass === 'tool_error'
      ? (e.process ? `${k}.culprit_step` : `${k}.culprit`)
    : named ? `${k}.culprit_named` : `${k}.culprit`;
  return {
    ...e,
    i18n: { cause: named ? `${k}.cause_named` : `${k}.cause`, culprit: culpritKey, next: named ? `${k}.next_named` : `${k}.next`, vars },
  };
}

function classifyCore(
  rawError: string | null | undefined,
  opts: { process?: string } = {},
): CoreExplanation {
  const raw = (rawError || '').trim();
  const process = opts.process || extractProcess(raw);
  const exitCode = extractExit(raw);
  const specific = mostSpecificErrorLine(raw);
  const base = { process, exitCode, raw: specific } as const;

  if (!raw || /^Caused by:?$/i.test(raw)) {
    return {
      klass: 'unknown',
      known: false,
      cause: '',
      nextAction:
        'No error message was captured for this run. Open the run in the workflow panel → failed step → log to see the task log, and share it so I can investigate.',
      ...base,
    };
  }

  // 1. Workflow could not be loaded / resolved (e.g. a mis-routed nf-core path → 404).
  if (/Could not resolve Nextflow script|Unable to resolve .*(?:pipeline|workflow|script)|pipeline .*not found|No such pipeline/i.test(raw)) {
    // Prefer the quoted script path; only then a bare token after "resolve".
    const culprit =
      /['"`]([^'"`]+\.nf)['"`]/i.exec(raw)?.[1] ||
      /script\s+['"`]([^'"`]+)['"`]/i.exec(raw)?.[1] ||
      /resolve\s+(?:Nextflow\s+)?(?:script\s+)?['"`]?([^\s'"`]+)/i.exec(raw)?.[1];
    return {
      klass: 'workflow_not_found',
      known: true,
      cause: 'The workflow itself could not be loaded on the server — the pipeline path it was given does not exist or is unavailable.',
      culprit,
      nextAction: 'Pick the workflow from the panel/catalog (or ask me to route your request) instead of that path, then run it again.',
      ...base,
    };
  }

  // 2. Bad contrast / design column mismatch (differentialabundance, DESeq2, edgeR).
  const contrastVar =
    /contrast variables? (?:are|is) not present in the sample ?sheet:?\s*([^\n.]+)/i.exec(raw)?.[1] ||
    /(?:contrast|design|comparison)[^\n]*?\bcolumn\s+['"`]?([A-Za-z0-9_.]+)['"`]?[^\n]*?(?:not found|not present|does not exist|missing|not in)/i.exec(raw)?.[1] ||
    /['"`]?([A-Za-z0-9_.]+)['"`]?\s+(?:is )?not (?:a )?(?:present|found|in)[^\n]*sample ?sheet/i.exec(raw)?.[1];
  if (/contrast/i.test(raw) && /(not (?:present|found|in)|missing|does not exist|no such column)/i.test(raw)) {
    return {
      klass: 'bad_contrast',
      known: true,
      cause: contrastVar
        ? `Your contrasts/design references the column '${contrastVar.trim()}', which is not in your sample sheet.`
        : 'Your contrasts file references a column that is not present in your sample sheet, so the comparison could not be set up.',
      culprit: contrastVar?.trim() ? `contrasts column '${contrastVar.trim()}'` : 'contrasts file',
      vars: contrastVar?.trim() ? { contrast: contrastVar.trim() } : undefined,
      nextAction: 'Make the contrast variable match a column that exists in the sample sheet (add the column, or fix its name/spelling), then run again.',
      ...base,
    };
  }

  // 2b. Generic missing/mismatched column (not necessarily a contrast).
  const colName =
    /column\s+['"`]?([A-Za-z0-9_.]+)['"`]?\s+(?:not found|does not exist|is not present|is missing|not in)/i.exec(raw)?.[1] ||
    /(?:no such column|unknown column|undefined columns?)[:\s]+['"`]?([A-Za-z0-9_., ]+)/i.exec(raw)?.[1] ||
    /KeyError:?\s*['"`]([^'"`]+)['"`]/.exec(raw)?.[1];
  if (colName && /\bcolumn|KeyError|undefined columns?\b/i.test(raw)) {
    return {
      klass: 'missing_column',
      known: true,
      cause: `The analysis expected a column '${colName.trim()}' that is not in your input table.`,
      culprit: `column '${colName.trim()}'`,
      vars: { column: colName.trim() },
      nextAction: `Add the '${colName.trim()}' column to your input (or correct the column name in the parameter that selects it), then run again.`,
      ...base,
    };
  }

  // 2c. Too few rows for the requested split / CV (a 1-row file given as a training table).
  const fewRows =
    /cannot make (\d+) folds from (\d+) rows?/i.exec(raw) ||
    /n_splits=(\d+) cannot be greater than the number of (?:samples|members[^:]*): n_samples=(\d+)/i.exec(raw);
  if (fewRows) {
    return {
      klass: 'too_few_rows',
      known: true,
      cause: `The input table has only ${fewRows[2]} usable row(s), too few for ${fewRows[1]}-fold cross-validation — it does not look like a training table (one row per sample with feature columns and a label).`,
      culprit: 'training dataset',
      vars: { rows: fewRows[2], folds: fewRows[1] },
      nextAction: 'Pick a dataset with one row per sample (at least a few dozen rows), or lower the number of folds / use a holdout split, then train again.',
      ...base,
    };
  }

  // 3. Empty input (before missing-file: "input X is empty" is not "X not found").
  if (/\b(is empty|empty file|contains no data|0 reads|no reads|no records|no (?:valid )?sequences|zero records|no input (?:files|data))\b/i.test(raw)) {
    const f = fileNear(raw);
    return {
      klass: 'empty_input',
      known: true,
      cause: f ? `The input file ${f} is empty — there was no data for the step to process.` : 'One of the input files is empty — there was no data for the step to process.',
      culprit: f,
      vars: f ? { file: f } : undefined,
      nextAction: 'Confirm the upload/transfer completed and the file actually contains data, replace the empty input, then run again.',
      ...base,
    };
  }

  // 4. Out of memory / killed for exceeding a resource limit. Exit 137 is the
  //    OOMKilled convention; we do NOT treat 139 (SIGSEGV) or 143 (SIGTERM / spot
  //    reclaim / timeout) as OOM, since that would invent a memory cause.
  if (
    /\b(OutOfMemory|OOMKilled|out of memory|cannot allocate memory|memory limit|exceeded .*memory|java\.lang\.OutOfMemoryError)\b/i.test(raw) ||
    exitCode === '137' ||
    /\bKilled\b/.test(raw)
  ) {
    return {
      klass: 'out_of_memory',
      known: true,
      cause: `The step${process ? ` '${process}'` : ''} ran out of memory (or was killed for exceeding its resource limit)${exitCode ? ` — exit ${exitCode}` : ''}.`,
      culprit: process ? `step '${process}'` : 'memory/resource allocation',
      nextAction: 'Re-run with a larger memory / instance size for that step, or reduce the input size (subset / downsample) so it fits.',
      ...base,
    };
  }

  // 5. Container / tool unavailable (missing command, image pull, exit 127).
  if (
    // Specific phrases only. Nextflow prints a "Container:" banner on EVERY failed
    // task, so the bare word "container"/"docker" next to "ERROR" is not evidence
    // (it mislabelled a Python ValueError as "missing image", 2026-11-10).
    /\b(command not found|executable not found|pull access denied|unable to find image|CannotPullContainerError|ErrImagePull|failed to pull image|manifest (?:for \S+ )?(?:unknown|not found)|image \S+ (?:not found|does not exist))/i.test(raw) ||
    (exitCode === '127') ||
    /No such file or directory.*\.(?:sh|py|pl|R)\b|\/(?:usr|bin)\/[^\s]*: No such file/i.test(raw)
  ) {
    return {
      klass: 'container_tool',
      known: true,
      cause: `A tool or container the step${process ? ` '${process}'` : ''} needs was not available (missing command or image).`,
      culprit: process ? `step '${process}' container/tool` : 'container/tool',
      nextAction: 'This is usually an environment issue on our side — report it to BioMate; we will check the container/tool image for that step. Re-running as-is will not help until it is fixed.',
      ...base,
    };
  }

  // 6. Missing input file / bad path (general; after the container .sh case above).
  if (/\b(no such file or directory|does not exist|file not found|cannot find .*(?:file|path)|not a valid path|path .*(?:does not exist|not found)|unable to (?:read|open) .*file)\b/i.test(raw)) {
    const f = fileNear(raw);
    return {
      klass: 'missing_input_file',
      known: true,
      cause: f ? `An input the pipeline needs could not be found: ${f}.` : 'An input file the pipeline needs could not be found at the path it was given.',
      culprit: f,
      vars: f ? { file: f } : undefined,
      nextAction: 'Check that the file parameter points to a file that exists and is still accessible (re-upload or fix the path), then run again.',
      ...base,
    };
  }

  // 7. Invalid / missing parameter value.
  if (/\b(unknown parameter|unrecognized (?:option|parameter)|invalid value|is not a valid|must be one of|missing required (?:parameter|argument)|parameter .* is required|required parameter)\b/i.test(raw)) {
    const p = /parameter\s+['"`]?(--?[A-Za-z0-9_.]+|[A-Za-z0-9_.]+)['"`]?/i.exec(raw)?.[1];
    return {
      klass: 'bad_parameter',
      known: true,
      cause: p ? `A parameter value was invalid or missing: ${p}.` : 'A parameter value was invalid, or a required parameter was missing.',
      culprit: p,
      vars: p ? { param: p } : undefined,
      nextAction: 'Open the workflow panel → Edit params, fix the named parameter (set a valid/allowed value), then run again.',
      ...base,
    };
  }

  // 7b. The tool raised its own exception and no rule above recognised it: report
  //     the tool's message verbatim as the cause rather than "unknown".
  const exc = toolException(raw);
  if (exc) {
    return {
      klass: 'tool_error',
      known: true,
      cause: `The step${process ? ` '${process}'` : ''} stopped with an error from the tool itself: ${exc.message}`,
      culprit: process ? `step '${process}'` : undefined,
      vars: { detail: exc.message },
      nextAction: 'Check the input and parameters against that message (it usually names what is wrong), fix them, then run again.',
      ...base,
    };
  }

  // 8. Unknown — do NOT invent a cause. Report the step + the raw error and offer to help.
  return {
    klass: 'unknown',
    known: false,
    cause: '',
    nextAction: `Share this error with me and I will investigate${process ? `; you can also open the run in the workflow panel → '${process}' step → log for the full task log` : '; the full task log is in the workflow panel → failed step → log'}.`,
    ...base,
  };
}

/**
 * Compose a one-message, plain-language failure reply from a classification:
 * (a) the cause, (b) the input/param at fault, (c) a concrete next action.
 * When the class is unknown it states the step + shows the raw error rather than
 * inventing a cause. The raw error line is always included for "show raw error".
 */
export function formatRunFailureReply(exp: RunFailureExplanation): string {
  const parts: string[] = [];
  if (exp.known && exp.cause) {
    parts.push(`Why it failed: ${exp.cause}`);
    if (exp.culprit && !exp.cause.includes(exp.culprit)) parts.push(`At fault: ${exp.culprit}.`);
    parts.push(`Next: ${exp.nextAction}`);
  } else {
    const where = exp.process ? ` at step '${exp.process}'${exp.exitCode ? ` (exit ${exp.exitCode})` : ''}` : '';
    parts.push(`The run failed${where}. I can't pin a specific cause from the recorded error, so here it is:`);
    parts.push(`Next: ${exp.nextAction}`);
  }
  if (exp.raw) parts.push(`Error: ${exp.raw}`);
  return parts.join('\n');
}
