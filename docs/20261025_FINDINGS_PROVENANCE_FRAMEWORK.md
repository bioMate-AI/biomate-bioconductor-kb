# Entity-Aware Findings + Provenance — General Framework & Guideline

**Date:** 2026-10-25. **Status:** framework/spec (no implementation yet — agreed first).
**Supersedes the ad-hoc approach** of per-workflow findings parsers. This is the single
source of truth the backend extractor **and** the Claude Design findings primitive both
build against. Problem 2 of `20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md`.

---

## 0. Why (the problem this replaces)

Findings are generated **ad hoc, case by case**. `frontend/server/routes.ts`
`preProcessForFindings` routes by a workflow-name regex to **4 hardcoded parsers**:

| Parser | Covers | Emits |
|---|---|---|
| `_parseAdmetOutput` | drug_discovery ADMET | structured `key_results` **with `entity`** + thresholds |
| `_parseDeseq2Output` | transcriptomics DE | only `{context, numbers}` → LLM |
| `_parseEnrichGoOutput` | enrichment | only `{context, numbers}` → LLM |
| `_parseRarediseaseOutput` | variant calling | only `{context, numbers}` → LLM |

Everything else (~4,200 of 4,210 workflows) falls through to a generic LLM findings
call. Three consequences, each a Problem-2 defect:

1. **Entity identity is first-class only for ADMET** — only `_parseAdmetOutput` + the
   `findings-card.tsx` `KeyResult` carry a structured `entity`. `AfterRunReport.tsx`
   `FindingsKeyResult` has none. So per-compound/per-gene/per-variant attribution is lost
   for everything except one path.
2. **Provenance is a bare filename reprinted per row** — no version/hash, no evidence
   class, no producer step/tool/model+version. Violates "never a bare predicted number"
   (`20261023_DRUGDEV…INFOFLOW…:66`).
3. **Three shapes** (`KeyResult` in findings-card, `FindingsKeyResult` in AfterRunReport,
   the ADMET push shape) — no single contract.

Adding fields to `_parseAdmetOutput` per metric would deepen the bespoke-per-workflow
pattern we are explicitly killing ("reusable primitives, not bespoke screens per
workflow"; "LLM composes from primitives — kill per-workflow templates"). **The fix is
one general record + one general extractor, not a fifth parser.**

---

## 1. The universal Findings Record (the contract)

Every finding, in every domain, is **one entity, one metric, one value, with a verdict
and provenance**. This single shape replaces all three current types.

```ts
type EvidenceClass = 'Table' | 'Figure' | 'Structure' | 'Report' | 'Log';
type EntityType =
  | 'compound' | 'gene' | 'variant' | 'protein' | 'peptide' | 'cell_type'
  | 'taxon' | 'go_term' | 'pathway' | 'particle' | 'map' | 'residue'
  | 'feature' | 'clonotype' | 'allele' | 'dose' | 'sample' | 'none';

interface FindingRecord {
  // WHO — the entity this value belongs to (ALWAYS present; `none`/`batch` for aggregates)
  entity: {
    type: EntityType;
    label: string;                        // display: "aspirin", "TP53", "rs1234", "cluster 3"
    identifier?: { scheme: string; value: string };   // {SMILES|Ensembl|UniProt|rsID|CHROM:POS|GO}
    identitySource?: 'input_mapping' | 'output_column' | 'companion_file' | 'unresolved';
    scope: 'per_entity' | 'batch' | 'global';   // batch = belongs to no single entity
  };
  // WHAT — the measurement (never a bare number)
  metric: {
    name: string;                         // "hERG inhibition", "log2FoldChange", "resolution"
    value: string | number;               // exact as read; string preserves precision/format
    units?: string;                       // "µM" | "Å" | "kcal/mol" | "" (dimensionless)
    comparator?: '=' | '<' | '>' | '<=' | '>=' | '~';  // censored: IC50 > 30 µM (NEVER coerce to 30)
    confidence?: { kind: 'ci' | 'sem' | 'prob' | 'applicability' | 'ood'; value: string };
  };
  // VERDICT — interpretation against an explicit criterion (optional; absent = descriptive)
  assessment?: {
    threshold?: { value: number; direction: 'high_bad' | 'low_bad' | 'band'; label?: string };
    flag: 'pass' | 'liability' | 'neutral' | 'unknown';
    interpretation: string;               // human sentence; no rejected boilerplate
  };
  // WHERE — immutable provenance (referenced by id; see §1.1 for de-dup)
  provenanceRef: string;                  // → FindingsDocument.provenance[id]
}

interface Provenance {
  id: string;
  source: { file: string; version?: string; locator?: string };   // version = hash/run-rel path; locator = line/cell/column
  producer?: { step?: string; tool?: string; toolVersion?: string; model?: string; modelVersion?: string };
  evidenceClass: EvidenceClass;           // which viewer opens the full artifact
  outputRef?: string;                     // link/id into the Outputs tab (step-output-preview)
}

interface FindingsDocument {
  status: 'generating' | 'ready' | 'unavailable';
  summary: string;                        // concise, entity-aware (chat uses a trimmed form)
  entityRoster: Array<{ type: EntityType; label: string; identifier?: object }>;  // for grouping + missing states
  records: FindingRecord[];               // the full per-entity × per-metric set
  provenance: Record<string, Provenance>; // shared — a file/version/tool cited ONCE, referenced by many records
  caveats: string[];
  nextSteps: string[];
  report?: { url: string; version?: string };
}
```

**Why this shape satisfies the accepted decisions:**
- **Entity always present + `scope`** → real identity everywhere; `scope:'batch'` is the
  honest state for the hERG IC50 **432.4246 µM** that "belongs to no named compound".
  `identitySource:'unresolved'` is the partial-identity state (flag, never fabricate).
- **`provenanceRef` + shared `provenance` map** → source cited **once**, referenced by
  many records (kills the "same filename on every row" redundancy) while every number
  still traces to an immutable file/version + producer + evidence class.
- **`units` + `comparator` + `confidence`** → no bare numbers; censored values stay
  inequalities; confidence/CI/applicability travels with the value.
- **`assessment` optional** → a passing DILI check is "pass", not an overall-safety claim;
  interpretation carries the sentence, never the rejected "model prediction, not measured".

---

## 2. Domain → entity map (the generalization)

The same record shape covers every domain; only `entity.type`, the metric vocabulary, and
the evidence class vary. From CLAUDE.md §Workflow Database (4,210 wf / 42 domains) + the
MCP domain descriptions + the infoflow doc:

| Domain | Entity (`type`) | Identifier scheme | Typical metrics (units) | Evidence class |
|---|---|---|---|---|
| transcriptomics (DE) | gene | Ensembl / symbol | log2FoldChange, padj, baseMean | Table + Figure(volcano) |
| enrichment / systems | go_term / pathway | GO / KEGG | p.adjust, GeneRatio, Count, NES | Table + Figure |
| genomics | contig / sample | — | N50, coverage ×, QC % | Report + Table |
| variant_calling | variant | rsID / CHROM:POS | IMPACT, consequence, AF, QUAL | Table (+VCF viewer) |
| epigenomics | peak | CHROM:start-end | peak count, FRiP, fold-enrich, q | Table + Figure |
| drug_discovery (ADMET) | compound | SMILES / name | hERG IC50(µM), DILI(0-1), BBB, Caco-2 logPapp, PPB%, CYP, Ames, oral-bioavail, ClinTox | Table + Structure + Report |
| drug_discovery (docking/FEP) | compound / edge | SMILES | Vina affinity(kcal/mol), ΔΔG±SEM(kcal/mol) | Structure + Table |
| proteomics | protein / peptide | UniProt | LFQ intensity, #peptides, FDR, FC | Table + Figure |
| single_cell | cell_type / cluster | — | #cells, #clusters, markers, ambient frac | Figure + singlecell viewer |
| metagenomics | taxon | NCBI taxid | rel. abundance %, reads, #bins | Table + Figure |
| metabolomics | feature | m/z@RT | fold-change, VIP, p-value | Table + Figure |
| cryo_em | particle / map | — | resolution(Å), #particles, FSC, CTF | Structure/Density viewer |
| structural_biology | residue / model | — | pLDDT, PAE(Å), RMSD(Å) | Structure (fold+pLDDT+PAE) |
| immunology | clonotype / allele | — | diversity, cell fractions | Table + Figure |
| pharmacology | dose / drug | — | Cmax, AUC, EC50/IC50, margin | Table + Figure |

**The lesson:** per-domain difference is **data** (entity type + metric vocab + threshold
table + evidence class), not **code**. → §3.

---

## 3. Extraction architecture (replace 4 parsers + LLM with 1 pipeline)

```
run outputs ──► classify output file(s) by shape ──► ADAPTER (declarative) ──► FindingRecord[]
                         │ no adapter / irregular                               │
                         └────────────► constrained LLM extractor ─────────────┘ (same schema)
                                                                 │
                                        validate (verbatim numbers, source exists,
                                        units/comparator sane, identity resolved) ──► FindingsDocument
```

1. **Pattern adapters, not workflow parsers.** Most outputs are **tabular-per-entity**:
   a table whose rows are entities and columns are metrics (ADMET JSON→rows, DESeq2 CSV,
   enrichGO CSV, VEP TSV, proteomics TSV, metabolomics CSV all fit). One generic
   `tabularPerEntity` extractor driven by a **declarative descriptor** per domain/pattern:
   ```ts
   interface PatternDescriptor {
     id: string;                       // "admet", "deseq2", "vep_variants", "enrichgo", …
     match: { fileRegex?: RegExp; contentIncludes?: string[]; domainTag?: string };
     entity: { type: EntityType; column?: string; fromInputParam?: string; scheme?: string };
     metrics: Array<{ name: string; column: string; units?: string;
                      threshold?: { value: number; direction: 'high_bad'|'low_bad'|'band' } }>;
     evidenceClass: EvidenceClass;
   }
   ```
   Adding a domain = **add a descriptor row** (data), not a function. The 4 current
   parsers collapse into ~a dozen descriptors; the generic extractor + validator is shared.
   A second family, **structured-report** (JSON like `toxicity_report.json`/`ddg_summary.json`
   with named fields), uses a field-path descriptor variant.
2. **Entity resolution order** (per the accepted decision): `output_column` → else
   `input_mapping` (e.g. the `smiles_list` the user submitted, mapped positionally/by index
   to a companion per-compound output) → else `companion_file` → else mark
   `identitySource:'unresolved'` + `scope:'batch'`. **Never fabricate** "Compound N" as an
   identity; it is only a last-resort display label with `scope:'batch'`.
3. **Constrained LLM fallback** — unchanged guards (verbatim-number check, source_file
   existence, citation strip; routes.ts ~14701-14888), but its JSON target becomes the
   **FindingRecord** shape (entity+units+comparator+provenanceRef), not the flat
   `{metric,value,interpretation,source_file}`. Used only when no descriptor matches or the
   table is irregular. Rule-first, LLM-fallback — matches CLAUDE.md's hybrid policy.
4. **Validation (guardrail)** runs on adapter AND LLM output: numbers verbatim in source;
   `provenance.source.file` exists among sampled outputs; `comparator` preserved from the
   raw token; units from the descriptor or recognized; drop rows that fail (never invent).

---

## 4. Guideline (rules every producer + renderer follows)

**Identity**
- Every record has an `entity`; multi-entity runs group by entity. `scope:'batch'` for
  aggregates (a single number over all inputs); `'global'` for run-level metrics (N50,
  resolution). `identitySource:'unresolved'` renders as an explicit "unattributed" state.
- Do not claim identity is unavailable when a companion per-compound output supplies it
  (resolve via §3.2 before falling back).

**Provenance**
- Every record references one `Provenance` (file + version/hash + producer + evidence
  class). Cite a source **once** in `provenance{}`, reference by id — never reprint per row.
- `evidenceClass` is set so the UI links the value to the right viewer
  (`step-output-preview.tsx` resolves Table/Figure/Structure/Report/Log).

**Values**
- No bare numbers: `units` (or explicit dimensionless) + `assessment.interpretation`
  always travel. Censored values keep `comparator` (`IC50 > 30 µM`, never coerced to 30).
- Confidence/CI/SEM/applicability in `metric.confidence` (ΔΔG ± SEM; pLDDT; OOD flag).
- **No blended/composite score** across objectives — emit one record per objective; the
  renderer shows per-objective bars; safety is a hard gate, not averaged.

**Verdicts**
- `assessment.flag` is `pass|liability|neutral|unknown` against an explicit `threshold`.
  A `pass` is not an overall-safety conclusion. No rejected "model prediction, not a
  measured result" sentence. Retain threshold flags as findings on a **completed** run —
  never a fabricated pause (ties to the QC-vs-execution fix already shipped in PR #298).

**Chat vs. panel split**
- **Chat completion answer** = concise, entity-aware highlight (flagged liabilities / top-N
  by effect), ≤ a few bullets. (This is already what the live ADMET run shows.)
- **After-run Findings panel** = the full `FindingsDocument` grouped by entity, with
  missing/partial/unavailable states and the shared provenance footer.

---

## 5. Migration (incremental, no big-bang)

1. **Unify the type.** Promote `findings-card.tsx` `KeyResult` → `FindingRecord`; add
   `entity` + `provenanceRef` to `AfterRunReport.tsx` `FindingsKeyResult`; keep snake/camel
   aliases for back-compat. One shared `shared/findings.ts`.
2. **Generalize the extractor.** Implement `tabularPerEntity` + `structuredReport` +
   descriptor registry; port the 4 parsers to descriptors (ADMET first — it already has the
   entity+threshold logic). Keep the LLM fallback, retarget its schema.
3. **Attach provenance + evidence class** in the emitter; render the shared provenance
   footer + evidence-class links (consumes `step-output-preview`).
4. **Renderer (Design's half).** The visual primitive for the grouped entity × metric
   table + per-entity cards + missing/partial states is **Problem 2's Design deliverable**
   (spec + mockup). This doc is its data contract.

**Guardrails:** no new `_parseXOutput`; descriptors are data; every record cites a real
source or is dropped; `herg_ic50_uM` (the live field) — not the `_nM` the stale chain
used. Validate against the schema before render.

---

## 6. Division of labor

| Part | Owner |
|---|---|
| `FindingRecord` / `FindingsDocument` schema (this doc) | Engineering (contract) |
| General extractor + descriptor registry + validator | Engineering |
| Porting 4 parsers → descriptors; retarget LLM fallback | Engineering |
| Visual primitive: grouped entity×metric table, per-entity cards, provenance footer, missing/partial/batch/unresolved/censored states, evidence-class links | **Claude Design** (Problem 2 spec + mockup) |
| Token/color/spacing/layout | Claude Design (exact) |

Next concrete step after sign-off: write the Problem-2 Design brief from §1/§4 (fields,
states, provenance footer, acceptance examples using the three-compound fixture) and, in
parallel, land migration step 1 (the unified `shared/findings.ts` type) behind the
existing consumers.
