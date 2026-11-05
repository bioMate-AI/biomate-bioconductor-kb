# Cross-omics biomarker-driver fusion — method details (2026-11-05)

Companion to `20261104_GENERALIZATION_SESSION_IMPLEMENTATION.md` (§8 item 3: "a real 2nd consumer
for `fuse_channels`"). This documents the method that turns the dormant general fusion engine into
an end-to-end multi-omics biomarker capability, and records exactly how each step works so the
result is reproducible and auditable.

---

## 1. The question this answers

Multi-omics integration (e.g. the SNF run in `snf_multiomics/main.nf`, verified on Batch 2026-11-05,
run `9d889185`) assigns each patient to a **subtype**. The immediate clinical follow-up is:

> *Which features (genes, proteins, methylation sites) drive those subtypes — and which are
> corroborated across more than one omics layer rather than being a single-assay artifact?*

A feature strong in **two** layers is far more trustworthy than one strong in a single, possibly
noisy layer. Ranking by cross-layer corroboration is exactly a multi-source **evidence-fusion**
problem — the same shape as target identification (fuse several evidence channels into one ranked,
confidence-tiered list).

## 2. Why this was a gap

`target_id.arbiter.fuse_channels` is a **domain-neutral** fusion engine, and
`multiomics.evidence_fusion.fuse_omics_biomarkers` already adapts it to omics layers. But
`fuse_omics_biomarkers` takes a **precomputed** `{layer: {feature: score}}` — the per-layer evidence
that a feature separates the subtypes. **Nothing computed that score from real matrices + subtype
labels**, so the engine stayed dormant for multi-omics (the audit's "generality unexercised"). The
missing piece is a **scoring step**: `(layer matrices, subtype labels) → {layer: {feature: score}}`.
`biomarker_fusion.rank_cross_omics_drivers` is that step. It is the realized second, independent
consumer of `fuse_channels` (the first being target-ID) — Pattern A ("general core, one consumer")
is now actually exercised across two domains.

## 3. The method, end to end

```
layer matrices (features × samples, per layer)  +  subtype labels {sample: subtype}
        │
        ▼  (per layer, per feature)
one-way ANOVA F-statistic of the feature's values across the subtype labels      ← SCORING (new)
        │  →  {layer: {feature: F}}
        ▼
fuse_omics_biomarkers → fuse_channels (EvidenceGate, robust per-layer null)       ← FUSION (existing)
        │
        ▼
ranked drivers: {entity(feature), score, tier, n_fired, fired_channels}
```

### 3.1 Scoring — one-way ANOVA F per feature per layer (`_f_statistic_per_feature`)

For each layer matrix (features × samples) and the subtype label of each sample, each feature gets a
one-way ANOVA **F-statistic** across the subtype groups:

```
F = (SS_between / df_between) / (SS_within / df_within)
    df_between = k − 1            (k = number of populated subtype groups)
    df_within  = n_total − k      (n_total = labelled samples across those groups)
```

- **F is between-subtype variance ÷ within-subtype variance** — high when a feature's values differ
  sharply between subtypes relative to their spread within a subtype, i.e. a strong driver.
- **Why F (not a t-test or fold change):** it generalizes to ≥2 subtypes, is a pure ratio (so a
  layer measured on a different scale isn't privileged), and raw cross-layer comparability does not
  matter — the fusion engine re-calibrates each layer against its own null (§3.2), so the scorer only
  has to rank features correctly *within* a layer.
- **Edge handling (never NaN/inf into the engine):**
  - a feature with no within-group variance but non-zero between-group signal (perfect separation) is
    capped to a large but **finite** `F = 1e6` — ranks at the top without poisoning the layer's null
    with `inf`;
  - a flat/constant feature, a single populated group, or samples with no labels → `F = 0`
    (uninformative). So an ID/metadata column contributes no evidence rather than noise.

Validated in isolation: a planted driver scored **F≈604**, a flat feature **F≈2.8**, perfect
separation **F=1e6**, and the no-label case **F=0**.

### 3.2 Fusion — `fuse_channels` via `fuse_omics_biomarkers`

Each layer is a **channel** of `{feature: F}`. The default `EvidenceGateArbiter` (`method=
"evidence_gate"`):

1. **Per-channel robust null + z (`null_method="robust"`):** within each layer, each feature's F is
   converted to a robust z against that layer's own distribution (median / MAD). This is what makes
   cross-layer corroboration fair — a layer with uniformly large raw F values doesn't dominate,
   because every layer is scored against itself.
2. **Gate at `z_thresh = 2.0`:** a feature "fires" in a layer when its z ≥ 2.
3. **Convergence tier (OR/AND):** fires in **≥2 layers → `corroborated`**; **1 layer → `nominated`**;
   **0 → `none`**. `n_fired` and `fired_channels` record which layers fired.

`method="harmonic_sum"` is available for a weighted variant (per-layer reliability `weights`), e.g.
down-weighting a noisier assay.

### 3.3 Output

A ranked list of dicts: `entity` (the feature), `score`, `tier`, `rank`, `n_fired`,
`fired_channels`, `per_channel_z`. Corroborated drivers sort above nominated ones; `top_k` truncates.

## 4. Worked example (the unit test)

`biomarker_fusion_test.py` builds three layers over 20 patients (subtype A = even, B = odd):
`DRV` separates the subtypes strongly in **rna + protein**; `SOLO` separates only in **methyl**;
all other features are near-flat. Result: `DRV` ranks **first**, `tier=corroborated`, `n_fired≥2`,
`fired_channels ⊇ {rna, protein}`; `SOLO` is present but `nominated` (`n_fired=1`). Empty input → `[]`;
no labels → nothing fires.

## 5. Provenance and generality

- Same engine, two domains: `fuse_channels` now ranks **targets** (target-ID) and **omics
  biomarkers** (here) with one code path — the generality is exercised, not asserted.
- Deterministic and auditable: F-statistics are a fixed formula; the engine's z/gate/tier are
  recorded per feature (`per_channel_z`, `fired_channels`), so every ranking is explainable.
- Serves the SYSUCC / faculty **stratification spearhead**: subtype a cohort by multi-omics, then
  name the RNA/protein/methylation drivers that **agree across layers**.

## 6. Status

- **Built + unit-tested:** `backend/lib/galaxy/ai/multiomics/biomarker_fusion.py` +
  `biomarker_fusion_test.py` (10 cases incl. the orchestrator + parsers). `py_compile` clean under
  3.9; scoring + parsers validated in isolation; fusion covered by `evidence_fusion_test.py`.
- **WIRED into the live findings path (backend findings hook, option 1 below).** The
  `/api/nextflow/analyze-outputs` endpoint (`nextflow_executor.py`), after `OutputAnalyzer`, now runs
  a best-effort block: when the run produced a subtype/cluster CSV (`snf_clusters.csv` /
  `patient_stratification.csv`) AND the run record's `parameters.omics` has ≥2 layers, it recovers
  the layer URIs via `_run_lookup(run_id)`, reads each (boto3 in the backend, AWS-CLI fallback) and
  the cluster CSV, calls `drivers_from_run`, and appends the top corroborated drivers to the run's
  Findings (`key_results` + a `summary`/`next_steps` note). Guarded so it never breaks findings.
  - `drivers_from_run(cluster_csv_text, omics_uris, fetch_text=…)` is the testable orchestrator:
    parse clusters (`_parse_cluster_csv`) + read/parse each matrix (`_parse_feature_matrix`) →
    `rank_cross_omics_drivers`. `fetch_text` is injectable, so the whole path is unit-tested with no
    network (`DriversFromRunTest`, `ParserTest`).
- **Live-verified in the dev Galaxy backend (2026-11-05).** `drivers_from_run` was run inside the
  `biomate-galaxy-dev` container against real S3 artifacts: it read a cluster CSV + three omics
  matrices via boto3, scored (F-stat) and fused (`fuse_channels`), and correctly returned
  `GENE0 → rank 1, corroborated, n_fired=2 ['rna','protein']` (the planted shared driver), with
  single-layer features `nominated` and a flat feature scored 0. This exercises the whole chain —
  boto3 S3 read, matrix/cluster parsing, scoring, per-layer-null fusion, corroboration ranking — in
  the production backend. (An earlier live run on the SNF smoke's own outputs executed the path but
  showed `corroborated=0`, correctly: those matrices used layer-prefixed feature names, so no
  feature is shared across layers — corroboration is structurally impossible there, a data artifact
  not a code issue.)
- **Full HTTP endpoint live-verified (2026-11-05).** `POST /api/nextflow/analyze-outputs` for the
  SNF run (`9d889185`) returned **HTTP 200** and attached **10 `driver:` findings** to the run's
  `key_results` plus the "Cross-omics biomarker fusion ranked …" summary note — the complete path:
  run-record `omics` recovery (`_run_lookup`) → S3 read → scoring → fusion → attach to
  `AnalysisResult`. (Those drivers are `nominated`/single-layer because the SNF smoke matrices use
  layer-prefixed feature names; corroboration is shown by the shared-feature live run above.)
  - A pre-existing latent bug surfaced and was fixed in the same endpoint (commit `d4b735273`):
    six `logger.` references where the module logger is `log` — they would `NameError`→500 on any
    except path (analyzer, citation, report, figures, save, and the new biomarker block). All six
    now use `log`, so a failure in any of those is logged and the endpoint degrades gracefully.

### Design note — why the backend hook, not a Nextflow step
The alternative (a Python `BIOMARKER_FUSION` Nextflow process after SNF) would need a new/extended
image carrying the multiomics/target_id packages + numpy. The backend hook needs neither — the
Galaxy backend already has numpy + the multiomics package — and it reuses outputs + inputs the run
already produced, so it adds a finding with no extra compute.

## 7. Files

| File | Role |
|---|---|
| `backend/lib/galaxy/ai/multiomics/biomarker_fusion.py` | scoring (ANOVA F) + `rank_cross_omics_drivers` entry point |
| `backend/lib/galaxy/ai/multiomics/biomarker_fusion_test.py` | 5 unit tests (corroborated-ranks-first, nominated vs corroborated, F-scoring, empty/unlabeled, top_k) |
| `backend/lib/galaxy/ai/multiomics/evidence_fusion.py` | the omics adapter over `fuse_channels` (existing) |
| `backend/lib/galaxy/ai/target_id/arbiter.py` | `fuse_channels` — the general engine (EvidenceGate / HarmonicSum) |
