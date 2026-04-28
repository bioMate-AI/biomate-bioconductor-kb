# BioMate Improvement Plan — 2026-04-16

**Objective:** Close identified benchmark gaps and improve BioMate's scientific capabilities.  
**Method:** Parallel execution of independent tracks.

---

## Gap Analysis — Updated 2026-04-16

| Benchmark | Current | Root Cause | Fix | Status |
|-----------|---------|-----------|-----|--------|
| SGI-Bench deep research | 10-17% (noisy) | Paper numbers in Extended Data Figures; NCBI/EuropePMC PDF bot gates | Full-text PMC BioC JSON added; PDF vision blocked | Track 1 ✓ applied; Track 5 blocked |
| BixBench MCQ mode | 26.7% | MCQ is a proxy; exec mode needs capsule data | Code execution enabled; HF capsule data confirmed accessible | Exec mode data download needed |
| BiomniEval1 gwas_causal_gene | 26.7% | 30% route to workflow path; boilerplate in response | First-line extraction fix; intent routing fix | ✓ improved from 3.3% |
| BiomniEval1 screen_gene | 40.0% | Tool-use attempts; knowledge limit | Format instructions strengthened | ✓ stable |
| BiomniEval1 gwas_variant | 13.3% | Wrong rsID from candidate list; knowledge-limited | (none) | Open |
| BiomniEval1 pgd | 40.0% | DB lookup quality | Live OMIM/ClinVar clients added | ✓ improved from 0% |
| BiomniEval1 rdd | 40.0% | DB lookup quality | Live OMIM/ClinVar clients added | ✓ improved from 13.3% |
| Routing: variant_calling | 93.3% (post-patch) | was 56.7%: gatk outscored sarek | Description disambiguation patch | ✓ done |
| Routing: atac_seq | 88.2% (post-patch) | was 70.6%: CUT&RUN vs ATAC-seq | Description disambiguation patch | ✓ done |
| ResearchAgent → tool DB | Interim | HTTP clients bypass galaxy_ai_tools.db | Architecture unification (later) | Open |

---

## Active Tracks

### Track 1 — SGI-Bench: Full-Text Paper Retrieval
**File:** `backend/lib/galaxy/ai/agents/research_agent.py`  
**What:** Add `lookup_paper_fulltext(title_or_doi)` using Semantic Scholar S2 API + PMC Open Access XML.  
After finding relevant papers in PubMed/arXiv, fetch open-access full text for Methods/Results sections.  
**Expected impact:** SGI 16.7% → 35%+ (paper-specific number extraction is the dominant failure mode)

### Track 2 — Routing Patches: Variant Calling + Epigenomics
**File:** `backend/scripts/patch_workflow_descriptions.py`  
**What:**
- `nf-core/sarek`: Add "for somatic/tumor-normal variant calling, cancer genomics, multi-sample cohorts" disambiguation
- `wgs_germline_gatk`: Add "for germline single-sample, family trio, or population genetics variant calling"  
- `nf-core/atacseq`: Add "Tn5 transposase-based open chromatin profiling without antibody"
- `nf-core/cutandrun`: Add "antibody-based CUT&RUN or CUT&TAG for targeted histone marks, NOT Tn5-based ATAC-seq"
**Expected impact:** variant_calling 56.7% → 80%+, atac_seq 70.6% → 90%+

### Track 3 — Full BiomniEval1 Baseline ✓ COMPLETE
**Results (n=30 each):**
- gwas_causal_gene: **26.7%** (was 3.3% raw, fixed by first-line extraction)
- screen_gene_retrieval: **40.0%** (stable)
- gwas_variant_prioritization: **13.3%** (knowledge-limited)
- patient_gene_detection: **40.0%** (DB lookups added)
- rare_disease_diagnosis: **40.0%** (DB lookups added)
- **BiomniEval1 overall: 32.0%** (mean of 5 tasks)
- Competitor: Biomni-R0-32B >80% (specialized biomedical LLM)

### Track 4 — BixBench Exec Mode Setup ✓ INFRASTRUCTURE READY
**What:** Adapter built with HuggingFace capsule data support  
**Note:** All 64 CodeOcean capsule zips on HuggingFace (no account needed)  
**Next:** Run `python3 evaluation/runners/run_bixbench.py --mode biomate_exec --max-tasks 10`  
**Requires:** Backend server + ANTHROPIC_API_KEY set in environment

### Track 5 — PDF Figure Extraction via Vision ✓ IMPLEMENTED (BLOCKED)
**File:** `backend/lib/galaxy/ai/agents/research_agent.py`  
**What:** PyMuPDF page rendering + Claude Haiku vision to read Extended Data Figure values  
**Status:** BLOCKED — NCBI PDF endpoint uses JavaScript PoW bot gate; EuropePMC unreachable from this network  
**Workaround:** PMC BioC JSON figure captions (text fallback) working  
**Impact:** SGI figure-dependent questions (~20/30) can't get values from images; captions provide partial context

---

## Files to Change

| Track | File | Change |
|-------|------|--------|
| 1 | `research_agent.py` | Add `lookup_paper_fulltext()` + `_fetch_s2_paper()` + wire into `_gather_evidence()` |
| 2 | `patch_workflow_descriptions.py` | Add 4 new patch entries; run `--apply` |
| 3 | None | Run benchmark |
| 4 | `evaluation/config.yaml` | Set `paths.bixbench_repo`; clone repo |
