# Appendix E — Coverage & Roadmap (What Is *Not* Yet Supported)

This is the honest counterweight to the rest of the manual. Everything the book documents as **supported**
is green in `docs/user-manual/coverage-ledger.md`. Everything below is **not** sold as present — it is a
🗺️ roadmap item (not built / not verified) or a 🔧 known doc-vs-code mismatch already corrected in the
chapters. If a capability is here, do **not** rely on it as shipping today.

Compiled directly from the coverage ledger. Two legends:

- **🗺️ roadmap** — not built, not provisioned, or unverified. Do not promise it.
- **🔧 mismatch (resolved)** — a draft/tutorial/config claim that did not match the real system; the
  chapter now states the code truth. Listed so the discrepancy is on the record.

---

## Interactive tools & environments

| Item | Status | Note / source |
|---|---|---|
| Interactive-tool launch — RStudio / Jupyter / CellxGene | 🗺️ | Not provisioned on dev (`/api/interactive/available` → `available:false`); launch buttons are honesty-gated (hidden), not broken. When present, they open an **empty** session (do not auto-load run data). |

## Drug discovery → IND

| Item | Status | Note / source |
|---|---|---|
| Analogue / de-novo generation as auto-loop remediation | 🗺️ | Not built. Auto-loop tightens the library filter (compound drops out); it does not invent analogues. `param_tuner.py` |
| Dev TOTP e-signature accepts any 6 digits | 🗺️ | `ind_actions_router.py._verify_totp` — dev caveat; real MFA enroll/verify is roadmap |
| Toxicology §2.6.3 (single/repeat-dose, genotox in-vivo) | 🗺️ (partial) | Renders "Awaiting GLP data" placeholder without wet-lab data |
| Non-FDA region section rendering | 🗺️ | Returns `not_implemented` |
| "Submit to FDA" button | 🗺️ | Disabled — no submission endpoint |
| NDA-fetch (NDA → PK params) | 🗺️ | Honestly disabled ("coming soon"); no scraper |
| Manuscript "Stage 6" | 🗺️ | Not built — IND ends at DOCX; post-assembly is a user edit flow only |
| PBPK reference set size | 🗺️ | 30 marketed drugs (smaller than 100–300 full-regulatory sets); stated as-is |
| PBPK model = "one-compartment / well-stirred liver" (reference draft) | 🔧 | Wrong: real model is 8-compartment Rodgers–Rowland ODE. Chapter uses the real model |
| "C16→C4 remediation implies analogue generation" (draft/tasklist) | 🔧 | Real auto-loop only tightens the filter; chapter clarifies |

## Transcriptomics (bulk RNA-seq)

| Item | Status | Note / source |
|---|---|---|
| Fusion / splicing / RNA-variant end-to-end worked examples + gold validation | 🗺️ | Workflows exist and route (rnafusion, rnasplice, dexseq, sgseq, circrna, rnavar); deep per-workflow documentation is roadmap |
| Bulk-RNA auto-loop remediation | 🗺️ | Not built — QC fixes are manual (only ADMET has auto-loop) |
| Salmon mapping-rate gate: tutorial says ≥70%, code default is 50% | 🔧 | Chapter states the enforced 50%; treats 70% as interpretive target |
| DESeq2 sample-distance "2 clear clusters" presented as a gate | 🔧 | Real system produces the plot but has **no** automated pass check; chapter labels it visual/advisory |
| Old tutorial STAR+featureCounts + mapping>80% gate | 🔧 | Production chain uses STAR+Salmon; chapter follows real star_salmon path + code-enforced 70% STAR gate |

## Single-cell RNA-seq

| Item | Status | Note / source |
|---|---|---|
| In-app single-cell UMAP/cluster/marker panel on real runs | 🗺️ (data-gated) | Front end verified; needs a live scRNA run to populate the `summary.json` sidecar (none fired) |
| `max_pct_mito` = 20% (`.nf`) vs 10% evidence for most tissues | 🔧 | Chapter documents code truth (20%) with a 10% interpretive tip |

## Variant calling / genomics

| Item | Status | Note / source |
|---|---|---|
| Somatic variant calling (Mutect2 tumour-normal full chain) | 🗺️ | Workflows exist and route (ids 1771/1779/1744/10608) but there is **no** chain and **no** gold demo |
| Ts/Tv 1.8–2.2 presented as a gate | 🔧 | It is in-pipeline ADVISORY, not an enforced gate; hard-filter (not VQSR) is the single-sample default |

## Cryo-EM

| Item | Status | Note / source |
|---|---|---|
| EMPIAR-10025 gold standard | 🗺️ | Missing from `gold_standards.yaml` |
| Cryo-EM auto-loop | 🗺️ | Not wired to the live executor |
| Cryo-ET + cryptic-pocket mega-chain | 🗺️ | Excluded — does not run |
| Tutorial "MotionCor2/Topaz/DeepEMhancer, CTF>0.2, GSFSC<3.5Å, hetero-refine" | 🔧 | Does not match CryoSPARC-native pipeline; chapter uses code truth (≥0.70 CTF, ≤4Å FSC, no hetero) |

## Structural biology (largest unverified surface)

| Item | Status | Note / source |
|---|---|---|
| Foldseek / MMseqs2 / MD / AlphaFold-Multimer (T17–T20) end-to-end | 🗺️ | Wired + indexed but **E2E UNVERIFIED** / smoke-test-gated; no local Foldseek/AF-DB copy |
| DepMap / BindingDB | 🗺️ | Snapshot wrappers, **not** live API |

## Multi-omics / systems biology

| Item | Status | Note / source |
|---|---|---|
| GWAS→scRNA→eQTL target-ID chain | 🗺️ | Must be verified to run before it is documented (unbuilt/unverified) |

## Pharmacology / clinical

| Item | Status | Note / source |
|---|---|---|
| FAERS pharmacovigilance | 🗺️ (pending E2E) | WIRED + indexed (id 11363) — **not** a hard gap, but not yet E2E-verified. `bioconductor/faers/main.nf` |

## Public data & accession resolver

| Item | Status | Note / source |
|---|---|---|
| PDB / EMDB / EMPIAR / PRIDE / MassIVE + UniProt / Ensembl / ChEMBL / dbSNP / ClinVar fetch | 🗺️ | Detected for **validation only**, **not** resolvable (return 422). Only GEO / SRA / ENA / DDBJ / BioProject / ArrayExpress resolve to a fetch |
| dbGaP | 🗺️ | Absent |
| Second `/api/accession/resolve` handler (with PDB/EMDB) | 🔧 | Shadowed **dead code** — Express serves the first handler; not reachable |

## Search & evidence / literature

| Item | Status | Note / source |
|---|---|---|
| Patent / FTO corpus | 🗺️ | No patent corpus; the "Patents" track returns literature |
| Formatted APA/BibTeX for literature answers | 🗺️ | Populated only for workflow-tool citations; literature is APA-only / partial |
| Locus / recency fields on live answers | 🗺️ | Never populated |
| Source reader | 🗺️ | Link-out only; full text not rendered in the reader |
| "Save to project" = versioned Files doc | 🗺️ | It is a knowledge **note**, not a versioned document |

## Modules — UI/feature gaps (Part I)

| Item | Status | Note / source |
|---|---|---|
| Cold start: "Start"/normalized-seed button, thin launcher, project-scope line | 🗺️ | Seeds raw text only (I.1) |
| Composer: chip quality dot / id@version / kind; @-mention typeahead; URL-paste quality card; inherited-vs-deviated experts | 🗺️ | I.2 |
| Files: clickable "Open run" in lineage/consumers; cross-project browser | 🗺️ | Static text today (I.5) |
| Full step view from the after-run report Outputs tab | 🗺️ | Reaches StepOutputPreview but not the full step view (report lacks per-step params) (I.7) |
| "Re-run from here" inside StepDetail on the run panel | 🗺️ | Not wired; re-run via step-row/report instead (I.7) |
| Reproducibility checksums default-on | 🗺️ | Opt-in (`?checksums=1`); column shows "—" until you press Compute checksums (I.9) |
| Report chat-edit (propose-diff); manuscript Stage 6; cross-run report | 🗺️ | Hand-edit + Save version only (I.9) |
| Projects: owner-transfer UI; share-link create UI | 🗺️ | Backend exists (PATCH /owner, expiry honored) but **no UI** (I.4) |
| Models: "start training" / "launch loop" control on the panel | 🗺️ | 3 of 5 tracks read-only; training via chat (I.10) |
| Design & generate: peptide/biologic modalities | 🗺️ | Forms render, generators not wired; small-molecule round is the built path (I.11) |
| Connectors: Skills tab in the dialog | 🗺️ | Commented out (0 entries) (I.12) |
| Pre-run per-run cost estimate | 🗺️ | `CostEstimateBadge` off; no per-run estimate shown (I.13) |

## Catalog / inventory counts (`/capabilities`, stale strings)

| Item | Status | Note / source |
|---|---|---|
| Workflow/domain counts | 🔧 | Live catalog = **4,200 workflows / 42 domains / 70 chains** (direct DB count). Stale strings elsewhere say "2,455/34" (CLAUDE.md, `tools_manifest.py:118`) and "4,017/36" (MCP blurb) — treat those as out of date |

---

## The long tail — documented nowhere, by design

Per the book plan, these domains have **no** built tutorials and are intentionally **not** chapters;
documenting them would over-promise: imaging / bioimaging, population genetics, immune repertoire,
synthetic biology, ag-genomics, glycoengineering, and aspirational clinical diagnostics. They may appear
in the workflow catalog by keyword, but there is no verified end-to-end path.

---
*This appendix is the single place a capability may be listed as absent. If any other chapter appears to
promise something here, the chapter is wrong and this appendix wins.*
