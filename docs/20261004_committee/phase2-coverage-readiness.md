# Phase-2 Tutorial-Video Production-Readiness Map

**Date:** 2026-10-04
**Author:** Coverage committee — Phase-2 readiness lens
**Scope:** The next candidate tutorial videos beyond the 6 already-produced drug-dev/onboarding ones (t0–t4 + drug-dev). Decide which can be filmed as a WORKING showcase with REAL live output **today**, the cheapest capture path for each, and what is blocked. **Read-only audit — no Batch jobs run, no tutorial/workflow files edited.**
**Golden rule (CLAUDE.md):** never film a stub/fake. Only film what genuinely runs end-to-end with real output.

---

## 1. Readiness table

Status key: **RUNS-LIVE-REAL** = real end-to-end run with real output verified today · **RUNNABLE-WITH-SETUP** = implemented, needs one setup/verify step before it can be filmed honestly · **BLOCKED** = cannot complete today, do not film live.

| # | Video | Underlying workflow / feature | Status | Evidence (+ quote) | Cheapest capture path | What to show |
|---|-------|-------------------------------|--------|--------------------|-----------------------|--------------|
| 1 | **Search & Evidence** (data-centric v2 M1) | Cold-start "Search & evidence" lane → `/api/evidence` (PubMed E-utilities + OpenTargets GraphQL, LLM rerank, inline citations) | **RUNNABLE-WITH-SETUP** (committee "BLOCKED" is **STALE**) | 2026-10-04 nav audit now shows the module mounts: `"module":"search","passed":true` … `"Search & evidence — A cited answer over literature, databases and patents / Literature / Databases / Patents / Internal"` (`docs/qa/20261003-tutorial-release/navigation/audit.json`). The catalog still carries the old block (`m1-search-and-evidence … "status":"BLOCKED" … "does not mount the expected cold-start module dashboard"`) citing the *pre-fix* copy of that same audit. Evidence pipeline is real: `frontend/server/evidence-routes.ts` ("PubMed E-utilities, OpenTargets Platform v24 GraphQL … inline citations and relevance scores"). | **dev-UI** (~free) | A cited answer over a query **with retrieval hits** (e.g. "evidence linking <target> to <disease>"). **Setup/verify before filming:** confirm PMIDs/DOIs resolve — the LLM chat `research_query` path still confabulates when recall=0 (`docs/20260912_onprem_llm/20261001_OSS_SURVEY_GAP_PLAN.md`: "research_query still confabulates when recall=0"); film only grounded, resolvable citations. |
| 2 | **Count-matrix DE (DESeq2)** | `rnaseq_differential` / NormqPCR-adjacent DESeq2 count-matrix path on **GSE52778** | **RUNS-LIVE-REAL** | 0921: "RNA-seq (DESeq2) ✅ has (cold-start `GSE52778` airway) · runs end-to-end ✅ yes" (`docs/20260921_WORKFLOW_SAMPLE_DATA_COVERAGE.md`). Committee: "Count-matrix DE … Video-ready: validated, GSE52778 sample data on cold-start" (`docs/20261004_committee/coverage-qa.md`). | **CPU-Batch** (count-matrix only, no alignment → cheapest Batch, ~$0.01–0.30) | QC → DESeq2 → volcano + MA plot, padj vs log2FC, replicate caveat. P1 **Tier-1 freemium front door** — highest-leverage gap. |
| 3 | **Bulk RNA-seq** | `nf-core/rnaseq` (FASTQ → count matrix) | **RUNS-LIVE-REAL** (FASTQ input) / SRA-accession path BLOCKED | basespace tutorial §6: "run end-to-end on real public datasets on AWS Batch"; 0921 table "runs end-to-end ✅". **But** SRA-accession dispatch dies in the fetchngs pre-step (see #5). | **CPU-Batch** (full align+quant; tens of min, ~$1–3) | FASTQ → FastQC/MultiQC → STAR/Salmon → count matrix → DE handoff. **Film from staged FASTQ, not an SRA accession** (fetchngs S3 bug). |
| 4 | **Cryo-EM SPA** | `cryosparc_standard_spa` (motion/CTF/pick/2D/ab-initio/refine) | **BLOCKED** (infra) | `frontend/e2e/cryoem-capstone.e2e.ts`: real, no-mock EMPIAR-10025 run but `fixme` — "execution BLOCKED BY INFRA — the CryoSPARC GPU host 52.42.49.175:30000 is down/unreachable (port closed)". Root cause: `CRYOSPARC_AMI_ID` on dev points at a deleted AMI → on-demand CryoSPARC cannot launch (`docs/20260730_WGS_CRYOEM_ROOTCAUSE_AND_FIXES.md`). Tutorial claims "Validated on real data" = a **historical** team-S3 run, not reproducible on dev today. | **GPU-Batch**, committee est. **$200–2000/run** — do not attempt until infra restored | Nothing live today. Unblock = rebuild CryoSPARC AMI + repoint `CRYOSPARC_AMI_ID`, then one supervised GPU run. |
| 5 | **WGS / variant calling** | `Wgs Germline Gatk` (GATK4 14-step) | **BLOCKED** | fetchngs S3 dispatch bug **still open**: `docs/20260730_WGS_CRYOEM_ROOTCAUSE_AND_FIXES.md` — "When using `awsbatch` executor an S3 bucket must be provided as working directory …"; "*every* SRA-accession workflow (WGS, RNA-seq-from-SRA, any fetchngs prefetch on Batch) fails the same way"; fix "not yet shipped". Plus genome-alias→FASTA + requester-pays issues. 0921: "dispatch blocked (fetchngs S3 bug)". | GPU/CPU-Batch — **hold** | Nothing live today. Conflicts with basespace tutorial's "validated" (see §3b). |
| 6 | **qPCR ΔΔCt** | `normqpcr_delta_delta_cq_normalization` (Bioconductor NormqPCR) | **RUNS-LIVE-REAL** | 0921: "qPCR ΔΔCq ✅ added (NormqPCR bundled example) · runs end-to-end ✅ yes · Done this session" — copies `system.file("exData","example.txt", package="NormqPCR")`. Committee: "runs end-to-end on bundled NormqPCR example. The tutorial says 'no recorded real run' and is **stale**." | **dev-UI / CPU-Batch** — **cheapest of all** (small table, minute-scale, data bundled, Tier-1) | ΔCt → ΔΔCt → 2^−ΔΔCt fold-change on the bundled example. Best, cheapest instrument demo. Fix §6 first (§3a). |
| 7 | **Flow-cytometry gating** | `Analyze Flow Cytometry Immunophenotyping` (biomni wrapper) | **RUNNABLE-WITH-SETUP** (not film-ready) | 0921: "Flow cytometry … ❌ none · 🟡 unverified · Follow-up: bundle a real small public `.fcs` fixture — do NOT fabricate a synthetic `.fcs` blind." Committee: "Unverified. No fixture." | dev-UI / CPU-Batch after fixture | Needs a real small public `.fcs` fixture + one verify run before any film. Hold. |
| 8 | **LC-MS proteomics / metabolomics** | DDA `proteomics_dda_search` (Comet/Sage/mokapot); DIA `nf-core/diaproteomics` (OpenSWATH) vs `dia_proteomics_analysis` (DIA-NN); metabolomics `metaboanalystr`/`xcms` | **BLOCKED** (no clean E2E today) | LC-MS tutorial §6: "available, but NOT validated on real data end-to-end — this is the weakest-evidence instrument … no recorded real end-to-end proteomics or metabolomics run." 0921: proteomics/metabolomics "blocked (B3 raw→mzML)". Metabolomics is **one line from running**: `main.nf` line 140 `ReplaceMin` → `ImputeMissingVar` (`docs/20260923_DOMAIN_VALIDATION_RESULTS.md`; CSV-assembly chain fully fixed, sanity check passes). **License:** DIA-NN is **not license-clean** (memory); the clean path is OpenSWATH/PyProphet (DIA) + Comet/Sage/mokapot (DDA). Comet **does** produce real FDR-calibrated results in isolation (`evaluation/results/proteomics_search_speed_recall_20260929/metrics.json`: comet, 260 PSMs @1% FDR, entrapment FMR 0.0). | CPU-Batch — **hold** | Nothing clean end-to-end today. If filmed later, show **Comet/Sage/mokapot** (DDA) or **OpenSWATH** (DIA), **never DIA-NN**. |
| 9 | **Large-DB search** (Foldseek / MMseqs2 / FPSim2) | Foldseek 3Di (AFDB 214M), MMseqs2 (nr/UniRef, `--gpu`), FPSim2 (ChEMBL/PubChem); + reference-DB lookup cache (gnomAD/ClinVar/dbSNP) | **RUNNABLE-WITH-SETUP**; lookup-cache = **RUNS-LIVE-REAL** | **Conflict, reconciled:** priority Excel *Large DB Search* sheet (2026-07-15) = all "Implemented" with real harness e2e (FPSim2 "Real e2e local test 7/x"; MMseqs2 "Real e2e 4/4 + S3 prov"; Foldseek "Prebuilt index on S3"; **Reference-DB lookup cache "Done (9/9 tests), shipped 2026-07-15"**). But `docs/20260920_BIOMATE_WHATS_LEFT.md`: "E2E-unverified tools (wired, never run to completion): Foldseek, MMseqs2 …". So: implemented + indexed + local e2e green, but **no confirmed dev-Batch production run** as of Sept, and their natural UI home (M1 search) was only just unblocked (#1). | **dev-UI** (lookup cache) · **CPU/GPU-Batch** (Foldseek/MMseqs2/FPSim2, one confirm run) | Film-ready now: **reference-DB lookup** (gnomAD/ClinVar) via dev-UI. Foldseek/MMseqs2/FPSim2: do ONE live dev-Batch confirm run first, then film. |

---

## 2. Instrument-tutorial accuracy fixes (3 committee-flagged conflicts)

### (a) qPCR §6 stale status — `docs/user-manual/tutorials/instruments/qpcr-quantification.md`
**Current (§6, line ~141):** "Status: available, not yet validated on real data end-to-end. … BioMate does **not** yet have a recorded real qPCR run proving it end-to-end on the development site. Treat it as *available-but-untested*…"
**Fix:** rewrite to —
> "Status: **validated end-to-end on bundled sample data.** `normqpcr_delta_delta_cq_normalization` runs to completion on the NormqPCR package's own example dataset (`system.file("exData","example.txt", package="NormqPCR")`), which BioMate bundles as one-click sample data (`docs/20260921_WORKFLOW_SAMPLE_DATA_COVERAGE.md`, 2026-09-21). On your own data, still sanity-check the first run against a value you compute by hand."
Keep the absolute/standard-curve and melt-curve gaps (those are genuinely unbuilt). Also state the "~1 cycle ≈ 2-fold" rule assumes ~100% amplification efficiency.

### (b) basespace WGS "validated" vs the fetchngs block — `docs/user-manual/tutorials/instruments/basespace-sequencing.md`
**Current:** §2b and §6 call WGS "best-validated" / `Wgs Germline Gatk` "**validated** (BioMate-curated GATK4 pipeline, exact catalogue match)"; §6 table "Whole genome / exome (germline) → validated".
**Fix:** keep RNA-seq as validated, but downgrade WGS to —
> "`Wgs Germline Gatk` is a curated GATK4 best-practices pipeline with an exact catalogue match, **but it is not yet validated end-to-end on dev**: dispatch from an SRA accession currently fails in the nf-core/fetchngs pre-step with an awsbatch S3 work-dir error (`docs/20260730_WGS_CRYOEM_ROOTCAUSE_AND_FIXES.md`), and genome-alias→FASTA resolution plus requester-pays reference access are open issues. Treat WGS results as experimental until these land."
Remove "best-validated of the five instruments" framing (it is RNA-seq that is validated, not WGS).

### (c) LC-MS defaulting DIA to DIA-NN — `docs/user-manual/tutorials/instruments/lcms-proteomics-metabolomics.md`
**Current:** §2a/§2b and the workflow table **default** DIA to `nf-core/dia_proteomics_analysis` (DIA-NN), with OpenSWATH only as "an alternative"; DDA leads with `nf-core/proteomicslfq`, license-clean `proteomics_dda_search` only parenthetical.
**Fix:** flip the default ordering for hosted/commercial use —
> DIA default → **`nf-core/diaproteomics` (OpenSWATH/PyProphet)**; list DIA-NN (`dia_proteomics_analysis`) as an alternative **with the explicit caveat** "DIA-NN is not license-clean for commercial/hosted work — prefer OpenSWATH unless you hold a DIA-NN licence."
> DDA default for commercial → **`proteomics_dda_search` (Comet/Sage/mokapot)**.
The §6 licensing caveat already exists; this change makes the **recommended default** match it rather than contradict it. (Reference: memory "Proteomics engine licenses"; `evaluation/results/proteomics_search_speed_recall_20260929/` shows Comet is real and FDR-calibrated.)

---

## 3. Recommended Phase-2 filming order (cheapest-live-first)

1. **qPCR ΔΔCt** — dev-UI/CPU-Batch, minute-scale, bundled data. Truly runs, cheapest, best instrument demo. *(Fix §6 first.)*
2. **Count-matrix DE / DESeq2 on GSE52778** — CPU-Batch (count-matrix only), ~cents. P1 Tier-1 front door, validated, cold-start chip ready.
3. **Reference-DB lookup search (gnomAD/ClinVar)** — dev-UI, ~free. The film-ready slice of the "DB" pillar (Done 9/9, shipped).
4. **Search & Evidence (M1)** — dev-UI, ~free. Route now unblocked; film after one live cited-answer spot check (resolve the PMIDs).
5. **Bulk RNA-seq via nf-core/rnaseq (from staged FASTQ)** — CPU-Batch, ~$1–3. P1, validated; avoid the SRA-accession path.
6. **Foldseek / MMseqs2 / FPSim2 large-DB search** — CPU/GPU-Batch. Film after ONE confirmed dev-Batch run (close the Excel-vs-whats-left evidence gap).

**Blocked — do not film live until unblocked:** Cryo-EM SPA (CryoSPARC AMI/GPU host), WGS/variant calling (fetchngs S3 work-dir bug), LC-MS proteomics + metabolomics (no clean E2E; metabolomics 1-line `ReplaceMin` fix pending; show Comet/OpenSWATH not DIA-NN), Flow cytometry (needs a real `.fcs` fixture + verify run).

---

*Audit only. No Batch jobs were run; no tutorial or workflow files were edited. This doc is the sole output.*
