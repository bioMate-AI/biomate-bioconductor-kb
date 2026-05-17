# Manuscript Session Notes — 2026-05-04

## Session Scope
Paper-writing work: Bioconductor KB paper reference cleanup + §§ accuracy pass; manuscript status review across all three active papers.

---

## 1. Bioconductor KB Paper — Work Done This Session

**File:** `docs/papers/bioconductor_kb_paper/20260226_PAPER_DRAFT.md`

### Changes Made

| Section | What changed |
|---------|-------------|
| §1 Intro | Rewrote paragraph on related AI approaches — BioWorkflow, BTR, BioAgent Bench now accurately described (BioWorkflow = LLM RAG extractor with ~80% step recall on 100 papers; BTR = GNN on >7,000 Galaxy workflows; BioAgent Bench = evaluation benchmark, not a generation system) |
| §5.2 Integration | Fixed class name `MethodsGenerator` → `MethodsSectionGenerator`; fixed parameter signature `get_recommended_parameters(name, domain)` → `get_recommended_parameters(name, context={})` — both verified against actual code in `backend/lib/galaxy/ai/` |
| §6.5 FAIRsoft | Expanded from placeholder table to full 13-indicator FAIRsoft assessment (11/13 fully met, 2/13 partial); estimated score 0.85–0.88; two partial items: F3 (FAIRsharing registration pending) and R3 (CONTRIBUTING.md pending) |
| §7 Comparison | BioWorkflow coverage corrected from "~500 workflows" to "Publication-derived (100-paper eval)" |
| Abstract | URL placeholder `[URL]` → `https://biomate.ai/bioconductor-kb`; Zenodo noted as "DOI pending" |
| References | Filled 4 placeholder citations with verified details: |
| | Ref 6: Wang & Wang 2025 — *BioWorkflow*, Briefings Bioinformatics 26(6):bbaf571 |
| | Ref 7: Green et al. 2024 — *BTR*, Bioinformatics 40(5):btae275 (PMCID PMC11091741) |
| | Ref 8: Fa et al. 2026 — *BioAgent Bench*, arXiv:2601.21800 |
| | Ref 11: Martín del Pico et al. 2024 — *FAIRsoft*, Bioinformatics 40(8):btae464 |

### DB Structure Discovery
- Production DB (`galaxy_ai_tools.db`, `workflows` table, `source='bioconductor'`): 1,818 packages, 27,264 total steps — steps embedded as DSL2 Nextflow script comments, NOT the JSON schema shown in §4.1
- Pre-refactor backup DB has `tools.nfcore_metadata` JSON column (the original schema §4.1 describes)
- Canonical extraction source: `bioconductor_skill/skill_generation/bioconductor_tools.db` — has 1,909 packages with curated 15,641 steps (paper's authoritative numbers)
- Paper numbers (1,909 pkgs, 15,641 steps) are correct for the curated extraction DB; the 91-package/~12K step discrepancy vs production Galaxy DB is a result of the refactoring from tools.nfcore_metadata to workflows.workflow_json

### Remaining Placeholders
- Author section (lines 8–11): intentionally left — needs user input
- Zenodo DOI: pending deposit
- FAIRsharing registration: ~1 hour of work
- CONTRIBUTING.md for GitHub repo: short doc, ~30 min

### Target
NAR Database Issue — September 2026 submission. On track per venue timeline.

---

## 2. Manuscript Status: All Active Papers

### 2.1 CryoEnsemble
**File:** `research_repos/cryoensemble_paper/manuscript/MANUSCRIPT_DRAFT.md`
**Status:** 418 lines; revised 2026-05-01 (sister feedback incorporated); preprint target was 2026-05-01 — **MISSED**
**Venue:** Nature Methods (primary); eLife / PNAS (secondary)

**Submission checklist remaining:**
- [ ] Convert MANUSCRIPT_DRAFT.md → PDF/DOCX (pandoc)
- [ ] Register Zenodo DOI for data + code
- [ ] Fill author affiliations (Sister's institution + BioMate)
- [ ] Upload to bioRxiv.org
- [ ] Pilot 0 real BioEmu data (β₂AR + TRPV1, AWS Batch runs) — needed to strengthen §4.2 and replace Gaussian surrogate

**Key scientific gap from sister feedback (`docs/references/feedback_google_ai4s.md`):**
1. 10% gap fraction is simulation-derived, not empirical — needs Pilot 0 real BioEmu results to become data-driven
2. ADK benchmark uses coordinate-space particles (no CTF/noise) — acknowledged as PoC in §4.4
3. Gaussian perturbation doesn't capture correlated domain motions — Pilot 0 will replace it
4. All three limitations explicitly called out in §4.4 — reviewers will see them

**Core verified numbers (safe to submit):**
- 10% gap fraction across 10 proteins (lower-bound, Gaussian surrogate)
- 100% rare conformers missed by cryoDRGN (mean RMSD 4.50 Å from nearest cluster)
- ADK PoC: cryoDRGN RMSD 7.11 Å vs CryoEnsemble posterior 0.82 Å (5% closed state)
- +16.1% mean pocket enrichment (7/10 proteins p < 0.05)
- Formal proof: map-level BME posterior = 0 at any λ > 0

**Recommended action:** Submit bioRxiv preprint now (current draft is complete and limitations are transparent); upgrade to journal submission after Pilot 0 results arrive.

---

### 2.2 BioMate-Cryo
**File:** `research_repos/cryo_em_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md`
**Status:** 391 lines; draft 2026-04-27; DOCX ready; preprint target was 2026-05-01 — **MISSED**
**Venue:** Nature Methods (primary); Nature Communications (secondary)

**Submission checklist remaining:**
- [ ] Register Zenodo DOI for EMPIAR-10028 benchmark run data + code
- [ ] Fill author affiliations (Sister's institution, structural biology co-author)
- [ ] Add GitHub repository URL (replace placeholder)
- [ ] Upload to bioRxiv.org
- [ ] TRPV1 benchmark run (EMPIAR-10005) — in preparation (membrane_protein profile validation)
- [ ] Full-dataset run (1,081 particle stacks) — in progress

**Key verified numbers (EMPIAR-10028, already in manuscript):**
- 24 CryoSPARC jobs, FSC 0.143 = 3.98 Å, 26,284 particles, 2.8 GPU-hours, $6.29 AWS cost
- 0 QC gate halts (purified_protein profile on clean data)

**Gap in current manuscript:** Only one benchmark dataset (EMPIAR-10028, purified_protein). The membrane_protein profile differentiation (key claim of the paper) requires TRPV1 / EMPIAR-10005 run. This is the single biggest gap for Nature Methods acceptance.

**Recommended action:** Run EMPIAR-10005 TRPV1 with both `purified_protein` and `membrane_protein` profiles; quantify false-positive micrograph rejection difference; add Protocol-Discrimination table to manuscript; then submit bioRxiv.

---

### 2.3 Bioconductor KB Paper
**File:** `docs/papers/bioconductor_kb_paper/20260226_PAPER_DRAFT.md`
**Status:** Complete draft (9 sections + refs + supp); all numbers locked; 4 references just filled
**Venue:** NAR Database Issue (September 2026); Briefings in Bioinformatics (fallback)

**Remaining before submission:**
- [ ] Author list (first/last author, domain expert co-authors)
- [ ] Zenodo DB deposit → DOI
- [ ] FAIRsharing.org registration (F3 indicator)
- [ ] CONTRIBUTING.md for GitHub (R3 indicator)
- [ ] Actual FAIRsoft evaluator run (after Zenodo deposit)
- [ ] Simple web query interface at biomate.ai/bioconductor-kb

**Timeline (from venue analysis):**
- May 2026: Analysis/results sections written ← **DONE**
- June 2026: Full draft circulated to co-authors
- July 2026: Revision, figure polish, supplementary
- August 2026: Final review + prep
- September 2026: Submit

---

## 3. Planned Multi-Paper Arc (from `docs/papers/20260225_1545_MULTI_PAPER_PUBLICATION_STRATEGY.md`)

| Paper | Target venue | Month | Status |
|-------|-------------|-------|--------|
| BioMate-Cryo | Nature Methods | Now | Preprint ready — submit |
| CryoEnsemble | Nature Methods | Now | Preprint ready — submit |
| Bioconductor KB | NAR Database Issue | Sep 2026 | On track |
| BioMate QC Governance | Nature Methods | ~Month 9 | Plan written, build phase |
| Protocol-aware QC (ML) | Genome Biology | ~Month 15 | Concept only |
| Proteomics QC | MCP / J Proteome Res | Parallel | Plan written |

---

## 4. Immediate To-Dos (Priority Order)

### P0 — This week
1. **Submit CryoEnsemble to bioRxiv** — DOCX conversion + author affiliations + Zenodo data DOI → upload. The draft is complete and limitations are transparent.
2. **Run EMPIAR-10005 (TRPV1)** with BioMate-Cryo `membrane_protein` profile — this is the one missing result for the BioMate-Cryo paper's key claim.

### P1 — This month
3. **Submit BioMate-Cryo to bioRxiv** — after EMPIAR-10005 results added.
4. **Pilot 0 real BioEmu data** (β₂AR + TRPV1 AWS Batch) — replace Gaussian surrogate numbers in CryoEnsemble; needed before journal submission.
5. **Bioconductor KB**: author list, Zenodo deposit, FAIRsharing registration.

### P2 — Before June
6. Circulate Bioconductor KB draft to domain expert co-authors.
7. Upgrade CryoEnsemble submission from bioRxiv to Nature Methods after Pilot 0 data arrives.
