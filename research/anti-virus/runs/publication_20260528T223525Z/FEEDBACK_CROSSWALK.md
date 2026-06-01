# Feedback Review ↔ Publication Campaign Crosswalk

Maps `research/anti-virus/feedback_review/` recommendations to run `publication_20260528T223525Z`.

**Updated:** 2026-05-28 (post Plan A full GP completion)

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
| Multi-tool meta (NetMHC, MixMHC, IEDB) | 4-tool consensus | **Blocked / pending** | NetMHC tarball not on S3 |
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
| Replace 6-compound demo library | ≥500 compounds | **Partial** | ZINC600 on S3; ZINC150 screen **in flight** |
| Ensemble docking (7 conformers) | Sprint exists | **Partial** | 6 conformers × 3 demo SMILES only |
| GROMACS MD (3 trajectories) | Week 1 plan | **Partial** | Machinery validated; production run incomplete |
| ≥3 compounds Kd < 5 µM | Success criterion | **Not met** | Best demo scores ~−4 to −5 kcal/mol |
| REINVENT4 docking_gnina | Generative | **Pending** | Prior run: 0 retained |

---

## Scenario progress (TEAM_ACTION_PLAN)

| Scenario | Description | Progress |
|----------|-------------|----------|
| **A** Full 8-week implementation | $16.5K, positive papers | ~40% — real data runs done; manuscript + inhibitor leads pending |
| **B** Phase 1 + Weeks 1–3 compute | $5K | Largely done for vaccine/Plan B; inhibitor ensemble incomplete |
| **C** Manuscript revision only | $0 | Not started |

---

## Immediate next actions

1. ~~**Update wet-lab package**~~ — done (`wet_lab_package/`)
2. **ZINC150 ADMET → Vina** — running (`zinc150_launcher.log`, outdir `.../20260528T235300Z/`)
3. ~~**Manuscript Phase 1**~~ — draft **v1.1** at `docs/MANUSCRIPT_PLAN_A_VACCINE_v1_1.md`
4. **NetMHCpan** upload + multitool comparison (feedback §4)
5. **Fresh inhibitor pipeline run dir** for ZINC600 pharmacophore (cannot append to completed manifest)

---

## Key narrative shift for investors

**Before (feedback diagnosis):** 810 predictions, 0 binders on 90-aa smoke fragment.

**Now:** 45,160 predictions on **full Q9E006 GP**, **113 MHC class I binders** across 5 alleles, plus **54 triple-species conserved 9-mers** — complementary wet-lab tracks for breadth vs. binding validation.
