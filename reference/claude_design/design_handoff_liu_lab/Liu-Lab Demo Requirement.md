# Liu-Lab Tutorial Demo — Detailed Requirement for Claude Design

**Date:** 2026-06-18
**For:** Claude design / engineering handoff
**Researcher:** Dr. Zhandong Liu (Baylor College of Medicine, rare neurological disease diagnosis)
**Builds on:**
- `business/BioMate_ZhandongLiu_Study_Proposal.md` (1-week pilot proposal, target *Nature Methods / Genome Biology*)
- `business/BioMate_ZhandongLiu_Independent_Analysis.md` (his real published pipeline, paper-grounded)
- `business/BioMate_ZhandongLiu_Opportunity_Analysis.md` (BioMate fit assessment A–G)
- `reference/claude_design/design_handoff_zhi_lab/Zhi-Lab Demo Requirement.md` (sibling — same 8-beat grammar)
- `reference/claude_design/design_handoff_tier0_design_pipelines/Tier-0 Demo Requirement.md` (8-beat template + tip-card style)

## Why one demo (not five)

Per the audit (`docs/20260618_RESEARCHER_OUTREACH_SESSION.md` follow-up), most of Liu's published pipeline upstream is **already in BioMate today**. The single most valuable demo is the one that exercises the existing `rare_disease_multimodal_workup` chain end-to-end — that directly answers the pilot proposal's RQ1 (output concordance with his current pipeline).

His own lab tools (AI-MARRVEL, PolyAMiner-Bulk, SEAGAL) are deferred — they wrap easily later if the pilot's first reading is positive.

---

## Demo L01 — Rare Disease Multi-Modal Workup (RareCollab-style upstream)

### What runs in BioMate today (verified live)

**`workflow_chains.id = 1`, name `rare_disease_multimodal_workup`, domain `rare_disease`.**

Description (verbatim from DB):
> "End-to-end rare disease workup combining germline variant calling on WGS/WES with transcriptomic outlier detection (aberrant expression and splicing) on paired RNA-seq, producing a unified case report ready for downstream variant prioritisation tools."

5-step pipeline (verbatim from `workflow_chains.steps`):

| Phase | Workflow | Role | Params |
|---|---|---|---|
| A | `nf-core/sarek` | germline_variant_calling | `genome=GRCh38, tools=[haplotypecaller], wes=false` |
| B | `nf-core/vcf_annotate_ensemblvep` | variant_annotation | `species=homo_sapiens, assembly=GRCh38` |
| C | `nf-core/rnaseq` | rna_alignment_quantification | `aligner=star_salmon, genome=GRCh38` |
| D | `nf-core/drop` | aberrant_expression_splicing | `outrider=true, fraser=true` |
| E | `case_report_aggregation` | result_aggregation | (defaults) |

This is **exactly Liu's RareCollab upstream as quoted in the paper:**
> *"RNA fastq files were first converted into bam files by using nextflow rnaseq (3.22.2). Then, nextflow drop pipeline (development version) was applied for the downstream analysis, including OUTRIDER for aberrant expression analysis, FRASER for aberrant splicing analysis and GATK for ASE analysis."* — RareCollab (arXiv 2602.04058)

The differences vs. his current pipeline:
- BioMate ships **released nf-core/drop** (not the dev branch he uses) — output concordance is the pilot RQ1 to measure
- BioMate adds `case_report_aggregation` (step E) — a unified report his ad-hoc scripts currently produce manually
- BioMate's run goes through chain composer → SSE-live phase cards + 7-tab After-run report

### Scientific anchor

- **RareCollab** (arXiv 2602.04058, 2026)
- **AI-MARRVEL** (NEJM AI 2024, v1.1.2) — downstream variant ranker, not in this demo
- nf-core/rnaseq (3.22.2 in Liu's paper)
- nf-core/drop (development version in Liu's paper; BioMate ships current released)

### Cold-open promise (Beat 1)

> "Liu lab's RareCollab pipeline — variant calls, expression outliers, splicing outliers — usually means three separate Nextflow runs and stitching the results yourself. We'll do all four in one chat prompt."

### Input contract (Beat 2 — exact phrasing the user types)

```
Run a rare-disease multi-modal workup on these FASTQ + WGS samples — GRCh38, HaplotypeCaller for variants, OUTRIDER + FRASER for RNA outliers, unified case report.
```

### Per-beat tip script

| Beat | Tip | Duration | Anchor |
|---|---|---|---|
| 3 | "BioMate sees `rare-disease + WGS + OUTRIDER + FRASER` → routes to `rare_disease_multimodal_workup` chain (id 1) — already a 5-step curated chain." | 5500 | intent kicker |
| 4 | "Params prefilled: genome=GRCh38, sarek tools=haplotypecaller, drop has both outrider+fraser on. Only the sample sheet is yours to confirm." | 5500 | param strip |
| 5 | "Confirm & run — chain composer dispatches sarek first; rnaseq + drop wait for inputs." | 4000 | run button |
| 6a | "Phase A — nf-core/sarek germline variant calling. HaplotypeCaller on the WGS sample." | 5500 | phase A card |
| 6b | "Phase B — VEP annotation (Ensembl). The annotated VCF flows to the case report as one of three evidence streams." | 5000 | phase B card |
| 6c | "Phase C — nf-core/rnaseq with star_salmon. This is the same `nextflow rnaseq 3.22.2` you'd run today; BioMate just wraps the dispatch." | 6000 | phase C card |
| 6d | "Phase D — nf-core/drop. OUTRIDER for aberrant expression, FRASER for aberrant splicing — exactly your RareCollab quote." | 6000 | phase D card |
| 6e | "Phase E — case report aggregation. Variants + expression outliers + splicing outliers folded into a unified table, ready for AI-MARRVEL ranking downstream." | 5500 | phase E card |
| 7 | "Findings panel: per-case top variants, outlier genes, splicing events. Citations cite nf-core/drop (Yepez 2021), OUTRIDER (Brechtmann 2018), FRASER (Mertes 2021), and your RareCollab preprint. The (why?) anchor on each phase explains the method choice." | 6500 | findings + citations |
| 8 | "Outcome: your published upstream, in one prompt, runnable by anyone in your lab on day one." | 3500 | completed badge |

### What the recorder must verify (Playwright assertions)

```ts
// Beat 4 — workflow card matched to chain id 1
await expect(page.locator('[data-testid="workflow-panel-header"]')).toContainText('Rare Disease Multi-Modal');
// Beat 6 — all 5 phase cards render
await expect(page.locator('[data-testid^="phase-group-"]')).toHaveCount(5);
// citations + (why?) anchor backing (apply per BioMate's metadata pattern)
const r = await page.request.get('/api/workflows/rare_disease_multimodal_workup/citations');
// Expect ≥1 citation (currently empty — needs qc_evidence.yaml backfill before recording; see Open Items)
```

### Outcome card spec

Same methodology-blue (#2563eb) band as Zhi/Zhao demos (signals "method-integration partner"). Lists:
- Liu Lab — Baylor College of Medicine
- 4 published anchor papers (RareCollab, AI-MARRVEL, PolyAMiner-Bulk, SEAGAL)
- ✓ Your published pipeline, one prompt
- ✓ Same nf-core tools (sarek, rnaseq, drop)
- ✓ AI-MARRVEL integration available next phase
- Pilot enquiries: research@biomate.ai

---

## Acceptance criteria

### Pre-recording (engineering)

- [x] Chain `rare_disease_multimodal_workup` exists in DB (id 1)
- [x] All 5 step workflows (sarek, vcf_annotate_ensemblvep, rnaseq, drop, case_report_aggregation) exist in workflows table
- [ ] **OPEN** — `qc_evidence.yaml` does NOT yet have a `rare_disease_multimodal_workup` block. Need to add citations for:
  - nf-core/drop — Yepez et al. Nat Protoc 2021 (doi:10.1038/s41596-020-00462-5)
  - OUTRIDER — Brechtmann et al. AJHG 2018 (doi:10.1016/j.ajhg.2018.10.025)
  - FRASER — Mertes et al. Nat Commun 2021 (doi:10.1038/s41467-020-20573-7)
  - nf-core/sarek — Hanssen et al. F1000Research 2024 (or Nilsson et al. Bioinformatics 2025)
  - RareCollab — arXiv 2602.04058 (Liu lab 2026)
  - AI-MARRVEL — Mao et al. NEJM AI 2024
- [ ] **OPEN** — `rationale_mapping.yaml` rare_disease_multimodal_workup chain block with 5 confirmed phase rows pairing each phase to a gate in the above qc_evidence domain
- [ ] **OPEN** — run `populate_rationale_registry.py --apply` to materialize 5 new registry rows
- [ ] **OPEN** — verify live: `/api/workflows/rare_disease_multimodal_workup/citations` returns ≥5 DOIs; `/api/rationale/rare_disease_multimodal_workup:A` through `:E` all return curated text

### During recording (design)

- [ ] Voice-over reads each tip verbatim, total ≤3:00 strict
- [ ] All 5 phase cards render with `data-testid^="phase-group-"`
- [ ] Citations tab visible in Beat 7 (≥5 DOIs)
- [ ] (why?) anchor visible on at least one phase in Beat 6 (verifies metadata wired)
- [ ] Recording uses fixture login (`lifeifei163361@163.com`) per the canonical pattern

### Real-data validation (engineering, optional for recording)

- [ ] Test dataset: a public rare-disease cohort with paired WGS + RNA-seq (e.g. UDN, Sayed et al. or the Wagner 2020 study DROP authors used). Repo `nf-core/test-datasets` has minimal fixtures suitable for smoke.
- [ ] Smoke dispatch on dev with synthetic 2-sample test data; assert all 5 phases reach `completed` status
- [ ] Compare phase-D outputs (OUTRIDER + FRASER tables) against a Liu-lab-provided reference run for the same data → answers pilot RQ1

---

## Out of scope (deferred)

- **AI-MARRVEL wrap** — adds a 6th phase (variant ranking). Recommended for L01-v2 (after pilot Phase 1 measures concordance). Effort: ~1 day (`LiuzLab/AI_MARRVEL`, public, recent updates).
- **PolyAMiner-Bulk** (APA analysis) — separate demo L02. Effort: ~1–2 days.
- **SEAGAL** (spatial) — separate demo L05. Need to confirm repo URL with the lab first.
- **MeCP2 / CUT&RUN** chain — would be L04. Existing chain id 17 + chain id 2 are partial coverage; could compose into a single demo without new wrapping.

---

## Why this demo lands the pilot

The pilot proposal (`business/BioMate_ZhandongLiu_Study_Proposal.md`) asks 4 research questions. **L01 directly answers RQ1 (output concordance) and partially answers RQ2 (efficiency for analysts at all experience levels).** RQ3 (literature usefulness) and RQ4 (session memory) require the After-run report's Citations tab + multi-session interaction — both verified to work in dev for other demos this session.

The pitch to the lab becomes: *"Your published pipeline runs end-to-end in BioMate today. Spend one hour running your own published benchmark cohorts through chat, compare the outputs to your current pipeline, tell us where they diverge. We'll wrap AI-MARRVEL + PolyAMiner if Phase 1 says it's worth it."*

That's a low-cost, high-information pilot start — exactly what the proposal already drafted.

---

## Background reading for the next session

- `business/BioMate_ZhandongLiu_Study_Proposal.md` — pilot study + 4 research questions
- `business/BioMate_ZhandongLiu_Independent_Analysis.md` — paper-grounded audit of Liu's real workflow
- `business/BioMate_ZhandongLiu_Opportunity_Analysis.md` — A-G fit areas
- `docs/20260618_CLAUDE_DESIGN_QC_GATE_ALIGNMENT.md` — sibling QC alignment doc (3 bioc + 5 tier-0 + 3 Zhi/Zhao)
- `docs/20260617_RESEARCHER_OUTREACH_SESSION.md` — session-end state
- nf-core/drop docs: https://nf-co.re/drop
- AI-MARRVEL repo: https://github.com/LiuzLab/AI_MARRVEL
- PolyAMiner-Bulk repo: https://github.com/YalamanchiliLab/PolyAMiner-Bulk
