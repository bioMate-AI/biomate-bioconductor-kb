# Study Protocol — A Cross-Target, Mechanism-Aware Predictor of Renal Retention for Radiopharmaceutical Design

**Status:** design protocol (pre-analysis plan). **Date:** 2026-10-22.
**Target venue:** J Nucl Med / EJNMMI / J Med Chem (model+prospective) → Nature Communications (if prospective + dataset land).

---

## 1. Why this is a high-end paper (the gap)

Renal retention is **the** dose-limiting toxicity of peptide and small-molecule radioligand therapy (RLT):
every published αvβ6 radioligand has tumour-to-kidney absorbed-dose ratio < 1; the benchmark is public and
numeric (beat 0.66 Gy/GBq, ¹⁷⁷Lu-Therahexin; target 0.3, Pluvicto territory). Yet renal-retention management
is still **empirical** — net positive charge → megalin reabsorption, amino-acid/gelofusine co-infusion — with
**no validated, generalizable predictive model** and **no structured cross-target dataset**. Our preliminary
work shows the field heuristic is not merely weak but **sign-inverted** (net-charge→retention flips between
cationic and anionic ligands; mean-per-class Spearman −0.40), so a learned, mechanism-aware, target-agnostic
predictor is both missing and needed.

**Four contributions, each independently publishable, together high-impact:**
1. **The first large, curated, renal-protection-stratified, cross-target radioligand renal-biodistribution
   database** (a resource paper in its own right).
2. **A predictive model that generalizes to target classes it never trained on** (the scientific claim).
3. **Mechanistic insight** recovered from the model (charge sign-flip, modality- and protection-gating).
4. **Model-guided generative design** of a lower-renal-dose αvβ6 construct, with **prospective validation**.

---

## 2. Scientific question & hypotheses (pre-registered)

- **H1 (beats heuristic):** a structure/mechanism model predicts kidney retention better than the net-charge
  heuristic and logD, across targets. *Preliminary:* integrin LOTO mean-per-class ρ=0.78, perm p=0.012.
- **H2 (cross-target generalization):** performance holds under Leave-One-Target-class-Out and
  Leave-One-Sequence-cluster-Out (not memorizing near-duplicates).
- **H3 (covariate necessity):** renal-protection status, modality (peptide vs small molecule), timepoint and
  species are necessary covariates (ablation degrades performance significantly).
- **H4 (temporal/prospective):** the model predicts the rank of constructs published *after* the training
  cut-off, and (gold standard) of newly synthesized αvβ6 variants, while binder affinity is preserved.

Primary estimand: **mean within-held-out-target Spearman** (ranking constructs within an unseen target).
Secondary: calibrated regression on log kidney %ID/g (MAE, R²) and human Gy/GBq.

---

## 3. Dataset (the resource) — target ≥ 400–600 constructs, ≥ 8 target classes

**Unit of observation:** (construct, species, timepoint, renal-protection) → one labeled point; a construct
measured at 1h/4h/24h/72h yields multiple points, with **timepoint (h) and species as model covariates**
(this is how we scale honestly without pooling incomparable magnitudes).

**Fields:** structure (one-letter sequence and/or canonical SMILES), chelator, radiometal, albumin-binder,
cleavable-linker, net charge (computed: peptide Henderson-Hasselbalch / chelator-aware SMILES; or paper-
stated when terminal mods aren't sequence-encoded), kidney label (%ID/g + timepoint, or human Gy/GBq),
tumour:kidney, **renal_protection (mandatory, never imputed)**, provenance (DOI/PMID + table/figure).

**Sourcing (industrial, not ad hoc):**
- Systematic search (PubMed/EuropePMC/Scholar) across PSMA, SSTR, GRPR, FAP, αvβ6, αvβ3, MC1R, CCK2, NTS1,
  GLP-1R, CXCR4, folate, LHRH — agonist & antagonist, mono/multimeric, ± albumin binder, ± cleavable linker.
- Extraction tiers: (T1) machine-readable JATS/XML tables; (T2) supplementary .xlsx/.docx biodistribution
  tables; (T3) **figure digitization** (WebPlotDigitizer-style) for the large fraction reported only in
  bar/TAC figures — the current binding constraint.
- **QC:** dual independent extraction + reconciliation; report inter-annotator agreement; unit normalization
  (%ID/g vs %IA/g identical; mGy/MBq=Gy/GBq for ¹⁷⁷Lu; ²²⁵Ac RBE-Sv NOT converted); provenance to the table.
- **Splits defined before modeling:** (a) target-class, (b) sequence/scaffold cluster (Tanimoto/edit-distance
  ≥ threshold), (c) temporal (publication-year cut-off).

**Current state:** 136 constructs ingested through a citation-integrity gate (quarantines no-DOI / no-label /
no-protection); the extraction pipeline + stratified harness exist. **Gap to target:** ×3–4 more constructs,
dominated by figure-only data → requires the figure-digitization tier.

---

## 4. Models & baselines

**Baselines (must be beaten):** signed net charge; |net charge|; logD; MW/TPSA; a published heuristic; random.
**Interpretable model:** gradient boosting / RF on mechanistic descriptors (charge signed+abs, basic/acidic
residue counts, logD, MW, TPSA, HBD/HBA, chelator, radiometal, albumin-binder, cleavable-linker, modality,
timepoint, species). This is the primary model (interpretable, robust at n).
**Representation models (test, report honestly):** ESM-2 embeddings (peptides) / ChemBERTa / Morgan
(small molecules) → likely *not* better at this n (state it; cite the KB-dividend/representation-wall result).
**Mechanistic/hybrid:** a PBPK-style term (glomerular filtration × megalin-binding ~ f(charge)) as a feature
or a grey-box layer — turns the charge sign-flip into an explicit mechanism.
**Multi-task:** predict the full kidney time-activity curve (shares strength across timepoints).

---

## 5. Evaluation (the rigor that distinguishes it)

- **Nested cross-validation** (inner for tuning, outer for reporting) under **three held-out schemes:**
  (a) Leave-One-Target-class-Out — generalization to a new target (**headline**);
  (b) Leave-One-Sequence-cluster-Out — rules out near-duplicate leakage;
  (c) Temporal (train ≤ cut-off, test later years) — quasi-prospective.
- **Metrics:** mean within-class Spearman (primary); pooled Spearman (timepoint modeled → valid); MAE & R²
  on log %ID/g; AUC for a clinically meaningful "high-renal" threshold.
- **Uncertainty:** cluster bootstrap by construct (not by observation — avoids timepoint pseudo-replication);
  conformal prediction intervals on the regression.
- **Significance:** permutation tests (shuffle within class); paired model-vs-baseline bootstrap CI.
- **Ablations (H3):** drop protection / modality / timepoint / species, each with ΔSpearman + CI.
- **Interpretability:** SHAP / permutation importance → recover the charge sign-flip and the megalin mechanism;
  partial-dependence of retention on net charge, stratified by modality.
- **Calibration:** reliability plot; report whether predicted Gy/GBq is calibrated against the 0.66/0.42/0.30
  clinical anchors.
- **Power analysis:** simulate to state the n-per-class needed to detect the observed effect (mean-per-class
  ρ≈0.5–0.8) at 80% power — this sets the dataset target and the Gate-A n≥50 bar.

---

## 6. Validation & translational application (the differentiator)

- **Temporal held-out** (cheap, in-silico): already specified in §5(c).
- **Model-guided generative design:** SNG rule-constrained generator + Bayesian optimizer over
  spacer/linker/chelator (**binder frozen**), minimizing predicted renal retention subject to developability /
  FTO / binding-preserve guards (IC50 within 10×, selectivity vs αvβ3/αvβ5/α5β1). Levers and their effect
  sizes are pre-quantified (cleavable Met-Val-Lys −70/−77%; charge non-monotonic; gelofusine −61/−85%;
  albumin binder = T:K lever, not renal-sparing).
- **Prospective wet-lab validation (gold standard):** synthesize N (~8–12) αvβ6 variants spanning predicted
  low→high renal retention; radiolabel (¹⁷⁷Lu-DOTA); measure mouse kidney %ID/g and T:K; test predicted vs
  observed rank (pre-registered). Confirm binder preserved. **This closes design→predict→measure** and is what
  lifts the paper from methods to impact. (Synthesis is never automated; hybrid SDL per program policy.)

---

## 7. Phased plan with go/no-go gates

| Phase | Work | Gate (go/no-go) |
|---|---|---|
| **P0 (done)** | pipeline, 136-construct corpus, charge models, stratified LOTO, paper-grade eval harness | harness refuses to certify below n≥50 ✔ |
| **P1 — Dataset** | scale to ≥400–600 constructs incl. figure-digitization tier; dual-annotator QC | ≥50 sequence-resolved/charge-computable per ≥4 classes in ≥1 homogeneous stratum |
| **P2 — Modeling** | 3-scheme nested CV; baselines; ablations; SHAP; conformal | **Gate A passes:** model > net-charge on LOTO at 95% CI *and* permutation p<0.05 |
| **P3 — Temporal** | train≤cut-off / test-later quasi-prospective | positive, CI-separated from baseline |
| **P4 — Design** | generative loop → shortlist αvβ6 low-renal candidates (binder frozen) | predicted Gy/GBq < 0.66 with preserved binding |
| **P5 — Prospective** | synthesize + radiolabel + mouse biodistribution | observed rank matches prediction; a candidate beats 0.66 |

**No synthesis spend (P5) until P2 Gate A passes on real data.** No claim stated beyond the CV scheme that
supports it. No data excluded to inflate a metric.

---

## 8. Honest limitations & risks

- **Data scale** is the binding constraint, and much of the literature reports kidney uptake only in figures
  → figure digitization (with its own error model) is required; we will report digitization uncertainty.
- **Heterogeneity:** species, model, protocol, protection differ across labs → modeled as covariates and
  stratified; residual batch effects remain a threat (addressed by cluster-CV + sensitivity analysis).
- **Small per-class n** for rare targets → those classes enter as test-only or are pooled by mechanism.
- **Prospective validation cost/time** is real; a strong temporal held-out is the fallback for a methods paper.

---

## 9. Figure/table plan (what the paper shows)

F1 dataset descriptor (classes × constructs × timepoints × protection). F2 model-vs-baseline under 3 CV
schemes with CIs. F3 SHAP mechanism (charge sign-flip; modality gating). F4 calibration/conformal vs clinical
anchors. F5 design: predicted-renal landscape + shortlisted candidate. F6 prospective predicted-vs-observed.
Table 1 dataset stats; Table 2 full model comparison; Table 3 designed candidates (predicted Gy/GBq, binding).

---

## 10. Innovation — what makes this a METHOD paper, not an application

A gradient-boosting regressor with Leave-One-Target-Out is an *application*, not a contribution. The
publishable innovations are:

1. **PK–binding decomposition (conceptual contribution).** We formalize radioligand in-vivo behavior as a
   product of a **target-specific binding** term and a **target-agnostic pharmacokinetic (renal)** term, and
   show empirically that the renal term *transfers across binding targets* (Leave-One-Target-Out) while
   binding does not. This reframes radiopharmaceutical property prediction: renal optimization is a reusable,
   cross-program sub-problem solvable once and applied to any target. (It is the mirror image of the
   cyclic-binder cross-target wall, which is representation-deep and does NOT transfer.)

2. **Mechanistic grey-box renal-retention model (the core method).** A differentiable, physiology-informed
   model rather than a black box:
   `retention ≈ GFR_sieving(size, charge) × megalin_reabsorption(net_charge, basic_count; saturable Hill) ×
   residualization(radiometal) + tubular_route(small_molecule)`.
   A handful of interpretable parameters fit across targets. It (a) **transfers because it is mechanism**,
   (b) **explains the sign-flip** — megalin reabsorbs filtered *cationic* peptides, whereas anionic poly-Glu
   ligands enter via a distinct route, so a single signed-charge term cannot work and a saturable two-route
   model can, (c) yields parameters a radiochemist can act on. Beating BOTH the net-charge heuristic AND a
   black-box ML model on cross-target CV is the headline methodological result.

3. **Sample-efficient, uncertainty-aware design under data scarcity (turns small-n into the method).**
   Conformal prediction intervals for honest per-construct uncertainty + Bayesian active learning to choose
   the most informative next constructs to synthesize (minimize predicted-renal-dose variance per synthesis
   dollar), feeding the generative linker/spacer/chelator loop (binder frozen). The small-data regime becomes
   a principled active-design problem, not a weakness.

4. **The resource.** First structured, renal-protection-stratified, cross-target radioligand renal-
   biodistribution database with provenance — valuable independent of the model.

**Minimum bar for "method paper":** innovations 1+2 (decomposition + mechanistic grey-box) with the 3-scheme
CV and SHAP/mechanism. Innovation 3 and the prospective step lift it toward the top tier.

---

## 11. Target journal ladder (honest, tied to scope delivered)

| Scope delivered | Realistic venue |
|---|---|
| GBM + LOTO on ~150 constructs, no mechanism/prospective | specialist only: EJNMMI Research, Mol Pharmaceutics |
| + mechanistic grey-box model + PK–binding decomposition + 3-scheme CV + SHAP + **temporal** validation | **J Nucl Med / EJNMMI / J Med Chem** (field-leading, high impact) |
| + **prospective wet-lab** (synthesized variants, measured mouse kidney) + a designed candidate beating 0.66 Gy/GBq | **Nature Communications / Nat Biomed Eng / JACS Au** |

We will not claim a tier above the scope actually delivered.

---

## 12. Additional work required (beyond §7 phases)

- **Build + validate the mechanistic grey-box model** (innovation 2) — the single most important new piece;
  without it this is an application, not a method.
- **Dataset scale-up to ≥ 400–600 constructs** via the figure-digitization tier, WITH a digitization error
  model (report read uncertainty) and dual-annotator QC / inter-annotator agreement.
- **Conformal + Bayesian-active-learning design module** (innovation 3) — new code + a selection policy.
- **Binder-preservation evidence** for designed candidates: docking/FEP ΔΔG within 10× IC50 and selectivity
  vs αvβ3/αvβ5/α5β1 (ideally one wet-lab binding readout).
- **Mouse %ID/g → human Gy/GBq calibration bridge** — a known-hard translational step; needs the paired
  preclinical+clinical constructs we already have (Therahexin, PSMA-617, DOTATATE) as anchors + a dosimetry
  model; flagged as a limitation if it cannot be closed.
- **Prospective synthesis + radiolabel + biodistribution** — requires a radiochemistry collaborator/CRO;
  this is the gate between a strong specialist paper and a top-tier one.
- **Comparison vs any existing PBPK renal models** (e.g. published kidney dosimetry/PBPK) as an external
  baseline, so the mechanistic claim is benchmarked, not asserted.
