# BioMate gap register and fill-and-test plan (2026-11-01)

Companion to `docs/20261101_BIOMATE_CAPABILITY_AUDIT.md` (what is true today). This document lists only
**what is missing or wrong**, how to close each gap, and the full test that proves it closed. Nothing
here has been fixed yet. Sources for every gap are in the audit; IDs map as noted.

**Principles (from project rules).** Fix root causes, not workarounds (CLAUDE.md). Review the diff and
predict the outcome before any expensive run. Run experiments on EC2 spot or Spark, never the laptop.
Every number in a result is computed by script from the recorded output. Every closure leaves a dated
record (database `real_exec_*` fields or a dated document). Code changes pass the pre-sync checklist
(`docs/PRE_SYNC_CHECKLIST.md`) and are then verified on dev with the fixture account.

**Type tags.** CODE (change in repo) · OPS (environment or deployment) · DATA (needs a dataset or gold
set) · EVAL (needs a measured benchmark). **Size.** S (under a day), M (days), L (a week or more).
**Priority.** P0 = a first meeting with a hospital IT or data leader would expose it, or a number or
claim is wrong now. P1 = needed for a headline ability of the BD offer. P2 = needed for a specific
direction. Costs are not estimated here; each paid run needs an estimate approved first.

---

## A. Claims that are wrong today (fix the wording now, independent of the engineering)

| # | Current statement (BD supplement or earlier notes) | Evidence says | Reword to |
|---|---|---|---|
| W1 | "1,092 workflows with clean real-execution evidence" | 696 observed-clean; 1,103 including 407 provisional; latest record 2026-10-15; 1,879 never tested | "4,223 indexed; 696 observed-clean (1,103 including assumed status)" |
| W2 | "42 domain categories" / "more than 60 databases" | 42 tags but about 36 curated; registry has 58 sources, 54 live, about 20 searchable from chat | "about 36 curated domains; about 54 live sources, about 20 reachable from chat" |
| W3 | "unverifiable references are refused" | The system drops them or falls back to the grounded backend answer; no explicit refusal | "answers are limited to retrieved references; unsupported ones are dropped" |
| W4 | "every statement traces to a source" | Channel-level provenance only; no per-target links; LLM-channel scores have no references | "each target shows which channels support it, with source names; per-target links are planned" |
| W5 | Network and pathway channels listed as live | Not in the live route or chat tool | "available in the evidence engine; being connected to the service" |
| W6 | Client data "entered as an extra channel" | Mechanism only: server-path score files; no converter, upload or scoping | "the engine can take a per-gene score table; automatic conversion from analyses is being built" |
| W7 | Drug-type guidance | No code | Remove, or "planned" |
| W8 | Nominate-then-validate | Built, not wired into route, chat or UI | "planned for the service interface" |
| W9 | "BOIN" accuracy / PBPK | No BOIN accuracy record; PBPK 0.53 within 2-fold (local), below 0.60 | "dose-escalation simulation"; quote PBPK as first-pass only |
| W10 | Learning from experiments | Demonstrated with simulated assays; fixes uncommitted; refit not gated by holdout | "demonstrated on simulated assay data" |
| W11 | "On-premises, data stays with the hospital" | Cloud model defaults; analytics and fonts load by default; clean-host install untested | "designed for on-premises; clean-host install under test" |
| W12 | Tumour-reactive T cells, docking and ADMET accuracy, FIH biologic dose | Not demonstrated or failed validation | Do not claim |
| W13 | "imaging" data analysed (supplement section 3.1, 4.2) | Pathology slides and microscopy images are supported; radiology (CT, MRI, PET, radiomics) has no verified workflow; no image-archive or hospital-system connector | Say "pathology and microscopy images"; say radiology is not a verified capability |

---

## B. Gap register

### B1. Target identification and evidence search (T)

| ID | Gap (audit ref) | Type / size / priority | Fix | Full test (acceptance) |
|---|---|---|---|---|
| T1 | Client data cannot enter as an evidence channel safely (A4, B5) | CODE · L · **P0** | Adapters from analysis outputs to `target,score` tables (DE, recurrence, cell-type specificity, surface protein, survival, dependency); register results per project by dataset ID, not server path; chat and route parameter; default weight for the client channel; path allow-list | Run DESeq2 on a public tumour-vs-normal cohort (e.g. TCGA-BRCA). Auto-build the table; call target identification. Pass: known drivers (ERBB2, ESR1) appear in the top 20; `channels_run` names the client channel; provenance cites the run id; a request for an arbitrary server file path is rejected |
| T2 | STRING and pathway channels not in the live route (A2) | CODE · S · P1 | Add to `default_channels` (seed genes from the Open Targets top N); regenerate OpenAPI and connector manifest | Melanoma via REST, chat tool and connector: `channels_run` includes `ppi_string` and the pathway channel; `channel_errors` empty |
| T3 | No per-target source links (A11) | CODE · M · **P0** | Add `evidence_links` per target and channel (Open Targets page, STRING, PMIDs); evidence table in the UI; label LLM-only evidence "model judgment, no citation" | Top 10 targets each show at least one resolvable URL per fired non-LLM channel; a link checker passes |
| T4 | Nominate-then-validate not wired (A5) | CODE · M · P1 | `validate=true` option, chat card with launchable workflows | Melanoma top 5: each returns at least one real catalogue workflow per intent and the workflow launches |
| T5 | No drug-type (modality) selector (A6, C1) | CODE+DATA+EVAL · L · P1 | Rule-based selector (location, interface, druggability, size) with a rationale; or retire the claim | 100 approved targets with known modality: agreement with expert panel at a stated target (proposed at least 80%); each decision cites its input properties |
| T6 | No restricted-network or offline mode (A8, D5) | OPS+CODE · L · **P0** | Open Targets and STRING snapshots as table channels with a stated refresh; vetted allow-list document; degraded-mode behaviour documented | Egress blocked except the allow-list: the response states which channels failed and snapshot channels still produce a ranking |
| T7 | Open-model LLM channel unmeasured; LLM does not affect live ranking (A7, D3) | EVAL+CODE · M · **P0** | Run the existing benchmark with DeepSeek and Qwen endpoints; handle reasoning-model output; decide the LLM's ranking role | Same gold as the frontier-model benchmark: report the lift and the parse-error rate; stated thresholds met |
| T8 | No explicit refusal; reference existence not checked (A1) | CODE · M · P1 | PMID and DOI existence check on the final bibliography; refusal when no reference is grounded | 20 fixed questions (5 with no literature): every cited PMID resolves; the 5 return a refusal |
| T9 | No temporal or prospective set for novel targets (A9) | DATA+EVAL · L · P1 | Build a dated post-cutoff approval gold; define the prospective protocol for a pilot | Compare with and without the LLM channel on targets approved after the model cutoff; prospective candidates fixed before testing |
| T10 | Chat summary contradicted its own tool event; connector manifest drift (A2 notes) | CODE · S · P1 | Fix the chat reply contract; regenerate the manifest | Live chat run: the reply states the tool executed and its results; manifest contains the tool |
| T11 | Source registry count and chat reach unclear (A3) | CODE · S · P2 | Script that lists the registry against the chat-reachable set; optional `query_database` tool | Published numbers regenerate from the script |

### B2. Multi-omics and instrument data (M)

| ID | Gap | Type / size / priority | Fix | Full test |
|---|---|---|---|---|
| M1 | Catalogue numbers overstate verification (B1) | CODE+OPS · M · **P0** | Re-run the 407 provisional and a priority subset of the 1,879 untested; generate all published counts by script | Each re-run reaches ok or ok_warnings with provisional = 0, or is relabelled; the published numbers are regenerated from the database |
| M2 | Integration methods lack clean run records (B2) | OPS · M · P1 | Write the roadmap runs into the database; fix multiWGCNA and BANKSY inputs; add a Harmony and scVI fixture | MOFA2, mixOmics sPLS-DA, multiWGCNA, BANKSY with Harmony on public data (TCGA-BRCA three-omic, DLPFC Visium, PBMC two-batch): exit 0, expected artefacts, ARI or label accuracy above a preset baseline, provisional = 0 |
| M3 | Headline pipelines never executed (B3) | OPS · L · **P0** | Run and record nf-core rnaseq, sarek (somatic and CNV), scrnaseq, spatialvi, atacseq on public data | sarek on a public tumour-normal pair: VCF and CNV segments produced, concordance with truth above a preset level; rnaseq and scrnaseq: gene counts match a reference within tolerance; records written back |
| M4 | Survival and qPCR only assumed (B3) | CODE+OPS · M · P1 | Patient-level Kaplan-Meier and Cox workflow with a real run | TCGA-BRCA hazard ratios match published values within tolerance |
| M5 | NMR, ELISA, ITC, Cell Painting, cryo-EM unverified (B4) | OPS · L · P2 | Add missing workflows; run each on a public dataset (cryo-EM on EMPIAR-10028 with a GPU host) | Each produces its expected artefact (map and resolution, feature file, concentrations) |
| M6 | No batch, confound or held-out gate for integration (B6) | CODE · L · P1 | Integration QC module: batch-by-label confound check, permutation or held-out label recovery, minimum overlap; register under the gate emitter | MOFA2 on a cohort with a planted batch confound: gate fails and the report names the confounded factor; clean data passes |
| M7 | No cohort-scale evidence (B9) | OPS+EVAL · L · P1 | Scale tests with time, cost and memory recorded | 100 then 1,000 exomes through sarek; 300,000-cell atlas through quality control, integration and clustering; completes within budget; counts match |
| M8 | Provenance incomplete (B8, D6) | CODE · M · **P0** | Record container digests and tool versions at finalisation; persist QC events; add output hashes; offline cold tier | Run a workflow, restart services, reopen: parameters, input hashes, image digests, versions and gate events are all present; re-run from the record and diff outputs by hash |

### B3. Platform, on-premises and governance (P)

| ID | Gap | Type / size / priority | Fix | Full test |
|---|---|---|---|---|
| P1 | No clean-host or air-gapped install proof (D1) | OPS · L · **P0** | Merge the on-prem pull request to the branch of record; English install guide; offline image bundle | Clean VM, no cloud credentials: non-interactive install; register, create a project, run one workflow, find outputs in object storage; run the updater with backup and restore. Pass: all containers healthy, run completes, restore reproduces the data |
| P2 | AWS dependencies not inventoried; hard-coded image paths (D2, B7) | CODE+OPS · L · **P0** | Inventory every AWS reference; make the local path the default; image-mirror script; document executor variables | Block `*.amazonaws.com` and run one pipeline from the local registry: zero connections to AWS; then heavy pipelines on Slurm or Kubernetes |
| P3 | Cloud model defaults; two local-model paths (D3) | CODE · M · **P0** | One canonical local path; fail closed (or loudly) when a local endpoint is configured; startup self-check | Point at a DeepSeek or Qwen endpoint with all egress denied; run chat, a tool call, a workflow request and a target-ID query: zero outbound packets (capture) and tool-call success above a stated threshold |
| P4 | Analytics, fonts and CDNs load by default (D4) | CODE · S · **P0** | One offline switch removing the Google tag, analytics, fonts and CDNs; self-host fonts | Packet capture over a full working day under a deny-all firewall: no attempted connection to a non-allow-listed host |
| P5 | No institutional single sign-on or team roles (D7) | CODE · L · P1 | OIDC and SAML or LDAP; organisation and team entities; role mapping | Log in through a test identity provider; team A cannot read team B's projects or outputs; access trail recorded |
| P6 | No dataset de-identification; dead PHI classifier; development-secret fallback; no retention policy (D8) | CODE · L · P1 | Dataset de-identification step; wire the classifier; fail closed on a missing secret; retention and deletion jobs | Upload a synthetic patient table: prompts, logs and caches contain no identifiers; deletion removes the data |
| P7 | No hospital-system connector (D9) | CODE · L · P2 | Define the first integration with the hospital and build to it | Pull one record from the hospital system and trace it end to end |
| P8 | Tenant isolation asserted but untested (D10) | CODE+EVAL · M · P1 | Data-flow inventory; cross-tenant tests; row-level security | Two tenants write memory and cache data; automated test shows neither can retrieve the other's; training and evaluation corpora contain no tenant content |
| P9 | On-prem model evidence is narrow (D3) | EVAL · M · **P0** | End-to-end agentic benchmark on the hospital-class model (shared with T7) | Reproduce the on-prem routing table on the actual model plus 20 tool-call tasks, with thresholds stated in advance |

### B4. Drug-development directions (R)

| ID | Gap | Type / size / priority | Fix | Full test |
|---|---|---|---|---|
| R1 | Almost no drug-development workflow has a real-execution record (C2, C3, C5, C10, C11, C12) | OPS · L · **P0** | Run each headline workflow once on Batch with a positive control; write the record back | Per workflow: succeeds on Batch, valid outputs, recovers a known positive (erlotinib scaffold, a known PD-L1 macrocycle, a seeded dose-response), database status set |
| R2 | Assay-learning and ingestion fixes exist only in the working tree (C7, C8) | CODE+OPS · S · **P0** | Review, commit with explicit paths, pre-sync checklist, sync to dev | The 74 local tests pass on the committed state; the use-case suite passes on dev |
| R3 | Refits not gated by a holdout comparison (C8) | CODE · M · P1 | Route refits through the model registry; gate adoption on a holdout comparison | Split a public ChEMBL series (200 or more compounds) into three rounds and a fixed holdout: a worse version is rejected, rollback restores the old one, proposals change when labels change |
| R4 | ADMET and docking accuracy unmeasured or failed (C3) | EVAL · M · P1 | Held-out ADMET (e.g. TDC hERG, AMES) and docking redock validation; report method, version, threshold per score | hERG AUROC at a stated target (proposed 0.80); redocks under 2 Å for at least 60% of 20 complexes; each score carries an evidence record |
| R5 | PBPK below target; BOIN accuracy never measured; NCA unexecuted (C5) | EVAL+OPS · M · P1 | Dev Batch PBPK rerun; reproduce published BOIN operating characteristics; execute NCA through the authenticated path | PBPK: 15 or more compounds, at least 60% within 2-fold on dev. BOIN: published selection and overdose rates within 5 points over 1,000 or more simulated trials. NCA: synthetic curve returns half-life 4 h and AUCinf 5.77 mg·h/L with a dated record |
| R6 | Novelty and FTO gate is a research script, fail-open (C4) | CODE+DATA · L · P1 | Wire as a product gate; add a patent corpus; fail closed for export | 20 known patented compounds flagged (at least 90%); 20 post-cutoff novel compounds pass (false flags at most 10%); report lists matching patent identifiers |
| R7 | No computed biologic first-in-human dose (C6) | CODE · M · P2 | MABEL and receptor-occupancy calculator, wired | Five published biologic first-in-human cases: computed MABEL and dose within a factor of 3 of published values |
| R8 | Study-report extraction untested on real reports (C7) | EVAL · M · P1 | Test on real PDFs with human review | 10 real reports: at least 95% field accuracy against a hand-curated set, no predicted-as-measured mislabels, each field linked to its page |
| R9 | Fine-tune launch off; no lineage round-trip; GPU path not wired (C9) | OPS+CODE · L · P1 | Enable routing on dev; complete lineage; wire GPU | Fine-tune a small public model on a public dataset end to end: new version with run id and dataset version, holdout metrics, promotion requires sign-off, rollback restores the prior version |
| R10 | No humanisation or CDR-graft tool; no antibody design metric (C2) | CODE · L · P2 | Add the workflow and a design-quality metric | Humanise trastuzumab to HER2 binding retention; recover a known nanobody motif |
| R11 | Tumour-reactive T-cell identification absent; HLA and epitope never run (C10) | CODE+OPS · L · P1 | Run and record nf-core HLA and epitope workflows; build a clonal-expansion plus exhaustion workflow | Public 10x tumour with TCR data: HLA calls match known typing at four-digit resolution for at least 90% of samples; reactive-clone calls agree with published ones |
| R12 | Biomarker validation not in a verified workflow (C13) | CODE+EVAL · M · P1 | Execute the interaction-test and Cox workflows on public cohort data; add held-out validation | TCGA cohort: hazard ratio matches published; panel validated on a held-out split with C-index; interaction test recovers a seeded interaction |
| R13 | Benchling mock fallback risk; uncommitted connector (C notes) | CODE · S · P2 | Fail closed without a key; commit | With no key the connector errors, not mocks |

### B5. Multi-modal clinical data (K)

Added after the BD team asked how and where the client's multi-modal clinical data would be used
(supplement section 4.4). Evidence in the audit, section 4b.

| ID | Gap | Type / size / priority | Fix | Full test |
|---|---|---|---|---|
| K1 | No patient-level linkage and harmonisation layer across modalities (clinical, molecular, pathology, imaging) | CODE · M · P1 | Linkage-table builder (patient, sample, slide, image, timepoint), per-modality quality control, missingness and overlap report | On a public matched cohort (clinical, RNA, mutation and slide data, e.g. a TCGA cancer type) rebuild the linkage table and overlap report; counts match the cohort's published manifest exactly; deliberately broken keys are reported, not silently dropped |
| K2 | Radiology image analysis is absent (CT, MRI, PET, DICOM, radiomics) | CODE+DATA · L · P2 (depends on the client's interest) | A radiomics feature-extraction workflow with standard definitions, or a documented partner route; connector for exported imaging | On a public imaging collection with segmentations (e.g. a TCIA set): extracted features match a reference implementation within tolerance; feature table joins to clinical and molecular data through K1 |
| K3 | Clinical endpoint and timeline handling is not verified (overall and progression-free survival, censoring, landmark analysis, time-varying covariates) | CODE+EVAL · M · P1 | Patient-level survival workflow with explicit endpoint definitions; shares work with M4 and R12 | Public cohort: hazard ratios match published values within tolerance; synthetic data with a known effect recovers it; censoring handled correctly in a seeded edge case |
| K4 | No end-to-end multi-modal integration with held-out validation | EVAL · L · P1 (depends on M6, K1, K3) | Protocol: integrate matched modalities, predict a clinical endpoint, hold out by site or time, compare with a clinical-only baseline, with a permutation null | On a matched public cohort: report the gain over the clinical-only baseline with an interval, on the held-out site or period, with the null; the pass criterion is an honest result either way (a null is a valid outcome and is reported) |
| K5 | Circulating-DNA and liquid-biopsy workflows are listed but unverified | OPS · M · P2 | Run and record on a public dataset | Expected variant or fragment features produced; record written back |
| K6 | Pathology-to-molecular linkage workflow not demonstrated | CODE+OPS · M · P2 | Slide quantification joined to omics and outcome through K1 | Public cohort with slides and RNA: quantified features join to molecular data; association with a known marker reproduced |

---

## C. Order of work

1. **Phase 0, truth and hygiene (small, mostly code, no heavy compute):** W1 to W13 wording; M1 (numbers by script); R2 (commit and sync the working-tree fixes); T3, T10; P4; P3; M8 (digests and QC persistence).
2. **Phase 1, headline execution evidence:** M3, R1, M2, T1, T2, T4, T6, K1, K3.
3. **Phase 2, on-premises and governance proof, and the multi-modal test:** P1, P2, P9 with T7, P5, P6, P8, K4 (needs M6).
4. **Phase 3, scale, novelty and the remaining directions:** M7, T9, M6, R3 to R12, M5, P7, K2, K5, K6.

Each item ends with its acceptance test run, a dated record, and, for code, the pre-sync checklist and a
dev verification. Items needing paid compute get a cost estimate for approval first. Dependencies: T1
needs M3 or a DESeq2 run; T4 needs R1 and M3 records to find real workflows; P2 needs P1; T7 and P9 need
a hospital-class model endpoint (the Spark box or a rented GPU); T5 and R10 need DATA first.

## D. Branch and ownership notes

- The on-prem stack lives on `origin/integration/next-phase`; this branch lacks it. P1, P2 and P3 start by
  deciding the branch of record.
- Eight files under `drug_discovery/` are uncommitted in this worktree and are likely another session's
  work. R2 must be coordinated with that session; plain commits, explicit paths, no amend.
- The audit was read-only; items marked reported-by-audit were not re-run here. The catalogue numbers in
  section A (W1, W2) were recomputed from the database on 2026-11-01.
