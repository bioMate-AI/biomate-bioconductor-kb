# Requirement: per-workflow QC gates for Bioconductor DESeq2 (and other bioc chains)

**Date:** 2026-06-17
**For:** handoff to a dedicated QC-config session
**Branch context:** `qc/coverage-and-rebuilds` (current HEAD already 92 commits ahead of `integration/next-phase`; merge-clean as of 9231cd27cd)
**Background investigation:** `docs/20260617_RESEARCHER_OUTREACH_SESSION.md` §"What did NOT happen"; this file extends it.

---

## Problem (precisely scoped)

The Bioconductor DESeq2 tutorial design (`reference/claude_design/bioconductor-handoff/src/BiocTours.jsx:169`) promises the QC audit tab and per-phase QC block show **gene-retention, size-factor range, replicate count** gates with "threshold, observed value, result and action."

Dev today:

| Layer | Status |
|---|---|
| Per-phase QC renderer (`.qc-block` / `.qc-head` / `.qc-gate` / `.qc-autoloop`) | ✅ implemented at `frontend/client/src/components/nextflow-workflow-viewer.tsx:736-780` and `frontend/client/src/v2/PhaseCard.tsx:105` |
| Live `/api/qc/profiles` endpoint returns 47 profiles including `rnaseq_polya_standard` | ✅ live (verified 2026-06-17 via `curl http://localhost:8081/api/qc/profiles`) |
| `rnaseq_polya_standard.overrides` (the rnaseq-specific gates) | ❌ empty `{}` |
| Global `defaults` keys: `reads_surviving_pct`, `fit_quality` (cryo-EM), `mito_fraction_pct` (scRNA), `alignment_rate` | ⚠️ none of these are DESeq2-specific |
| The 3 design-promised DESeq2 gates (`gene_retention`, `size_factor_range`, `replicate_count`) | ❌ not registered anywhere in the backend QC catalog |

For a real bioc DESeq2 run the qc-block today will render with **at most one borrowed gate** (`alignment_rate`, from rnaseq domain detection) — not the 3 the design promises.

## Hard constraint: no invented thresholds

Per `CLAUDE.md` §"Engineering Discipline: Resolve Root Causes — Never Workaround" and the existing QC evidence convention (`backend/config/qc_evidence.yaml`), **every numeric threshold must have a published-paper citation or a consortium SOP reference.**

The DESeq2 literature does not supply hard thresholds for these gates:

- **gene-retention**: Love 2014 + edgeR `filterByExpr` use diagnostic plots, not a pass/fail %. No canonical "fail if < X" exists.
- **size-factor range**: Anders & Huber 2010 mention informally that sample size factors should sit within ~10× of each other; never written as a hard threshold.
- **replicate count**: DESeq2 *runs* with N≥2; *recommends* ≥3 (Love 2014 FAQ). The "3" is convention, not a published cutoff.

Inventing `{bound: 0.6}` / `{bound: 3.0}` / `{bound: 3}` would ship fake thresholds attributed to BioMate. **Do not do this.**

---

## Path A — per-workflow `qc_metrics.json` (recommended)

Replace the global-catalog approach with per-workflow QC emission, mirroring what cryo-EM and drug-discovery domains already do.

### What the workflow emits

Each bioc workflow's `main.nf` adds a final QC process step that writes `qc_metrics.json` to its output dir, e.g. for `bulk_rnaseq_de_analysis`:

```json
{
  "phase": "phase_A_qc_filter",
  "domain": "bioc_rnaseq_de",
  "gates": [
    {
      "key": "gene_retention",
      "label": "Gene retention after filterByExpr",
      "value": 14823,
      "value_total": 25341,
      "value_pct": 58.5,
      "threshold": null,
      "threshold_source": "diagnostic_only",
      "direction": "diagnostic",
      "action": "pass",
      "rationale": "edgeR::filterByExpr is a diagnostic; retention < 30% may indicate over-aggressive cutoff but has no published hard threshold."
    },
    {
      "key": "size_factor_range",
      "label": "DESeq2 size-factor range (max/min)",
      "value": 2.3,
      "threshold": 10.0,
      "threshold_source": "Anders & Huber 2010 §6 (informal)",
      "threshold_doi": "10.1186/gb-2010-11-10-r106",
      "direction": "max",
      "action": "pass",
      "rationale": "Per-sample size factors should fall within ~10× of each other; > 10× suggests technical confounding."
    },
    {
      "key": "replicate_count",
      "label": "Min biological replicates per condition",
      "value": 3,
      "threshold": 3,
      "threshold_source": "Love 2014 (DESeq2 paper) FAQ; recommendation, not hard requirement",
      "threshold_doi": "10.1186/s13059-014-0550-8",
      "direction": "min",
      "action": "pass",
      "rationale": "DESeq2 dispersion estimates stabilize at N≥3; runs with N=2 produce wide CIs."
    }
  ]
}
```

Three things to notice:

1. **`threshold` may be `null`** with `threshold_source: "diagnostic_only"` — that's the right answer for `gene_retention`. The gate appears in the panel as informational (observed value + rationale), no pass/fail badge. Renderer needs a tiny code change to handle `direction: "diagnostic"`.
2. **`threshold_source` + `threshold_doi`** appear in every row, so the QC audit tab (and the `(why?)` anchor) can cite where the number came from.
3. **`action`** is computed by the workflow itself — not by the frontend or the QC monitor. The workflow knows its own data and references.

### Backend reader

`backend/lib/galaxy/ai/qc_trace_monitor.py` (or equivalent) already reads `qc_metrics.json` for cryo-EM / drug-discovery domains. Extend it to:

1. Recognize `bioc_*` domain names.
2. Pass the gates array through to the existing SSE event `autoloop_gate_results` so the frontend renderer (which already exists) picks them up.

### Frontend renderer changes

Two tiny additions to `nextflow-workflow-viewer.tsx` (`auto-loop-panel.tsx` doesn't apply to bioc — no halt-and-retry):

1. Support `direction: "diagnostic"` in the gate-action helper: render as a neutral chip, no pass/halt badge.
2. When `threshold_source` is present, link/tooltip the threshold value to its source citation.

### Files to touch

| File | Change |
|---|---|
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/deseq2/*.nf` (3-5 files) | Append a `BIOC_DESEQ2_QC` process that writes `qc_metrics.json` |
| `backend/lib/galaxy/ai/qc_trace_monitor.py` | Recognize bioc domains; pass gates through |
| `backend/config/qc_evidence.yaml` | Add bioc DESeq2 domain block citing Anders 2010 + Love 2014 |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx:736-780` | Handle `direction: "diagnostic"`; render `threshold_source` tooltip |
| `backend/tests/test_qc_trace_monitor.py` | Add test: fake `qc_metrics.json` with the 3 DESeq2 gates → SSE event payload → assert all 3 surface |
| `frontend/e2e/researcher-chains-audit.e2e.ts` or new `bioc-deseq2-qc.e2e.ts` | Real-dispatch test using **fixture login** (`lifeifei163361@163.com`; see `frontend/e2e/allometric-qc-coverage.e2e.ts` for the canonical pattern). **Do not register per-test users.** |

### Effort estimate

- Plumbing: ~half-day
- Per-workflow `qc_metrics.json` emit (3-5 .nf files for the deseq2 family): ~2 hours each
- Tests: ~2 hours

Total: **~1 day** for the full bioc DESeq2 chain end-to-end.

---

## Path B — global literature-curated thresholds (alternative, more work)

If you want gates to appear in the catalog *before* a run dispatches (e.g., so the panel shows them pre-run as the workflow's "what we'll check"), curate global thresholds from large-consortium SOPs that DO publish hard cutoffs:

- **ENCODE RNA-seq pipeline** — has gene-detection-rate and replicate-correlation cutoffs (published in their data standards doc)
- **GTEx v8 pipeline** — has minimum sample-correlation and intronic-rate gates
- **GDC mRNA pipeline** — has FastQC pass criteria

This is real curation work — **~2-3 hours per gate per source** with proper citation. Risk: SOPs change; need a re-audit cycle.

Path A is cleaner because each workflow speaks for its own QC, with citations attached at the data level.

---

## Out of scope

- Renderer rewrite (the renderer at `nextflow-workflow-viewer.tsx:736` already handles the design's class structure — no need to touch CSS classes or DOM)
- The cryo-EM-style `AutoLoopCard` halt-and-retry overlay — DESeq2 doesn't have a halt-and-retry pattern; just pass/advisory/diagnostic
- The After-run "QC audit" tab content — already populated via the same gate stream once `qc_metrics.json` is emitted
- Any test using throwaway emails (`@biomate.test`, `Date.now()`-suffixed). Per project memory `feedback_unified_e2e_fixture_user.md`, all e2e auth goes through the fixture account.

---

## Acceptance criteria

1. `qc_metrics.json` emitted by `bulk_rnaseq_de_analysis` chain on a real dispatch contains ≥3 gates: `gene_retention` (diagnostic), `size_factor_range` (max), `replicate_count` (min). Each gate carries `threshold_source` + (where applicable) `threshold_doi`.
2. Live `/api/runs/<run_id>/qc` returns the gates exactly as emitted by the workflow.
3. Frontend phase card renders `.qc-block` with the 3 gates, including diagnostic-mode gates (no pass/halt badge).
4. `(why?)` anchor on each gate threshold shows the citation source.
5. Unit test `test_qc_trace_monitor.py` covers the diagnostic-mode action path.
6. New e2e `bioc-deseq2-qc.e2e.ts` dispatches the chain via fixture login and asserts the 3 gates appear in the rendered DOM. Run wall-clock ≤ 5 min.
7. No invented thresholds — every `threshold` value has a `threshold_source` field.

---

## Background reading for the next session

- `docs/20260617_RESEARCHER_OUTREACH_SESSION.md` — last session's summary
- `docs/20260616_TIER0_DRUG_DESIGN_CITATIONS_FIX.md` — pattern that closed the same gap for tier-0 drug-discovery chains
- `backend/config/qc_evidence.yaml` — existing citation format
- `frontend/e2e/allometric-qc-coverage.e2e.ts` — canonical fixture-login e2e pattern
- `frontend/client/src/components/nextflow-workflow-viewer.tsx:736-780` — the renderer that already speaks design's class names
- `reference/claude_design/bioconductor-handoff/src/BiocTours.jsx:169` — design source for the gate categories
- `reference/claude_design/bioconductor-handoff/src/PhaseCard.jsx:101-126` — design's QcBlock component
- Love, M.I., Huber, W. & Anders, S. *Moderated estimation of fold change and dispersion for RNA-seq data with DESeq2.* Genome Biology 15, 550 (2014). doi:10.1186/s13059-014-0550-8
- Anders, S. & Huber, W. *Differential expression analysis for sequence count data.* Genome Biology 11, R106 (2010). doi:10.1186/gb-2010-11-10-r106
