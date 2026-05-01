# Competitive Comparison Strategy — Cite vs. Head-to-Head

**Date:** 2026-05-01  
**Context:** IND assembly manuscript + product strategy for BioMate regulatory writing module

---

## Decision: Cite and Comment, Not Head-to-Head Benchmark

For the peer-reviewed manuscript targeting *Journal of Cheminformatics* or *Drug Discovery Today*, the correct approach is **cite and differentiate** rather than direct head-to-head computational benchmarking.

### Why Not Direct Head-to-Head

| Issue | Detail |
|-------|--------|
| **Tool access** | Certara CoAuthor, Yseop Compose, AutoIND are proprietary/licensed. Running them on our SMILES set requires commercial agreements or acceptance-period access. |
| **Scope mismatch** | Schrödinger LiveDesign, MOE output structured data files — they are *inputs* to our pipeline, not competitors at the §2.6 writing layer. |
| **Reproducibility** | Proprietary models are not version-pinned. Results from one access window may differ from the next. JCIM editors will ask how we ensured identical conditions. |
| **Unfair test construction** | Any test set we design advantages ourselves. For head-to-head credibility, an independent regulator or academic lab would need to administer the test. |
| **Not standard practice** | Regulatory informatics papers (e.g., ADMET-AI, ChemBERTa, TDC leaderboard papers) compare against open benchmarks (TDC, ChEMBL), not licensed tools. |

---

## What We Do Instead

### For the Manuscript

**1. Quantitative comparison: open benchmarks only**

Use TDC leaderboard rows as the comparison baseline:

| Model | hERG AUROC | DILI AUROC | AMES AUROC | PPBR MAE |
|-------|-----------|-----------|-----------|----------|
| ADMET-AI (Chemprop-RDKit, pub.) | 0.870 | 0.856 | 0.870 | 8.6% |
| Chemprop (baseline) | 0.870 | 0.847 | 0.850 | 8.4% |
| **BioMate (ADMET-AI engine, TDC scaffold split)** | **0.931** | **0.913** | **0.934** | **5.01%** |

> Note: BioMate's ADMET engine *is* ADMET-AI fine-tuned on expanded ChEMBL+TDC data — the gap above reflects additional training data (13,719 compounds vs. ADMET-AI's training set), not a fundamentally different architecture.

**2. Qualitative differentiation table** (§Discussion)

| Tool | ADMET prediction | PBPK modeling | §2.6 narrative | Regulatory audit | Wet-lab ingestion | Freeze/hash |
|------|-----------------|---------------|----------------|-----------------|-------------------|-------------|
| Certara CoAuthor | No | Yes (Simcyp) | Partial | Manual | No | No |
| AutoIND (arXiv 2509.09738) | No | No | Yes (LLM) | No | No | No |
| Schrödinger | Yes (ADMET) | No | No | No | No | No |
| Yseop Compose | No | No | Yes (template) | No | No | No |
| **BioMate** | **Yes (ADMET-AI)** | **Yes (OSP-validated)** | **Yes (LLM+rules)** | **Yes (2-tier)** | **Yes** | **Yes (SHA-256)** |

**3. The only legitimate head-to-head: expert user study**

If we want a quantitative "quality of §2.6 narrative" comparison vs. a human regulatory writer, the valid design is:
- Same 5 compounds → BioMate §2.6.1 narrative (automated) vs. senior RA consultant narrative (manual)
- Blind evaluation by 2 FDA-experienced reviewers using ICH M4 completeness rubric
- Score: section coverage, citation accuracy, quantitative accuracy, hedging appropriateness

This is a small user study ($5-15K cost for RA consultant + reviewer time). It would be the strongest evidence for the paper and for the product. We should target this for a subsequent publication or conference demo.

---

## What to Say About Each Competitor

### Certara CoAuthor
> "Certara CoAuthor integrates with Simcyp for PBPK-driven narrative generation but does not incorporate ADMET toxicity prediction layers or automated regulatory audit against ICH S7B/EMA DILI tier criteria. Our system adds an end-to-end pipeline from molecular structure through audit-ready CTD Module 2.6 document generation."

### AutoIND (Zhao et al., arXiv:2509.09738)
> "A concurrent effort, AutoIND, demonstrates LLM-based IND section drafting but focuses on template filling from structured input rather than integrating predictive toxicology and PBPK simulation results. BioMate generates the underlying ADMET and PK data computationally before assembling the narrative."

### Schrödinger LiveDesign / ADMET Predictor
> "Commercial ADMET platforms such as Schrödinger LiveDesign generate property predictions that can serve as inputs to BioMate's assembly pipeline, or BioMate's ADMET-AI engine can replace them in an end-to-end computational workflow."

### Yseop Compose
> "Template-based regulatory authoring tools such as Yseop Compose reduce writer time for structured sections but do not integrate computational ADMET or PBPK data sources, leaving the scientific content population to human authors."

---

## For the Blog / Marketing

Head-to-head is fine for blog positioning because it is explicitly opinion/analysis rather than peer-reviewed claims. The framing:

> "Most regulatory writing tools are document processors — they format what you give them. BioMate generates the science too: it predicts ADMET properties, runs PBPK simulations, screens reactive metabolite alerts, then writes the CTD Module 2.6 section, audits it against FDA/EMA/ICH guidelines, and freezes the document with a cryptographic hash. It's the only end-to-end pipeline from SMILES to eSig-ready IND section."

No false AUROC claims, no "better than Certara" performance claims — just pipeline coverage differentiation, which is demonstrably true.

---

## Action Items

| Item | Owner | When |
|------|-------|------|
| Add qualitative differentiation table to §6 Discussion in manuscript | Claude | This session |
| Add AutoIND citation (arXiv:2509.09738) to bibliography | Claude | This session |
| Scope expert user study (5 compounds, 2 reviewers) | User | Pre-submission |
| Get a commercial-access trial of AutoIND to test coverage | User | Optional |
| Blog post draft: "From SMILES to eSig-ready IND section in 10 minutes" | Claude | Next session |
