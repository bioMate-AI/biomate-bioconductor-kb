# Feedback Review ↔ Publication Campaign Crosswalk

Maps `research/anti-virus/feedback_review/` recommendations to run `publication_20260528T223525Z`.

**Updated:** 2026-06-03 (post multitool merge, ZINC150, GROMACS MD, Plan B spec)

---

## Phase 1 — Manuscript reframing

| Item | Feedback doc | Status | Evidence |
|------|--------------|--------|----------|
| Rewrite abstracts (outbreak framing) | MANUSCRIPT_REVIEW §Phase 1.1 | **Pending** | Manuscripts not edited |
| Outbreak Response Context section | MANUSCRIPT_REVIEW §Phase 1.2 | **Pending** | — |
| Comparative docking table (literature) | MANUSCRIPT_REVIEW §Phase 2.3 | **Pending** | — |
| Translational roadmap section | MANUSCRIPT_REVIEW §Phase 3.5 | **Pending** | Partial text in feedback docs only |
| Author names, references, figure paths | MANUSCRIPT_REVIEW checklist | **Pending** | — |

---

## Phase 2 — Computational depth (positive results)

### Vaccine / Plan A

| Item | Target | Status | Result |
|------|--------|--------|--------|
| Full-length GP (not 90-aa smoke) | Q9E006 1138 aa | **Done** | `assets/andv_gp_full_Q9E006.fasta` |
| Expanded HLA panel | >2 alleles | **Done** | 8 alleles |
| Full GP epitopeprediction | MHCnuggets Batch | **Done** | `plan_a_epitope/PLAN_A_FULL_GP.tsv` — **45,160 rows, 113 binders (0.25%)** |
| Cross-species conservation | ANDV/SNV/PUUV | **Done** | **54** conserved 9-mers, **195** cross-species peptides |
| Conserved + binder overlap | Ideal dual candidates | **0/54** | Conservation and MHC binders occupy different GP regions |
| Multi-tool meta (NetMHC, MixMHC, IEDB) | 4-tool consensus | **Partial** | MHCnuggets + MHCflurry merged (`PLAN_A_FULL_GP_MULTITOOL.tsv`); NetMHC/MixMHC pending |
| Conformational epitope prediction | ≥5 epitopes | **Not started** | — |
| Immunogen designs (population coverage) | 75–85% | **Not started** | — |

**Top MHC binders (full GP, publication-grade positive values):**

| Peptide | Allele | Rank | BA |
|---------|--------|------|-----|
| KTFEGILTK | HLA-A\*03:01 | 0.0 | 0.426 |
| ATESALQAHY | HLA-A\*01:01 | 0.0002 | 0.451 |
| MPKTIYEL | HLA-B\*08:01 | 0.0007 | 0.727 |
| YRTLGVFRY | HLA-B\*27:05 | 0.0011 | 0.660 |
| IPMKTDLEL | HLA-B\*07:02 | 0.0017 | 0.631 |

**Wet-lab strategy (dual track):**
- **Track 1 — MHC binders:** synthesize top 10 by rank (validated in silico binders)
- **Track 2 — Conservation:** synthesize XSP-01–15 (cross-species breadth, MHC binding to be tested)

### Plan B — mRNA / LNP

| Item | Target | Status | Result |
|------|--------|--------|--------|
| Real ANDV GP CDS (not eGFP) | Q9E006 | **Done** | 3414 nt reverse-translated |
| Codon optimization | Real antigen | **Done** | **737/1138 codons (64.76%)** modified |
| RNA2D 5′ window | ViennaRNA | **Done** | MFE **−182.7 kcal/mol**, 161 bp pairs |
| LNP formulation | mRNA cargo | **Done** | Endosomal escape 0.202; liver tissue 0.85 |

### Inhibitor track

| Item | Target | Status | Result |
|------|--------|--------|--------|
| Replace 6-compound demo library | ≥500 compounds | **Done (ZINC150)** | 145 docked; best −6.267 kcal/mol |
| Ensemble docking (7 conformers) | Sprint exists | **Partial** | Top-5 done (1/5 improved); top-15 failed |
| GROMACS MD (3 trajectories) | Week 1 plan | **Partial** | INH-01 MD complete; MM-GBSA ΔG null |
| ≥3 compounds Kd < 5 µM | Success criterion | **Not met** | Vina scores ~−5 to −6 kcal/mol; no MM-GBSA ΔG |
| REINVENT4 docking_gnina | Generative | **Done (0 retained)** | `06_reinvent4/` — filters removed all |

---

## Scenario progress (TEAM_ACTION_PLAN)

| Scenario | Description | Progress |
|----------|-------------|----------|
| **A** Full 8-week implementation | $16.5K, positive papers | ~65% — Plan A/B compute done; inhibitor MM-GBSA + manuscripts pending |
| **B** Phase 1 + Weeks 1–3 compute | $5K | Done for vaccine/Plan B compute; inhibitor MD partial |
| **C** Manuscript revision only | $0 | Not started |

---

## Immediate next actions

1. ~~**Update wet-lab package**~~ — done; re-run with ZINC150 docking JSON for Track C
2. ~~**ZINC150 ADMET → Vina**~~ — done (`zinc150_screen/`)
3. ~~**Manuscript Phase 1 (Plan A)**~~ — draft v1.1 at `docs/MANUSCRIPT_PLAN_A_VACCINE_v1_1.md`
4. **Plan A figures** — regenerate from full GP multitool TSV
5. **Plan B wet-lab spec** — done (`plan_b_wet_lab/PLAN_B_WET_LAB_SPEC.md`)
6. **MM-GBSA** — rebuild ECR v1.2.0, re-run standalone Batch job
7. NetMHCpan upload + 4-tool comparison (optional)
8. Manuscript author/refs/outbreak framing (Phase 1 feedback)

---

## Key narrative shift for investors

**Before (feedback diagnosis):** 810 predictions, 0 binders on 90-aa smoke fragment.

**Now:** 45,160 predictions on **full Q9E006 GP**, **113 MHC class I binders** across 5 alleles, plus **54 triple-species conserved 9-mers** — complementary wet-lab tracks for breadth vs. binding validation.
