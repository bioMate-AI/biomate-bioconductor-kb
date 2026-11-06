# AACT / ClinicalTrials.gov Ingestion — the clinical-outcome layer of BioMate's Target Identification system

**Date:** 2026-10-08
**Status:** PLAN (design only — nothing downloaded; to be OWNED/executed by a separate session).
**Author handoff:** self-contained; read this + the three "context" docs in §9 and you can start cold.
**One-line:** AACT supplies the *clinical-success labels* that turn BioMate's existing target-evidence
(Open Targets genetics + the internal single-cell atlas + ChEMBL/Pharos tractability) into a
**learned, validated target-success prior** — reproducing and extending the Virtual Biotech's
headline finding on our own, on-prem-safe data.

---

## 0. Why this matters (positioning)
The Virtual Biotech (Stanford, *Science* 2026 — `docs/20261008_AGENT_PATTERNS_RESEARCH_AND_BIOMATE_INTEGRATION.md`)
showed that targets with **switch-like, cell-type-specific expression** advance in the clinic far more
often (≈+40% P1→P2, +48% to market, −32% AEs). That result requires **joining clinical trial outcomes
to per-target molecular features.** BioMate already has the molecular-feature half internally; what is
missing is the **trial-outcome half** — the success/failure labels. **AACT is that half.** It is the
single most leveraged data asset to add to target identification, because it is the *label* everything
else is scored against.

## 1. Decision: AACT, not raw ClinicalTrials.gov XML (settled)
- ClinicalTrials.gov's **classic API + classic site were retired 2024-06-25**; the legacy
  `AllPublicXML.zip` (one XML/study) belongs to that retired era. Current native bulk = **API v2 (JSON)**.
- **AACT (CTTI/Duke)** normalizes all of ClinicalTrials.gov into ~50 relational tables
  (studies, phase, overall_status, why_stopped, interventions, conditions, outcomes, results…) **and**
  keeps the free-text fields. So AACT alone feeds BOTH the structured success-prior AND the grounded
  trial-text retrieval — one source, no XML parsing.
- Download forms: **zipped pipe-delimited flat files** (start here; no Postgres needed) or a
  **PostgreSQL `pg_restore` dump** (for full relational joins); daily refresh, monthly archival snapshot.
  AACT is public → **on-prem-safe to mirror.**
- Sources: aact.ctti-clinicaltrials.org/download · /pipe_files · /snapshots.

## 2. What BioMate ALREADY has (reuse — do NOT rebuild). All verified by audit 2026-10-08.
| Need | Already in BioMate | Location |
|---|---|---|
| Target–disease association + **genetic evidence** | **Open Targets** (federated source) | `backend/lib/galaxy/ai/data_sources.py:113` (`DataSource("opentargets", …)`) |
| **Cell-type-specific expression** (the "switch-like" feature) | CELLxGENE immune atlas + **DICE** (cell-type TPM) + **OneK1K** | `s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/` (collected, not yet wired) |
| **Tractability / druggability** | ChEMBL, Pharos, BindingDB | `data_sources.py` (ChEMBL/Pharos); `biomni_data_lake/BindingDB_All_202409.tsv.gz` |
| **Drug → target mechanism map** (critical join, §4c) | ChEMBL + Open Targets drug data (+ BindingDB) | as above |
| Grounded trial-text store | **`corpus_fs`** (FTS5 Protocol+backend, slice 1) | `backend/lib/galaxy/ai/corpus_fs/` (on `feat/orch-retrieval-s2-20261008`; NOT yet on `next-phase`/dev) |
| Source registration mechanism | `federated_query` `_FETCHERS` + `DataSource` entry | `backend/lib/galaxy/ai/federated_query.py` (`_FETCHERS`), `data_sources.py` |
| Parallel execution / verification | `map_reduce.py`, `verification_layer.py`, RunStateStore | `backend/lib/galaxy/ai/` |
| Index backend | **SQLite FTS5 + sentence-transformers** (NO Elasticsearch — do not introduce it) | `vector_search.py`, `local_literature.py` |

**Missing = AACT outcomes + the drug→target join + the success-prior model + the scorer.** That is this plan.

## 3. Target Identification system — architecture (where AACT fits)
```
 D. GROUNDED RETRIEVAL   corpus_fs over AACT trial text + literature  (novelty/precedent per target)
 C. TARGET SCORER/RANKER score candidate targets for a disease by the learned prior + evidence
 B. SUCCESS-PRIOR MODEL  learn: which target features predict phase-transition / approval   <-- AACT labels
 A. EVIDENCE SOURCES     Open Targets (assoc+genetics) · single-cell atlas (cell-type specificity)
                         · ChEMBL/Pharos (tractability) · *** AACT (clinical outcomes = labels) ***
```
AACT is the new Layer-A source and the **label source for Layer B**. Everything above it already exists
or is partially built; AACT unlocks the learn-and-score loop.

## 4. AACT ingestion — detailed design
### 4a. Acquisition
- Pull the **AACT flat-files ZIP** (monthly snapshot) → `s3://biomate-data/aact/<YYYY_MM_DD>/`.
  Record source URL + snapshot date + row counts in a manifest (`manifest.json`) for provenance.
- Refresh cadence: monthly (AACT archives monthly). A small fetcher script (`scripts/fetch_aact.sh`)
  parameterized by snapshot date; idempotent; writes the manifest. **On-prem:** public data, mirror into
  the customer's own bucket — nothing leaves the perimeter.

### 4b. Load — reduced, embeddable by default
- BioMate's on-prem default is **SQLite** (no ES, no mandatory Postgres). Two tiers:
  - **Full AACT** → optional Postgres (`pg_restore`) for deep relational analysis (cloud/dev only).
  - **Reduced outcomes table** (the product artifact) → **materialize to SQLite** so it ships on-prem:
    one row per (study, intervention) with: `nct_id, intervention_name, drug_chembl_id?, target_id?,
    condition(s), phase, overall_status, start_date, completion_date, why_stopped, has_results,
    primary_outcome_met?`. Derived from AACT `studies`, `interventions`, `conditions`,
    `design_group_interventions`, `outcome_measurements`, `reported_events`.
- Keep the derivation SQL in-repo (`backend/.../target_id/aact_reduce.sql`) so a snapshot → reduced table
  is reproducible and auditable.

### 4c. The critical join — intervention → drug → target
AACT records **interventions (drug names)**, not targets. Converting trial outcomes into a *target-level*
success signal requires mapping drug → mechanism target. This is the accuracy-critical sub-task:
1. Normalize intervention free-text drug names (dedup synonyms, strip dose/formulation).
2. Map name → ChEMBL molecule → mechanism target (ChEMBL `drug_mechanism`), cross-checked against
   **Open Targets** "known drugs" (drug→target) and BindingDB where needed.
3. Record mapping confidence + provenance; drop/flag unmapped interventions (never fabricate a target).
Document unmapped-rate as a quality metric; this join's recall bounds the whole success-prior.

### 4d. Success labels (what Layer B learns)
Per target (and per target×disease): define outcome labels from the reduced table, e.g.
- **phase-transition**: did the target's drugs advance P1→P2, P2→P3 (from phase + status across a drug's trials);
- **approval proxy**: reached Phase 4 / `overall_status` approved-equivalent;
- **failure mode**: `why_stopped` / terminated for efficacy vs safety (feeds the −AE angle).
These are correlational labels — treat as a prior to **test**, not assume (see §7).

## 5. Integration into BioMate (concrete, reuse existing seams)
1. **Federated source** — add `DataSource("aact", "AACT / ClinicalTrials.gov", "disease", ["disease","drug","gene"], …)` in `data_sources.py` + `_fetch_aact(query)` in `federated_query.py` (`_FETCHERS`), querying the reduced SQLite for trials by condition/intervention/target. Same shape as every other fetcher; safe-empty when the AACT DB isn't present.
2. **corpus_fs text ingest** — an `aact → corpus_fs` ingester turning each study's `brief_summary`/`detailed_description`/`eligibility`/`outcomes` into block-shaped docs (`/papers/NCT…/sections/…`) for grounded grep (novelty/precedent, feeds the drug-novelty/FTO gate `project_drug_novelty_fto_gate`).
3. **Target scorer** — a new module/workflow (`backend/.../target_id/`) joining the reduced outcomes + the single-cell atlas features + Open Targets evidence → a ranked target list with per-target provenance.

## 6. Slices (phased; matches the portfolio/corpus cadence — each testable, additive, inert until wired)
- **S1 — AACT acquisition + reduced outcomes table + drug→target join.** Download a snapshot, load, build the reduced SQLite, run the drug→target mapping, emit success labels. Acceptance: reduced table row counts sane; drug→target unmapped-rate reported; spot-check 10 known drugs map to correct targets.
- **S2 — AACT→corpus_fs text ingest + `aact` federated fetcher.** Acceptance: grep a condition returns real NCT studies with provenance; fetcher safe-empty without the DB.
- **S3 — success-prior model + scorer.** Learn the prior from labels + target features (incl. cell-type-specific expression), **validate on held-out** (§7). Acceptance: reproduces a sane phase-transition base rate; scorer ranks ≥1 validated target highly; honest held-out metric reported.
- **S4 — wire into product** (target-identification workflow + chat routing). Flag-gated/inert until approved.

## 7. Guardrails (so we don't "bring errors" or over-claim)
- Public data → on-prem safe; mirror into the customer's bucket; monthly refresh with manifests.
- **Reuse infra:** SQLite FTS5 + the existing atlas/Open Targets; **do not introduce Elasticsearch**.
- Grounded-by-construction for all trial text (corpus_fs returns only stored text).
- The **drug→target join recall bounds everything** — measure and surface it; never fabricate a target.
- The Virtual-Biotech success prior is a **hypothesis to validate on our data**, with a proper held-out
  split and a null/base-rate comparison — not an assumed fact. Report correlational caveats honestly.
- Each slice additive + disabled-by-default until a deliberate wiring step.

## 8. Open decisions for the owning session
1. Postgres (full AACT) vs SQLite-reduced-only for the first slice (recommend: SQLite-reduced product artifact + optional Postgres for analysis).
2. Canonical drug→target map: ChEMBL `drug_mechanism` vs Open Targets known-drugs vs BindingDB — pick primary + cross-check (recommend ChEMBL primary, Open Targets cross-check).
3. First disease scope (recommend starting in the immune area, where the internal single-cell atlas is richest).
4. Branch: this is forward work → `integration/next-phase` (not the `cursor/tutorial` dev lineage); corpus_fs must be present there first (currently only on `feat/orch-retrieval-s2-20261008`).

## 9. Context docs to read first (all in `docs/`)
- `20261008_AGENT_PATTERNS_RESEARCH_AND_BIOMATE_INTEGRATION.md` — the Virtual Biotech + the switch-like target-success prior.
- `20261008_BIOMATE_RETRIEVAL_ABILITY_AND_PAPERCLIP_FIT.md` + `20261008_CORPUS_FS_OPTION_B_DESIGN.md` — the `corpus_fs` grounded store this plugs into.
- The internal-corpora audit (this session) — the single-cell atlas / regulatory / knowledge-lake locations (`s3://knowledge-datasets-1759951976/`).
- Memory: `project_drug_novelty_fto_gate`, `feedback_audit_biomate_capabilities_first`, `feedback_verify_data_existence`.
