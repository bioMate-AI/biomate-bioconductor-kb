# LEAVE-HLA-OUT DECISION GATE — does the widened H4 thesis generalize across HLA backgrounds?

**Artifact:** `leave_hla_out_gate.py` · **Dry-run:** `DRYRUN_leave_hla_out_gate_PXD056426.json`
**training_eligible = FALSE** (this is an evaluation/decision harness, not a training artifact).
**Date:** 2026-09-13.

This is the gate that **sizes any future CRO spend** on the presentation (H4) thesis. It answers
one question: the H4 result — *presentation is controlled by antigen-processing MACHINERY STATE,
not by source-protein abundance* — is validated on **ONE** HLA background so far (HAP1 / PXD056426).
**Does that machinery→presentation relationship TRANSFER to HLA backgrounds it was never learned
on?** If yes on public data, the CRO shrinks. If no, the CRO must buy the missing cells.

---

## 1. What the harness computes

Each **deposit == one HLA background**, with KO/WT conditions and (where available) a matched
proteome. Per deposit the gate computes:

- **B1 baseline** — `Spearman(presentation_frac_of_WT, proteome_frac_of_WT)` across KO conditions.
  B1 is the "presentation ∝ source-protein abundance" null (OBJECTIVES.md §8.2). B1 "works" only if
  presentation tracks abundance (rho > 0).
- **H4 discriminative metric** — `presentation_loss_beyond_abundance = proteome_frac − immunopeptidome_frac`
  per KO; the **mean over machinery essentials** is the beyond-abundance effect. A large positive value
  means *the source protein is still there but the peptide is not presented* → machinery-state, not
  abundance, controls presentation. `H4_local_win = (mean essential beyond-abundance > 0.15) AND
  (B1 rho ≤ 0.3)`.

Across deposits — the **actual generalization gate**:

- **Leave-HLA-out CV** — hold out each HLA background; fit `presentation_loss ~ machinery-severity`
  on the OTHER backgrounds; predict the held-out KOs from an **HLA-agnostic machinery-severity prior
  only**; score transfer with Spearman(predicted, observed). The **primary statistic is the POOLED
  cross-fold Spearman** (all held-out (pred,obs) pairs in one correlation → adequate n, smooth null).
- **Permutation null** — shuffle the machinery↔loss labels within each training fold, re-run LOO,
  build the null distribution of the pooled statistic, report a one-sided permutation p-value.
- **Leakage check** — (a) the predictor uses ONLY the KO gene's machinery-severity (HLA-agnostic),
  never the held-out deposit's own peptides → transfer must be machinery-driven, not memorized;
  (b) an HLA-allele overlap report flags shared-allele leakage across folds (transfer must not ride
  on a shared allele). PASS requires **disjoint alleles across folds**.

### Why an HLA-agnostic severity prior is the transfer feature (not leakage)
`MACHINERY_SEVERITY` (in the script) grades each antigen-processing gene by its KNOWN pathway role
(B2M/TAP2/TAP1/TAPBP highest, regulators mid, chaperones low). It is a **biology prior**, fit to no
held-out deposit. Using it as the transfer feature makes "does machinery role predict presentation
loss on an unseen HLA background?" a fair, leakage-free test. It is a **conservative floor**: a
trained H4 head could do better, OR reveal HLA-specific processing the flat prior misses.

---

## 2. Dry-run on HELD data — the harness is proven to run

**PXD056426 (HAP1, APM-KO immunopeptidome + matched proteome; class-I).** Pulled from
`s3://knowledge-datasets-1759951976/immunology_sc_corpus_broad/acquisitions/immunopeptidome/PXD056426/Search.zip`
(124 MB, peptide-list level — no raw MS). The single zip contains the matched immunopeptidome
(`Search_results_DIA.tsv`), the matched proteome (`search_results_proteomics.tsv`), and the
condition map (`Raw_file_list.xlsx`) → a complete B1+H4 compute on one HLA background.

| metric | value |
|---|---|
| WT immunopeptidome (unique 8–25mer peptides, FDR 1%) | 18,624 |
| conditions | 12 (WT + 11 machinery KO), matched proteome present |
| **B1 Spearman (presentation vs proteome abundance)** | **−0.591** (B1 baseline INVERTED — abundance does not explain presentation) |
| **H4 mean essential loss-beyond-abundance** | **0.722** (essentials lose 72 pp of presentation the proteome cannot explain) |
| **H4 local win** | **TRUE** |

Per-KO (fraction of WT): B2M 0.028, TAP2 0.17, TAPBP 0.24, ERP57 0.39, TAP1 0.49, ERAP1 0.50 —
the antigen-processing essentials are the top presentation losers while their proteomes stay at
0.98–1.36× WT. This **reproduces the prior HAP1 kill-gate** (`HAP1_H4_DISCRIMINATIVE_RESULT.json`:
rho −0.51, ~87 pp; minor differences are aggregation choices — unique-peptide counts vs summed
spectral counts across all 12 conditions). **The B1+H4 compute path and the loaders are proven.**

**Gate verdict on the dry-run: `INSUFFICIENT_DEPOSITS_FOR_CROSS_HLA_GATE`** — correct by design.
Leave-HLA-out cannot run on one background; the dry-run proves the compute, not the cross-HLA result.

### PXD020079 (glioblastoma CIITA, HLA-II) — held but NOT processable here
The S3 copy is **6 raw-MS `.raw` files (0.6–4.4 GB each), no peptide lists**. With ~5.8 GB free disk
and a peptides-not-raw-MS constraint, it cannot be searched in this environment. Once the aggregation
agent produces its **normalized per-condition table** (CIITA-KO vs WT, class-II), it drops straight
into the inventory path as a second, class-II HLA background — no code change.

### Self-tests that prove the cross-HLA gate discriminates (synthetic, clearly labeled)
Because only one real background is processable here, the LOO / null / leakage / verdict paths were
validated on synthetic inventories (in scratch; NOT delivered as results):

| scenario | pooled transfer rho | perm p | verdict |
|---|---|---|---|
| machinery-driven loss, 4 disjoint-HLA bg × 11 KO | **0.907** | **0.0057** | **PASS_generalizes_across_HLA** |
| loss RANDOM (unrelated to machinery), 4 bg | 0.048 | 0.19 | FAIL_or_UNPROVEN |

The negative control also produced 4/4 **local** H4 wins — a deliberate demonstration that
**per-deposit local H4 wins do NOT imply cross-HLA transfer**; only the leave-HLA-out gate settles it.

---

## 3. How it runs across ALL HLA backgrounds once aggregation lands

The aggregation agent produces `H4_CORPUS_INVENTORY.json` (absent at build time — handled gracefully).
Expected per-deposit entry (flexible):

```json
{"deposit":"PXDxxxxxx","hla_background":"cellline;HLA-A*..;HLA-B*..;HLA-C*..","hla_class":"I",
 "conditions":[{"condition":"B2M","immunopeptidome_frac":0.03,"proteome_frac":1.19}, ...]}
```
or `{"deposit":..,"deposit_dir":"/path"}` to trigger a built-in loader (currently the FragPipe/DIA-NN
`Search.zip` loader that ran the dry-run). Then:

```bash
python leave_hla_out_gate.py --inventory H4_CORPUS_INVENTORY.json --out CROSS_HLA_GATE_RESULT.json --n-perm 3000
```

**Before gating, group by `hla_class`** — class-I and class-II use different machinery, so a LOO fold
must not mix them (a caveat in the JSON). Run the gate once per class when the corpus spans both.

---

## 4. The PASS/FAIL rule that sizes the CRO

**PASS** (`PASS_generalizes_across_HLA`) requires ALL of:
1. pooled cross-fold transfer Spearman **≥ 0.30**,
2. permutation p-value **≤ 0.05**,
3. **≥ 3** HLA backgrounds each carry a positive ordering (transfer ≥ 0.3 per fold) — not one dominant fold,
4. **disjoint HLA alleles across folds** (no shared-allele leakage).

| verdict | meaning | **CRO sizing** |
|---|---|---|
| **PASS** | machinery→presentation transfers across HLA on PUBLIC data | **SHRINK the CRO** — it need only fill genuinely missing HLA×KO cells + add absolute quant / MS-detectability censoring; the thesis is NOT re-established on the CRO's dime. |
| **FAIL / UNPROVEN** | transfer indistinguishable from null, or carried by <3 backgrounds, or allele-leaky | **CRO MUST supply the missing cells** — ≥3 distinct HLA backgrounds × the machinery-KO panel + matched proteome, before H4 can be trained/claimed cross-allele. The expensive path. |
| INSUFFICIENT / TWO_BG_PRELIMINARY | <2 / exactly 2 backgrounds | cannot size yet; acquire ≥3 distinct HLA backgrounds and re-run. |

**Current state:** exactly ONE processable HLA background here → verdict INSUFFICIENT. The thesis is
validated locally (HAP1) but **cross-HLA generalization is UNPROVEN on public data**. Concretely, the
CRO-sizing decision is **not yet PASS**, so today the conservative default holds: the CRO must be
budgeted to cover ≥3 distinct HLA backgrounds × KO panel + matched proteome — UNLESS the aggregation
lands ≥3 public backgrounds that flip this gate to PASS, which is exactly what the harness is built to
detect the moment they arrive.

---

## 5. Honest caveats (also embedded in the result JSON)

- H4 validated on **ONE** HLA background (HAP1/PXD056426). ≥3 distinct backgrounds with KO + matched
  proteome are required for a real cross-HLA PASS.
- The cross-HLA feature is an **HLA-agnostic machinery-severity prior**, not a trained H4 head — a
  conservative floor. A trained head could beat it or expose HLA-specific processing it misses.
- Fraction-of-WT uses **unique-peptide count** (presentation) vs **summed spectral count** (proteome);
  both are relative-abundance proxies, **not absolute copies/cell**. Absolute quant + MS-detectability
  censoring (BMA-PGM-002 +D: non-detection = censored, never negative) is still owed.
- **Class-I and class-II must not be mixed in a LOO fold** — group by `hla_class` first.
- **Local H4 wins ≠ cross-HLA transfer** (the negative-control self-test shows 4/4 local wins with no
  transfer). Only the leave-HLA-out gate is decision-grade.
- PXD020079 is held as **raw MS only** here; it enters as a second (class-II) background once its
  normalized peptide table is aggregated.
- The permutation null is small-corpus honest: few KOs/backgrounds → wide null → high p → correctly
  hard to pass. Do not weaken the thresholds to force a PASS; acquire more backgrounds instead.
