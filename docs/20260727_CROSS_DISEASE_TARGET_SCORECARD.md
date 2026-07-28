# Cross-Disease Target Scorecard — Autoimmune/Immune Panel

**Date:** 2026-07-27
**Pipeline:** BioMate target-discovery, two-stage, run per disease on the host
(`nextflow run … -profile standard`, `process.executor = local`, live network).
1. `nextflow/subworkflows/database/query_opentarget.nf` — live Open Targets
   Platform GraphQL v4 (`api.platform.opentargets.org`, apiVersion 26.6.3),
   `--n_targets 25`, emits `target_evidence.csv`.
2. `nextflow_nfcore/subworkflows/drug_discovery/target_scorecard_ranker/main.nf`
   — OT-style weighted-harmonic-sum ranker over the evidence table.

**Panel (8 diseases, all resolved live in OT before scoring):**

| Slug | Disease | OT id | Step 1 | Step 2 |
|------|---------|-------|:------:|:------:|
| ra  | rheumatoid arthritis          | MONDO_0008383 | 25 rows ✔ | 25 scored ✔ |
| sle | systemic lupus erythematosus  | MONDO_0007915 | 25 rows ✔ | 25 scored ✔ |
| ms  | multiple sclerosis            | MONDO_0005301 | 25 rows ✔ | 25 scored ✔ |
| cd  | Crohn disease                 | MONDO_0005011 | 25 rows ✔ | 25 scored ✔ |
| uc  | ulcerative colitis            | MONDO_0005101 | 25 rows ✔ | 25 scored ✔ |
| pso | psoriasis                     | MONDO_0005083 | 25 rows ✔ | 25 scored ✔ |
| t1d | type 1 diabetes mellitus      | MONDO_0005147 | 25 rows ✔ | 25 scored ✔ |
| mg  | myasthenia gravis             | MONDO_0009688 | 25 rows ✔ | 25 scored ✔ |

**8/8 diseases ran end-to-end with no failures.** Disease names were passed as
apostrophe-free / EFO-MONDO ids (per the known param-quoting bug — e.g. "Crohn
disease", not "Crohn's"); every name resolved to a MONDO id on the first search
hit and the id was used for scoring. The live OT API was reachable throughout;
no synthetic fallback was used at any point.

---

## Headline findings

1. **Two pan-autoimmune hubs recur in the top-10 of 4/8 diseases each:**
   **IL12B** (IL-12/23 p40; ra, cd, uc, pso) and **TYK2** (ra, sle, pso, t1d).
   These are the shared IL-12/23 → TYK2 signalling spine — exactly the axis the
   clinic converged on (ustekinumab, deucravacitinib) across RA-spectrum,
   IBD and psoriasis.
2. **The ranker rediscovers validated, marketed drug targets across the panel
   without being told any drug information** (the ranker excludes the OT
   `clinical`/known-drug datatype from its biological axis by design — see
   caveats). Most striking single result: **myasthenia gravis top-2 = C5
   (rank 1) and FcRn/FCGRT (rank 2)** — the two mechanisms of the actual
   approved MG biologics (eculizumab, efgartigimod). That is a clean,
   drug-blind rediscovery of the MG standard of care.
3. **Disease-specific top hits track known disease genetics:** SLE → TLR9/TREX1/
   DNASE1L3/IRF5/IFNAR1 (interferon/nucleic-acid-sensing axis), Crohn → NOD2/
   ATG16L1/IL23R (autophagy + barrier), T1D → CTLA4/PTPN22-adjacent islet genes,
   MG → C5/FcRn/AChE. The panel separates cleanly into biologically coherent
   per-disease signatures rather than one generic "inflammation" list.

---

## Validated-target rediscovery (face-validity check)

Drug-blind ranker vs. the real autoimmune target landscape. "Top-10 in" = the
diseases where the target landed in that disease's top-10; "best rank" = its
single highest placement in the panel.

| Target | Known drug / role | Top-10 in | Best rank |
|--------|-------------------|-----------|:---------:|
| **C5** | complement C5 — eculizumab/ravulizumab (MG, gMG) | mg | **#1 mg** |
| **FCGRT** | FcRn — efgartigimod/rozanolixizumab (MG) | mg | **#2 mg** |
| **IL23R** | IL-23 receptor (IBD genetics) | cd, uc | **#1 uc** |
| **IL12B** | IL-12/23 p40 — ustekinumab | ra, cd, uc, pso | **#1 pso** |
| **TYK2** | TYK2 — deucravacitinib | ra, sle, pso, t1d | #4 ra |
| **IL17A** | IL-17A — secukinumab/ixekizumab | ra, pso | #4 pso |
| **IL17F** | IL-17F — bimekizumab (dual A/F) | pso | #10 pso |
| **TNF** | TNF — adalimumab/infliximab | uc, pso | #7 pso |
| **CTLA4** | CTLA-4 — abatacept | ra, t1d | #4 t1d |
| **CD40** | CD40 — iscalimab | ra | #3 ra |
| **IL2RA** | IL-2Rα (MS genetics; basiliximab) | ms | #2 ms |
| **JAK2** | JAK2 — tofa/upadacitinib family | uc | #8 uc |
| **JAK3** | JAK3 — tofacitinib | uc | #10 uc |
| **MS4A1** | CD20 — rituximab/ocrelizumab (MS) | ms | #10 ms |
| **S1PR1** | S1P₁ — fingolimod/ozanimod (MS) | ms | #9 ms |
| **IL6R** | IL-6R — tocilizumab (RA) | — | #11 ra |
| **IL23A** | IL-23 p19 — risankizumab/guselkumab | — | #12 uc |
| **TNFSF13B** | BAFF/BLyS — belimumab (SLE) | — | #11 sle |
| **ITGA4** | α4 integrin — natalizumab/vedolizumab | — | #12 ms |

**Verdict:** high face validity. Of the canonical autoimmune target list,
**15 land in a disease top-10** in the correct disease, and the remaining
"misses" (IL6R, IL23A, BAFF, α4-integrin) all sit at **rank #11–12** — just
outside the top-10 cut, not absent. The ranker is not producing novelty; it is
faithfully reconstructing the known autoimmune target map from genetics +
literature + pathway + animal-model evidence.

---

## Cross-disease recurrence — pan-autoimmune hubs vs. disease-specific

**Recurring across ≥2 disease top-10s (pan-autoimmune hubs):**

| Target | # diseases | Diseases | Interpretation |
|--------|:----------:|----------|----------------|
| **IL12B** | 4 | ra, cd, uc, pso | IL-12/23 p40 hub — the shared psoriasis/IBD/RA axis |
| **TYK2**  | 4 | ra, sle, pso, t1d | downstream kinase of IL-12/23 + type-I IFN |
| **IL23R** | 2 | cd, uc | IBD-shared IL-23 receptor |
| **GPR35** | 2 | cd, uc | IBD-shared (both colitides) |
| **IL10**  | 2 | cd, uc | IBD-shared regulatory cytokine |
| **IL17A** | 2 | ra, pso | Th17 axis (RA + psoriasis) |
| **TNF**   | 2 | uc, pso | classic broad anti-TNF target |
| **CTLA4** | 2 | ra, t1d | T-cell costimulation checkpoint |
| **TLR9**  | 2 | ra, sle | nucleic-acid sensing (autoantibody diseases) |
| **SH2B3** | 2 | cd, t1d | shared immune-regulatory locus |
| **KCNA1 / KCNA3** | 2 each | ms, mg | see caveat — neuro-channel artefact of the neuro-immune diseases |

The IBD pair (cd/uc) shares the most top-10 members (IL23R, GPR35, IL10, IL12B),
consistent with their overlapping genetics. RA sits at the crossroads of the
Th17 (IL17A/IL12B) and costimulation (CD40/CTLA4/CD80) axes.

**Disease-specific leaders (top-5 gene unique to that disease's top-10):**

| Disease | Disease-specific top hits | Known biology |
|---------|---------------------------|---------------|
| RA  | MIF, FCRL3, CD40 | costimulation / RA-genetic FCRL3 |
| SLE | TREX1, BLK, SLC15A4, DNASE1L3 | nucleic-acid clearance / IFN |
| MS  | TNFRSF1A, IL2RA, NR3C1, DHODH, KCNQ1 | MS GWAS (TNFRSF1A, IL2RA), DHODH=teriflunomide |
| CD  | NOD2, LACC1, TNFSF15 | Crohn autophagy/barrier signature |
| UC  | MST1 | UC-specific locus |
| PSO | IL36RN, CARD14 | pustular-psoriasis Mendelian genes |
| T1D | CD226, CTSH, SLC5A2 | islet-autoimmunity loci (SLC5A2=SGLT2) |
| MG  | C5, FCGRT, ACHE | complement + FcRn + cholinesterase |

Each disease's private signature is biologically on-target for that disease —
the pipeline is discriminating between diseases, not returning a shared
inflammation blob.

---

## Per-disease top-10 scorecards

Score = OT-style weighted-harmonic-sum over disease-evidence axes
(genetic_support, biological_relevance, cell_specificity, expression), reduced
by a safety penalty. Tier cuts: T1 ≥0.65, T2 ≥0.45, T3 ≥0.30, else T4.

### Rheumatoid arthritis (top=MIF 0.90; 15×T1)
| # | Gene | Score | Tier |
|--:|------|------:|------|
| 1 | MIF | 0.90 | TIER 1 |
| 2 | FCRL3 | 0.84 | TIER 1 |
| 3 | CD40 | 0.84 | TIER 1 |
| 4 | TYK2 | 0.81 | TIER 1 |
| 5 | TLR9 | 0.80 | TIER 1 |
| 6 | CD80 | 0.80 | TIER 1 |
| 7 | PADI4 | 0.79 | TIER 1 |
| 8 | IL12B | 0.79 | TIER 1 |
| 9 | CTLA4 | 0.78 | TIER 1 |
| 10 | IL17A | 0.78 | TIER 1 |

### Systemic lupus erythematosus (top=TLR9 0.98; 20×T1)
| # | Gene | Score | Tier |
|--:|------|------:|------|
| 1 | TLR9 | 0.98 | TIER 1 |
| 2 | TREX1 | 0.83 | TIER 1 |
| 3 | BLK | 0.78 | TIER 1 |
| 4 | SLC15A4 | 0.78 | TIER 1 |
| 5 | DNASE1L3 | 0.77 | TIER 1 |
| 6 | IFNAR1 | 0.77 | TIER 1 |
| 7 | IRF5 | 0.77 | TIER 1 |
| 8 | TYK2 | 0.76 | TIER 1 |
| 9 | WDFY4 | 0.76 | TIER 1 |
| 10 | TNFSF4 | 0.74 | TIER 1 |

_Note: IFNAR1 (anifrolumab) and TNFSF4/OX40L (itolizumab-class) also validated hits._

### Multiple sclerosis (top=TNFRSF1A 0.62; 0×T1, mostly T4)
| # | Gene | Score | Tier |
|--:|------|------:|------|
| 1 | TNFRSF1A | 0.62 | TIER 2 |
| 2 | IL2RA | 0.61 | TIER 2 |
| 3 | NR3C1 | 0.41 | TIER 3 |
| 4 | DHODH | 0.30 | TIER 4 |
| 5 | KCNQ1 | 0.25 | TIER 4 |
| 6 | KCNA3 | 0.24 | TIER 4 |
| 7 | KCNA1 | 0.21 | TIER 4 |
| 8 | KEAP1 | 0.20 | TIER 4 |
| 9 | S1PR1 | 0.18 | TIER 4 |
| 10 | MS4A1 | 0.18 | TIER 4 |

_MS scores low overall (polygenic, diffuse evidence per target) but the ordering
still surfaces IL2RA, DHODH (teriflunomide), S1PR1 (fingolimod), MS4A1/CD20
(ocrelizumab), KEAP1 (dimethyl-fumarate/Nrf2) — five approved MS mechanisms in
the top-10 despite low absolute scores._

### Crohn disease (top=NOD2 0.83; 12×T1)
| # | Gene | Score | Tier |
|--:|------|------:|------|
| 1 | NOD2 | 0.83 | TIER 1 |
| 2 | LACC1 | 0.78 | TIER 1 |
| 3 | TNFSF15 | 0.77 | TIER 1 |
| 4 | IL12B | 0.77 | TIER 1 |
| 5 | IL23R | 0.75 | TIER 1 |
| 6 | GPR35 | 0.74 | TIER 1 |
| 7 | ATG16L1 | 0.74 | TIER 1 |
| 8 | PTPN22 | 0.71 | TIER 1 |
| 9 | IL10 | 0.69 | TIER 1 |
| 10 | SH2B3 | 0.67 | TIER 1 |

### Ulcerative colitis (top=IL23R 0.75; 7×T1)
| # | Gene | Score | Tier |
|--:|------|------:|------|
| 1 | IL23R | 0.75 | TIER 1 |
| 2 | GPR35 | 0.74 | TIER 1 |
| 3 | IL12B | 0.73 | TIER 1 |
| 4 | MST1 | 0.71 | TIER 1 |
| 5 | IL10 | 0.70 | TIER 1 |
| 6 | FCGR2A | 0.69 | TIER 1 |
| 7 | CXCR2 | 0.67 | TIER 1 |
| 8 | JAK2 | 0.64 | TIER 2 |
| 9 | TNF | 0.55 | TIER 2 |
| 10 | JAK3 | 0.32 | TIER 3 |

### Psoriasis (top=IL12B 0.85; 9×T1)
| # | Gene | Score | Tier |
|--:|------|------:|------|
| 1 | IL12B | 0.85 | TIER 1 |
| 2 | IL36RN | 0.85 | TIER 1 |
| 3 | CARD14 | 0.84 | TIER 1 |
| 4 | IL17A | 0.81 | TIER 1 |
| 5 | TYK2 | 0.81 | TIER 1 |
| 6 | TRAF3IP2 | 0.76 | TIER 1 |
| 7 | TNF | 0.71 | TIER 1 |
| 8 | ITGB2 | 0.68 | TIER 1 |
| 9 | VDR | 0.68 | TIER 1 |
| 10 | IL17F | 0.64 | TIER 2 |

_Psoriasis is the cleanest rediscovery: IL12B, IL17A, TYK2, TNF, IL17F — five of
its top-10 are the marketed psoriasis mechanisms._

### Type 1 diabetes mellitus (top=CD226 0.84; 18×T1)
| # | Gene | Score | Tier |
|--:|------|------:|------|
| 1 | CD226 | 0.84 | TIER 1 |
| 2 | CTSH | 0.83 | TIER 1 |
| 3 | SH2B3 | 0.82 | TIER 1 |
| 4 | CTLA4 | 0.77 | TIER 1 |
| 5 | SLC5A2 | 0.77 | TIER 1 |
| 6 | SUOX | 0.76 | TIER 1 |
| 7 | TYK2 | 0.76 | TIER 1 |
| 8 | SIRPG | 0.76 | TIER 1 |
| 9 | GCGR | 0.75 | TIER 1 |
| 10 | CTRB2 | 0.74 | TIER 1 |

_T1D surfaces its islet-autoimmunity GWAS loci (CD226, PTPN-adjacent SH2B3, CTLA4,
SIRPG) plus metabolic targets (SLC5A2=SGLT2, GCGR=glucagon receptor)._

### Myasthenia gravis (top=C5 0.73; 1×T1)
| # | Gene | Score | Tier |
|--:|------|------:|------|
| 1 | C5 | 0.73 | TIER 1 |
| 2 | FCGRT | 0.45 | TIER 2 |
| 3 | KCNA4 | 0.43 | TIER 3 |
| 4 | KCND3 | 0.43 | TIER 3 |
| 5 | ACHE | 0.37 | TIER 3 |
| 6 | KCNS3 | 0.34 | TIER 3 |
| 7 | KCNH5 | 0.30 | TIER 4 |
| 8 | KCNA1 | 0.24 | TIER 4 |
| 9 | KCNV2 | 0.21 | TIER 4 |
| 10 | KCNA3 | 0.07 | TIER 4 |

_MG top-2 = C5 (eculizumab) and FcRn (efgartigimod) — the exact two mechanisms of
the approved MG biologics. The KCN* potassium-channel cluster below them is a
known OT artefact for the neuro-immune diseases (see caveats)._

---

## Honest caveats

- **This is evidence-driven prioritisation, not novel discovery.** The ranker
  aggregates existing Open Targets evidence (human genetics, literature, animal
  models, pathways, RNA expression) into a transparent weighted score. A high
  rank means "this target has strong, converging, published disease evidence" —
  it does **not** mean a new mechanism was discovered. Every result above is a
  *rediscovery* of established biology; the value is the ranking/triage, the
  provenance trail, and cross-disease consistency, not new hypotheses.
- **Drug-blind by design, but not fully independent of the clinic.** The
  `query_opentarget.nf` biological-relevance axis excludes the OT `clinical`
  (known-drug) datatype (weight 0), so a target cannot rank purely because it is
  already drugged. However, `literature` and `genetic_association` are still
  richer for well-studied, already-drugged targets, so the rediscovery is a
  face-validity check, **not** a claim of blind prediction. Reproduce with drug-
  naïve historical genetics to make a stronger novelty claim.
- **Neuro-immune diseases (MS, MG) score low and are contaminated by
  potassium-channel genes** (KCNA1/3/4, KCND3, KCNQ1, etc.). These channels
  carry OT association to neurological phenotypes that are co-annotated with MS/
  MG, inflating them into the top-10 even though they are not autoimmune drug
  targets. For these two diseases the *real* targets (C5, FcRn, IL2RA, S1PR1,
  MS4A1, DHODH) are present but interleaved with channel noise — an
  expression/cell-specificity axis (currently empty from the OT query alone)
  would help separate them.
- **Coverage is thin (OT-only).** The evidence table populates only
  `genetic_support`, `biological_relevance`, `tractability`, `safety_liability`;
  `cell_specificity` and `expression_lfc/padj` are empty because they come from
  other tools (scRNA / DE). Many top targets therefore score at 35–65% axis
  coverage and are correctly flagged provisional. Fusing in a disease scRNA/DE
  run would raise coverage and likely re-order the mid-tiers.
- **n=25 per disease** is a shallow slice of each disease's associated-target
  list; targets ranked #11–12 (IL6R, IL23A, BAFF, α4-integrin) fell just outside
  the top-10 cut, so top-10 membership is a hard threshold, not a hard boundary
  in the underlying evidence.

---

## Many-use-case test result

**8/8 diseases passed both pipeline stages (16/16 workflow invocations, 0
failures).** No disease failed to run. The apostrophe/paren param-quoting bug was
avoided by resolving each disease to its MONDO id up front and passing the id
(and an apostrophe-free display name to the scorecard). The live OT GraphQL API
was reachable for all 16 calls; the no-fabrication guard in both workflows
(header-only CSV on failure) was never triggered. Raw outputs (evidence CSVs,
scorecards, JSON, per-disease reports) are under the run workspace
`…/scratchpad/panel/<slug>/` (transient scratch; regenerate by re-running the
two workflows with the MONDO ids in the table above).
