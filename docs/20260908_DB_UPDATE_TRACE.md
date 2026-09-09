# Workflow DB — Update Trace & Specific Content

**Date:** 2026-09-08
**DB:** `backend/database/galaxy_ai_tools.db` (dev = local, byte-identical: 318,631,936 bytes; 4,210 workflows / 12,312 tools / 3,176 enriched tools).
**Source of this trace:** the DB's own timestamp columns (`created_at`, `indexed_at`, `annotation_v2_at`, `workflow_json_v2_at`, `real_exec_at`, tools.`scientific_context_v2_at`). There is **no separate change-log table** — these timestamps are currently the only update record (see §5 recommendation).

---

## 1. Headline

The DB is **not corrupted** and has **grown** (+155 workflows vs the Aug-2 S3 canonical, enrichment intact). **But the most recent batch — 153 workflows added 2026-09-02 — was indexed and embedded but NEVER enriched or execution-verified.** `0 of 153` have `workflow_json_v2`, `annotation_v2`, or `real_exec` status, while essentially all older workflows do. **This is the concrete "not correctly updated during the upgrade" gap:** new rows are searchable but under-enriched relative to the rest of the catalog.

---

## 2. Update timeline (workflows created & indexed, by date)

| Date | Created | Indexed | Note |
|---|---:|---:|---|
| **2026-09-02** | **153** | **153** | **Most recent batch — the upgrade additions (see §3). NOT enriched/verified.** |
| 2026-08-05 | 2 | – | |
| 2026-07-15 → 07-21 | ~36 | ~12 | mid-July additions |
| 2026-06-16/17 | 10 | 4 | |
| 2026-06-10 | 260 | 897 | main build wave |
| 2026-06-07 | 665 | 1060 | main build wave (largest) |
| 2026-06-04 → 06-06 | 567 | 671 | main build wave |
| 2026-06-03 | – | 147 | |
| 2026-05-09 → 05-27 | ~30 | ~6 | early |

**Enrichment / verification passes (separate from creation):**
| Field | When last run | Count | Covers the Sep-2 batch? |
|---|---|---:|---|
| `workflow_json_v2` (regenerated JSON) | 2026-05-28 | 1,603 | ❌ no |
| `real_exec` (real-execution verification) | 2026-06-09 → 06-11 | ~2,232 | ❌ no |
| tools `scientific_context_v2` | mostly 2026-05-28 (1,739), some 08-02/08-12/08-17 | 3,176 | n/a (tools) |

**Read:** the catalog was built and enriched/verified in **May–June 2026**; the **Sep-2 batch arrived after the last enrichment pass and was never run through it.**

---

## 3. Specific content of the most recent update (2026-09-02, 153 workflows)

**By domain:**
| Domain | Count |
|---|---:|
| drug_discovery | 78 |
| virtual_cell | 12 |
| cryo_em | 12 |
| single_cell | 10 |
| general | 10 |
| genomics | 6 |
| cryo_et | 4 |
| biostatistics | 4 |
| structural_biology | 3 |
| epigenomics | 3 |
| transcriptomics / proteomics / immunology / rare_disease / multi_omics / molecular_dynamics / lab_automation / database | 1–2 each |

**By source/format:** `biomni_nextflow` / `nextflow` = 142; `bioconductor` / `bioconductor_nf` = 11.

**Representative names:** Cohort Qc Triage · Gate3 Interaction Test · Qsp Virtual Population · Virtual Trial Gate3 · 3D Variability Analysis · Cryosparc Standard Spa · Filament Tracer · Global Ctf Refinement · Helical Refinement · Topaz Extract/Train · Et Full Pipeline · Tilt Alignment · Tomogram Reconstruction · (+ drug-discovery/virtual-trial and cryo-EM/ET subworkflows).

*(This batch = the clinical-trial/QSP virtual-trial workflows + the cryo-EM/ET subworkflows that were promoted out of `_archive`, plus drug-discovery additions.)*

---

## 4. The gap (specific, actionable)

For the **153 Sep-2 workflows**, coverage is:
- `workflow_json_v2` (v2 structured JSON): **0 / 153**
- `annotation_v2` (enriched annotation): **0 / 153**
- `real_exec_status` (real-execution verification): **0 / 153**

Consequence: these workflows are **routable and vector-searchable** (embeddings NPZ = 4,210 = full count), but they lack the enrichment/verification the rest of the catalog has — so their routing quality, parameter/step richness, and "verified-executable" status are weaker. This is a **quality/consistency gap, not corruption or data loss.**

Also noted (from the embeddings check): tool embeddings cover 12,288 of 12,312 tools (**24 newest tools unembedded**), and a **stale duplicate** `/app/galaxy_ai_tools_embeddings.npz` (Mar-25, 8,095 vectors) sits beside the correct `/app/database/` one.

---

## 5. Recommendations

1. **Run the enrichment + real-exec verification pipeline on the 153 Sep-2 workflows** so they match the rest of the catalog (`annotation_v2`, `workflow_json_v2`, `real_exec`). This closes the actual gap. Do it on dev against the live DB (do NOT `--rebuild`; that destroys enrichment — memory [[reference_workflow_db_canonical]]).
2. **Re-embed after enrichment** (tool + workflow NPZ) so the +24 tools and any enriched fields are searchable; verify the shipped tool-embeddings NPZ tracks the live DB (the sync ships a prebuilt NPZ that currently lags by 24 tools).
3. **Delete the stale `/app/galaxy_ai_tools_embeddings.npz`** (Mar-25, 8,095 vec) after confirming the search code reads `/app/database/` first.
4. **Add a real change-log** going forward — a small `db_update_log(ts, action, table, n_rows, source, note)` table written by the index/enrich scripts — so future DB updates have an explicit audit trail instead of being reconstructed from per-row timestamps. This aligns with the platform's own provenance/audit posture.
5. **Snapshot to S3** after the enrichment refresh (a new `db-backups/<date>_dev_pull/`) so the canonical is current (last canonical is 2026-08-02).

---

## 6. How this trace was produced (reproducible)
```sql
-- creation/indexing history
SELECT substr(created_at,1,10) d, count(*) FROM workflows WHERE created_at IS NOT NULL GROUP BY d ORDER BY d DESC;
SELECT substr(indexed_at,1,10) d, count(*) FROM workflows WHERE indexed_at IS NOT NULL GROUP BY d ORDER BY d DESC;
-- enrichment/verification passes
SELECT substr(workflow_json_v2_at,1,10) d, count(*) FROM workflows WHERE workflow_json_v2_at IS NOT NULL GROUP BY d ORDER BY d DESC;
SELECT substr(real_exec_at,1,10) d, count(*) FROM workflows WHERE real_exec_at IS NOT NULL GROUP BY d ORDER BY d DESC;
-- specific content + enrichment coverage of the latest batch
SELECT domain, count(*) FROM workflows WHERE substr(created_at,1,10)='2026-09-02' GROUP BY domain ORDER BY 2 DESC;
SELECT sum(workflow_json_v2 IS NOT NULL AND workflow_json_v2!=''),
       sum(annotation_v2 IS NOT NULL AND annotation_v2!=''),
       sum(real_exec_status IS NOT NULL AND real_exec_status!=''), count(*)
FROM workflows WHERE substr(created_at,1,10)='2026-09-02';
```
