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
    | 'out_of_memory'
    | 'container_tool'
    | 'missing_input_file'
    | 'bad_parameter'
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

/** The single most specific line of the raw error — never a bare "Caused by:". */
export function mostSpecificErrorLine(raw: string): string {
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
      nextAction: `Add the '${colName.trim()}' column to your input (or correct the column name in the parameter that selects it), then run again.`,
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
    /\b(command not found|executable not found|no command|image .*(?:not found|pull)|pull access denied|unable to find image|manifest .*not found|docker|singularity|container)\b/i.test(raw) &&
    /(not found|denied|unauthorized|error|pull|no such|missing)/i.test(raw) ||
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
      nextAction: 'Open the workflow panel → Edit params, fix the named parameter (set a valid/allowed value), then run again.',
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
