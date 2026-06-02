# Manuscript review — Plan A (epitope) & Plan B (mRNA/LNP)

**Date:** 2026-06-03  
**Reviewers:** Vaccine immunology expert panel (hantavirus GPC + mRNA platform) + Nature Portfolio writing criteria  
**Documents reviewed:**

| Document | Version | Path |
|----------|---------|------|
| Plan A | v1.1 | `docs/MANUSCRIPT_PLAN_A_VACCINE_v1_1.md` |
| Plan B | v1.1 (excerpt) | `docs/MANUSCRIPT_PLAN_B_CODON_v1_0.md` |
| Wet-lab package | 2026-06-02 | `runs/publication_20260528T223525Z/wet_lab_package/` |
| Plan B CRO spec | 2026-06-03 | `runs/publication_20260528T223525Z/plan_b_wet_lab/PLAN_B_WET_LAB_SPEC.md` |

**Writing criteria applied:** `nature_research_writing_skills/nature_editorial_criteria_overview.md`, `nature_science_style.md`, `scientific-writing/SKILL.md` (IMRAD, no bullet prose in main text, abstract as flowing paragraphs).

---

## Executive verdict

| Manuscript | Scientific core | Writing quality | bioRxiv-ready? | Nature-family? |
|------------|-----------------|-----------------|----------------|----------------|
| **Plan A v1.1** | Improved vs v1.0 but **stale vs campaign data**; missing GPC biology | Good honesty; uneven breadth; Methods lean | **No** — fix Critical items 1–6 first | **No** — no experiment, no structural map |
| **Plan B v1.1** | Valid workflow QA; **not a vaccine construct** | Too thin for standalone paper; bullet Methods | **No** — expand or merge as supplement | **No** — infrastructure demo only |

**Recommended path:** Revise Plan A for **bioRxiv methods/resource** (~2–4 weeks + optional peptide binding data). Treat Plan B as **Methods supplement** to integrated preprint or separate platform note. Target integrated story at **Journal of Virology**, **npj Vaccines**, or **Vaccines** after minimal wet-lab.

---

## Part I — Vaccine immunology expert review

### Plan A — strengths

1. **Correct scope expansion** — Full Q9E006 (1138 aa) and eight HLA alleles supersede the 90-aa / two-allele negative baseline; the before/after comparison is scientifically valuable.
2. **Appropriate caution** — Abstract and Conclusions explicitly disclaim immunogenicity and efficacy.
3. **Dual-track wet-lab logic** — Separating MHC-validated peptides (Track A) from cross-species conserved 9-mers (Track B) reflects real design tension between allele coverage and pan-hantavirus breadth.
4. **Concrete anchors** — **MPKTIYEL**, **YRTLGVFRY**, **VIYEKTHCV**, **ESSCNFDLH** (pos 61) support readable Results.
5. **Reproducibility** — Run IDs, S3 paths, and wet-lab package are publication-grade for a resource paper.

### Plan A — critical science errors (must fix before any submission)

#### 1. Manuscript is stale relative to campaign artifacts

| Claim in v1.1 | Current data |
|---------------|--------------|
| 113 MHCnuggets binders only | **604 unique binder peptides** in `PLAN_A_FULL_GP_MULTITOOL.tsv` (MHCnuggets + MHCflurry) |
| Zero conserved ∩ binder overlap | **10/54** conserved 9-mers overlap binders (`wet_lab_package/`) |
| HLA-A\*02:01: 0 binders | **VIYEKTHCV** (MB-10) in multitool merge |
| Table 1 led by KTFEGILTK (rank 0.0) | Wet-lab MB list prioritizes **ATESALQAHY**, **MPKTIYEL** — reconcile rank vs selection criteria |

Submitting manuscript + wet-lab package together without reconciliation will trigger immediate reviewer distrust.

#### 2. No glycoprotein precursor (GPC) biology

Q9E006 is the full envelope **polyprotein** (signal peptide → Gn → transmembrane/stem → Gc → cytoplasmic tail). The manuscript treats GP as a linear string with no:

- Signal peptidase cleavage (~Met1–Leu18)
- Furin/SKI-1-class cleavage between Gn and Gc
- Ectodomain vs TM vs cytoplasmic annotation
- Mapping to **Gn head**, **Gc head**, or stem using PDB **9P3I**

**Top peptides — geographic concern:**

| Peptide | GP pos | Likely region | Expert concern |
|---------|--------|---------------|----------------|
| MPKTIYEL | 19–26 | N-proximal / leader-adjacent | Poor natural processing candidate |
| ESSCNFDLH | 61 | N-proximal Gn | Conserved; MHCnuggets-negative |
| VIYEKTHCV | 172 | Gn head | Best surface CD8 candidate among top hits |
| KKVILTKTL–KTLVIGQCI | 442–448 | Gc TM-proximal / stem | Conserved + binder overlap; likely membrane-buried |
| ATESALQAHY | 582 | **Cytoplasmic tail** | Not displayed on virion |
| YRTLGVFRY | 618 | **Cytoplasmic tail** | Strong score; **not a surface epitope** |

Without exposure filtering, binder calls are misread as “vaccine epitopes.”

#### 3. Missing immunology dimensions

- **Class II (CD4)** — No HLA-DR/DQ scan; CD4 help is essential for durable anti-GP antibody.
- **Neutralizing vs T-cell** — No link to Gn/Gc prefusion nAb literature or 9P3I structural epitopes.
- **HLA coverage** — Eight alleles skew B locus; no population coverage metric (IEDB tool). Cannot imply global vaccine relevance.
- **Score units** — MHCnuggets “BA” is not nM IC50; MHCnuggets vs MHCflurry disagree ~5× on binder counts — must be central Discussion point.

#### 4. Wet-lab plan is Tier 1 only

DimerX/ELISA → ELISpot is acceptable first pass but insufficient for vaccine claims. Add: NetMHCpan consensus, NetChop/TAP processing, tetramer confirmation, glycosylation caveat for Gn, and (for Plan B linkage) expression + pseudotype nAb.

---

### Plan B — strengths

1. Full-length Q9E006 CDS (3414 nt) — antigen-faithful, not eGFP smoke.
2. Codon change rate (737/1138; 64.76%) is plausible.
3. 5′ MFE and stop-codon gates are reasonable in silico QC.
4. LNP pKa 9.5 and POOR PK stealth are correctly flagged in `PLAN_B_WET_LAB_SPEC.md`.
5. Spike 2P (12819) as platform regression — appropriate internal control.

### Plan B — critical gaps (vaccine realism)

The ANDV construct is a **raw polyprotein ORF**, not a deployable mRNA vaccine:

| Component | Plan B | Field expectation |
|-----------|--------|-------------------|
| Prefusion stabilization | None (Spike 2P not applied) | Gc prefusion locks per structural vaccinology |
| Cleavage / trimming | Full 1138 aa incl. TM + tail | Ectodomain-only or authentic Gn/Gc processing design |
| 5′/3′ UTR, cap, mod nucleotides | Placeholders | Required for CRO quote (e.g. N1-mψU, CleanCap) |
| LNP target tissue | **Liver** | Mismatch for HPS (respiratory/endothelial; want LN/APC uptake) |
| Liver uptake 80.3% @ 24 h | Reported in PK model | Formulation **failure mode**, not feature |

**CAI = 1.0** alone is insufficient — report GC%, CpG, rare codons; score full-CDS structure, not only 500-nt 5′ window.

---

### Cross-track integration (largest translational gap)

Plan A epitopes are **encoded** in Plan B ORF but **never integrated**:

- Best dual-track candidates (**KKVILTKTL**, **KVILTKTLV**, **KTLVIGQCI**) appear in wet-lab package but not Plan B manuscript.
- Cytoplasmic binders (**YRTLGVFRY**, **ATESALQAHY**) should not drive construct design.
- No shared GP map figure; no immunogen redesign (mosaic / ectodomain / prefusion-stabilized variants).

---

### Severity-ranked revision list (immunology)

**Critical**

1. Reconcile binder counts and overlap (113 vs 604; 0 vs 10).
2. Annotate all top peptides by GPC topology; downgrade tail/TM hits as surface vaccine epitopes.
3. Integrate MHCflurry + consensus binder definition in Plan A text.
4. Plan B: state explicitly — **not a clinical candidate** without prefusion/cleavage/ectodomain engineering.
5. Reframe liver-targeted LNP; PK data are anti-goals for HPS vaccine unless repositioned as anti-pattern.
6. Define MHCnuggets BA units; add NetMHCpan orthogonal thresholds.

**Major**

7. NetChop/TAP on top 30 peptides.
8. IEDB population coverage for eight alleles.
9. CD4 module (paragraph + planned NetMHCII).
10. Neutralizing vs T-cell strategy section.
11. Conservation re-analysis on ectodomain-only.
12. Plan B construct variants (full GPC vs ectodomain vs Gc-stabilized).
13. Cross-track figure for dual candidates.
14. Structural references (9P3I, Guo et al., hantavirus vaccine precedents).

**Minor**

15. KTFEGILTK rank 0.0 footnote; harmonize Table 1 vs MB list; GC/CpG alongside CAI; verify WHO outbreak citation.

---

## Part II — Nature Portfolio writing review

Applied criteria: interdisciplinary interest, arresting main conclusion, readability for non-specialists, flowing abstract (no labeled sections), active voice, minimal jargon, story-driven Results, heavy detail in SI.

### Plan A — writing assessment

| Criterion | Grade | Notes |
|-----------|-------|-------|
| **Title** | B+ | Descriptive and accurate; slightly long for *Nature* TOC — consider shortening to “Full-length ANDV glycoprotein class I epitope map and cross-species conservation” |
| **Abstract** | B | Good flowing structure (context → methods → numbers → caveat → wet-lab); **too workflow-heavy** for *Nature* (nf-core, BioMate, GRCh37); outbreak sentence needs verified WHO cite |
| **Introduction** | B− | Clear funnel; **Paragraph 3 (“Prior work in our campaign…”)** is meta-narrative — move smoke-run comparison to Results or SI for external readers |
| **Outbreak Response Context** | C+ | Standalone section reads like investor deck; *Nature* would fold 1–2 sentences into Introduction; verify outbreak facts |
| **Methods** | C | Reproducible but **repository paths and run UUIDs** belong in SI; main text should state design in prose (IMRAD violation: bullet HLA list acceptable, but S3 URLs in body are wrong tier) |
| **Results** | B | Finding-driven subheads work; **needs one figure** (GP map with binder/conservation tracks) per Nature graphical abstract norm |
| **Discussion** | B− | Honest limitations; too brief on **predictor disagreement** and **GPC topology**; “multivalent designs” claim needs structural rationale |
| **Conclusions** | B+ | Appropriately scoped |
| **References** | D | Placeholders; *Nature* requires numbered Vancouver; need epidemiology + 9P3I structure + hantavirus vaccine refs |

**Nature-style abstract rewrite (target ~180 words, illustrative):**

> Andes virus causes hantavirus pulmonary syndrome with high mortality, yet no licensed vaccine exists and experimental class I epitope maps for the viral glycoprotein remain sparse. Here we computed a full-length class I peptide–allele landscape for the 1,138-amino-acid Andes virus glycoprotein precursor across eight common HLA-A and HLA-B alleles, integrating cross-species conservation with Sin Nombre and Puumala viruses. In silico binding calls nominated hundreds of candidate peptides—concentrated at HLA-B\*08:01, B\*07:02, and B\*27:05—with partial overlap between conserved nine-mers and predicted binders in transmembrane-proximal regions. Conservation and allele-specific binding mapped largely to distinct segments of the polyprotein, including cytoplasmic segments that are unlikely to be presented from native virions without further processing analysis. These results do not establish immunogenicity; they provide a reproducible resource and a dual experimental strategy prioritizing MHC binding confirmation and cross-species T-cell probes, with archived predictions supporting expanded allele panels and orthogonal tools.

**Key Nature gaps for Plan A**

1. **No arresting “so what” for non-virologists** — Lead with “outbreak + no vaccine + first full-GP map,” not workflow orchestration.
2. **No central figure** — Nature expects one schematic: GP topology + epitope tracks + wet-lab funnel.
3. **Internal campaign language** — “Smoke fragment,” “BioMate,” “run_id” reduce interdisciplinary appeal.
4. **Discussion too short** — Nature wants mechanism and field context (how this compares to HTNV/ANDV vaccine attempts, VSV vectors, DNA vaccines).
5. **Length appropriate for *Nat Commun* / bioRxiv**, not *Nature* Article.

### Plan B — writing assessment

| Criterion | Grade | Notes |
|-----------|-------|-------|
| **Standalone paper** | D | Reads as **Methods supplement fragment** — no Introduction, no figure callouts, bullet Methods |
| **Abstract** | C− | One paragraph listing workflow IDs — not a scientific story; violates “finding-first” Nature abstract |
| **IMRAD completeness** | F | Missing Introduction, proper Results prose, structured Discussion |
| **Honesty** | A− | Discussion correctly limits claims |
| **Integration** | F | No link to Plan A or inhibitor track |

**Recommendation:** Do **not** submit Plan B as standalone preprint. Expand into:

- **Option A:** Combined “ANDV outbreak computational vaccine platform” preprint (Plan A + Plan B + methods figure).
- **Option B:** Plan B as **Extended Data / Supplement** to Plan A with one composite workflow figure.

**Nature-style fix for Plan B abstract (if merged):**

> Messenger RNA vaccines depend on expression-optimized open reading frames and formulations that protect RNA and deliver it to relevant immune compartments. For the Andes virus glycoprotein—a 3,414-nucleotide coding sequence—we optimized codons for human expression, evaluated five-prime RNA structure, ranked lipid-nanoparticle compositions in silico, and modelled nanoparticle pharmacokinetics. Codon adaptation modified 64.8% of codons while passing premature-stop and stability gates; recommended formulations showed suboptimal ionizable-lipid pKa and rapid mononuclear phagocyte clearance in simulation, flagging iteration before translational use. These analyses validate a reproducible mRNA-design ladder on antigen-faithful sequence data but do not demonstrate expression, immunogenicity, or protective efficacy.

---

## Part III — Combined revision roadmap

### Phase 1 — Critical (1 week, no wet lab)

- [ ] Update Plan A to **multitool TSV**; fix overlap counts; add MHCflurry Methods paragraph
- [ ] Add **GPC topology table** for MB-01–15 and XSP-09–15
- [ ] Remove “zero overlap”; highlight dual candidates **KKVILTKTL**, **KVILTKTLV**, **KTLVIGQCI**
- [ ] Move S3 paths / run IDs to **Data availability + SI**
- [ ] Plan B disclaimer + liver-LNP reframe; merge or supplement structure
- [ ] Define BA units; add placeholder NetMHCpan comparison table from multitool merge

### Phase 2 — Major (2–3 weeks)

- [ ] One **GP landscape figure** (Plan A + Plan B ORF overlay)
- [ ] NetChop/TAP + IEDB population coverage (computational)
- [ ] CD4 paragraph + planned NetMHCII
- [ ] Plan B construct variants subsection (3 designs)
- [ ] Complete references (Vancouver numbered)
- [ ] Nature-style abstract rewrite (both tracks if merged)

### Phase 3 — Translational (optional before bioRxiv)

- [ ] Peptide–MHC binding on MB-01–05 + dual-track XSP-09–11
- [ ] ANDV GP mRNA expression in vitro (Plan B optimized ORF)
- [ ] Update Discussion with binding data

---

## Venue recommendations

| After Phase 1 only | After Phase 3 |
|--------------------|---------------|
| bioRxiv (methods/resource) | *Journal of Virology*, *npj Vaccines* |
| *PLOS Comput Biol*, *ImmunoInformatics* | *Vaccines* (MDPI) |
| Plan B never standalone — SI only | Integrated platform story |

**Not appropriate:** *Nature*, *Nature Medicine*, *Nature Vaccines* (without experimental immunogenicity/challenge), *Cell* family.

---

## Reviewer sign-off (simulated panel)

**Vaccine immunology:** “Promising resource once multitool data and GPC topology are integrated; do not call cytoplasmic peptides vaccine epitopes; Plan B is infrastructure, not a candidate.”

**Nature Portfolio editor (desk reject simulation):** “Plan A might be considered at *Nature Communications* only with experimental binding + structural figure and broader immunology framing; current draft is bioRxiv-tier methods. Plan B insufficient as standalone.”

---

## Related files

- Campaign status: `docs/20260603_ANDV_THREE_TRACKS_STATUS_AND_PLAN.md`
- Prior strategic review: `feedback_review/MANUSCRIPT_REVIEW_AND_STRATEGIC_RECOMMENDATIONS.md` (pre–full-GP; partially superseded)
- Plan A figures (full GP): `runs/manuscript_figures_v1/plan_a/`
- Writing skills: `docs/nature_research_writing_skills/`
