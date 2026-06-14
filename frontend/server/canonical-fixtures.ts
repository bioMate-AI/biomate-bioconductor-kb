/**
 * Canonical built-in fixture datasets recognised by the chat router.
 *
 * When the user's message mentions one of these names — directly or via an
 * alias — the chat must treat it as a fully-resolved input and emit the
 * workflow card immediately. It must NOT ask for an upload, counts matrix,
 * or metadata CSV. This is the bioinformatics-fixtures analog of the
 * existing ADMET-from-SMILES and pocket-from-PDB-id auto-resolve rules.
 *
 * Mirrors `docs/20260610_DETERMINISTIC_CHAT_ROUTING_PLAN.md`.
 *
 * The structured data here serves two roles:
 *   1) Injected into the workflow-generation system prompt as a table
 *      (see buildCanonicalFixturePromptSection) so the LLM follows the rule.
 *   2) Available for a future pre-LLM regex pass (Plan C) that suppresses
 *      the clarification gate independently of the LLM's behaviour.
 */

export interface CanonicalFixture {
  /** Primary name used inside the workflow (e.g. "airway"). */
  name: string;
  /** Other phrasings the user may type for the same fixture. Case-insensitive. */
  aliases: string[];
  /** One-line description of what the fixture is — used in the prompt table. */
  description: string;
  /** Workflows where this fixture is a known valid input. */
  workflowsHint: string[];
  /** Inline parameter set that the router can auto-fill when this fixture is detected. */
  paramHints?: Record<string, string>;
}

export const CANONICAL_FIXTURES: CanonicalFixture[] = [
  // ── Bioconductor / nf-core differentialabundance built-ins ──────────────
  {
    name: "airway",
    aliases: ["airway example", "Himes airway", "the airway dataset", "airway data"],
    description: "Bioconductor `airway` built-in (Himes 2014, 4 cell lines × 2 dexamethasone treatments). Loadable via `data(airway)` from the airway package — no upload needed.",
    workflowsHint: ["nf-core/differentialabundance", "bioconductor/deseq2/multi_factor_analysis", "bioconductor/deseq2/main"],
    paramHints: { dataset: "airway", contrast: "treated vs untreated" },
  },
  {
    name: "pasilla",
    aliases: ["pasilla example", "the pasilla dataset", "pasilla data"],
    description: "Bioconductor `pasilla` built-in (Drosophila exon counts). Loadable via the pasilla package — no upload needed.",
    workflowsHint: ["bioconductor/dexseq", "bioconductor/edger/main", "nf-core/differentialabundance"],
    paramHints: { dataset: "pasilla" },
  },
  // ── 10x Genomics scRNA fixtures bundled with Seurat / Scanpy ────────────
  {
    name: "pbmc3k",
    aliases: ["pbmc 3k", "pbmc3k example", "Seurat pbmc3k", "10x pbmc3k"],
    description: "10x Genomics PBMC 3k cells single-cell tutorial dataset bundled with Seurat / Scanpy — no upload needed.",
    workflowsHint: ["single_cell/seurat_qc_clustering", "single_cell/scanpy_clustering"],
    paramHints: { dataset: "pbmc3k" },
  },
  {
    name: "pbmc8k",
    aliases: ["pbmc 8k", "10x pbmc8k"],
    description: "10x Genomics PBMC 8k cells — bundled fixture.",
    workflowsHint: ["single_cell/seurat_qc_clustering", "single_cell/scanpy_clustering"],
    paramHints: { dataset: "pbmc8k" },
  },
  {
    name: "pbmc10k",
    aliases: ["pbmc 10k", "10x pbmc10k"],
    description: "10x Genomics PBMC 10k cells — bundled fixture.",
    workflowsHint: ["single_cell/seurat_qc_clustering", "single_cell/scanpy_clustering"],
    paramHints: { dataset: "pbmc10k" },
  },
  // ── Toy datasets bundled with R / Python ────────────────────────────────
  {
    name: "iris",
    aliases: ["iris example", "Fisher iris", "iris data"],
    description: "Classic Fisher iris classification dataset — bundled with base R and sklearn.",
    workflowsHint: ["bioconductor/randomforest/main", "general/classification_toy"],
    paramHints: { dataset: "iris" },
  },
  {
    name: "mtcars",
    aliases: ["mtcars example", "mtcars data"],
    description: "Classic mtcars regression dataset — bundled with base R.",
    workflowsHint: ["bioconductor/randomforest/main", "general/regression_toy"],
    paramHints: { dataset: "mtcars" },
  },
];

/**
 * Regex matchers for accession patterns whose workflow auto-fetches the data.
 * These don't need a literal entry in CANONICAL_FIXTURES because they're
 * pattern-based, not name-based.
 */
export const ACCESSION_PATTERNS: Array<{ pattern: RegExp; kind: string; description: string }> = [
  {
    pattern: /\bGSE\d{3,}\b/i,
    kind: "GEO accession",
    description: "GEO Series accession (e.g. GSE52778). The workflow knows how to fetch via GEOquery / SRA-toolkit — no upload needed.",
  },
  {
    pattern: /\bSRR\d{6,}\b/i,
    kind: "SRA accession",
    description: "SRA Run accession (e.g. SRR1039508). The workflow fetches via fastq-dump / sra-toolkit — no upload needed.",
  },
  {
    pattern: /\bTCGA-[A-Z]{2,4}\b/i,
    kind: "TCGA cohort",
    description: "TCGA cohort tag (e.g. TCGA-LUAD). The workflow fetches via GenomicDataCommons — no upload needed.",
  },
  {
    pattern: /\b(?:use|with|on)\s+(?:the\s+)?(?:nf-core\s+)?test\s+profile\b/i,
    kind: "nf-core -profile test",
    description: "Explicit reference to an nf-core test profile. The workflow runs with `-profile test,aws` and its bundled fixtures — no upload needed.",
  },
];

/**
 * Detect whether the user's message names a canonical fixture or accession.
 * Returns the matched fixture's name (e.g. "airway") or null. Used by the
 * pre-LLM clarification-suppression gate so the chat doesn't ask for files
 * when the dataset is already named — even when the user adds verbose
 * detail like "treated vs untreated; export CSV + MA plot" that would
 * otherwise re-trigger the LLM's "I need files" reflex.
 *
 * This is the deterministic counterpart to the prompt-level rule in
 * buildCanonicalFixturePromptSection() — Plan C from
 * docs/20260610_DETERMINISTIC_CHAT_ROUTING_PLAN.md.
 */
export function matchesCanonicalFixture(message: string): string | null {
  if (!message) return null;

  for (const fx of CANONICAL_FIXTURES) {
    const candidates = [fx.name, ...fx.aliases];
    for (const c of candidates) {
      // Word-boundary match to avoid false positives like "pairway"
      // matching "airway" or "ironman" matching "iris".
      const escaped = c.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const re = new RegExp(`(?:^|[^\\w])${escaped}(?:[^\\w]|$)`, "i");
      if (re.test(message)) return fx.name;
    }
  }

  for (const p of ACCESSION_PATTERNS) {
    if (p.pattern.test(message)) return p.kind;
  }

  return null;
}

/**
 * Build the system-prompt section that tells the LLM about all canonical
 * fixtures. Plug this into the workflow-generation prompt next to the
 * ADMET-from-SMILES and pocket-from-PDB-id rules.
 */
export function buildCanonicalFixturePromptSection(): string {
  const rows = CANONICAL_FIXTURES.map(f => {
    const aliasList = [f.name, ...f.aliases].slice(0, 3).map(a => `\`${a}\``).join(", ");
    const wfList = f.workflowsHint.slice(0, 2).join(" or ");
    return `| ${aliasList} | ${f.description.replace(/\|/g, "\\|")} | ${wfList} |`;
  }).join("\n");

  const accRows = ACCESSION_PATTERNS.map(p =>
    `| match \`${p.pattern.source}\` | ${p.description.replace(/\|/g, "\\|")} | inferred from the request |`
  ).join("\n");

  return `**Canonical built-in datasets are auto-resolvable inputs (deterministic routing rule)**

The following dataset names ship with their underlying R/Bioconductor package or with the nf-core test profile. When a user names one of them — directly or by an alias — treat it as a fully-resolved input and **generate the workflow card immediately**. This is the bioinformatics-fixture analog of the existing rules:

  - ADMET workflow auto-routes when the user provides a SMILES string.
  - Pocket-detection workflow auto-routes when the user provides a PDB 4-letter ID.
  - This rule auto-routes when the user names a canonical bioinformatics fixture.

| User mentions | What the fixture is | Workflows it maps to |
|---|---|---|
${rows}
${accRows}

**Forbidden response patterns** when the user's message contains any of the names or matching patterns above:
  - "Please upload the raw counts matrix..."
  - "I need the underlying dataset..."
  - "Could you share the metadata CSV?"
  - "Please share the FASTQ files..."

Those phrasings must not appear in any reply where the user already named a fixture. Instead, emit the workflow card with the canonical dataset as input (set \`params.dataset = <name>\` or the equivalent param). The user can still override params if they want — that's a follow-up, not a precondition.

**Rationale.** These names *are* the data. \`data(airway)\` loads the counts + metadata from the airway package; \`SRR\d+\` triggers a fetch via SRA-toolkit; the nf-core \`test\` profile ships its fixtures inside the pipeline. Asking the user to upload these is the wrong response — it produces measurable abandonment in chat logs. Same logical pattern that already works for ADMET-from-SMILES and pocket-from-PDB-id, extended to the bioinformatics fixtures.

**Few-shot example (this is exactly the response shape):**

  User: "Run DESeq2 differential expression on the airway example dataset; treated vs untreated; export results CSV + MA plot."
  Assistant: <workflow card for nf-core/differentialabundance with dataset=airway, contrast="treated vs untreated", emit CSV + MA plot — NO clarification ask>

  User: "Cluster pbmc3k with Seurat default settings"
  Assistant: <workflow card for single_cell/seurat_qc_clustering with dataset=pbmc3k — NO clarification ask>

  User: "Run nf-core/rnaseq on SRR1039508"
  Assistant: <workflow card for nf-core/rnaseq with input=SRR1039508 — NO clarification ask>`;
}
