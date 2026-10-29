<!-- model=google/gemini-3.1-pro-preview finish=stop tokens_in=37951 out=3067 reasoning=1217 cost=0.112706 -->
# External reviewer GEMINI (google/gemini-3.1-pro-preview)

## ROLE 1. MANUSCRIPT REFEREE

**What the paper can and cannot claim given the evidence:**
The manuscript currently reads as an extensive audit and methods paper rather than a complete research article, primarily because the central hypothesis (Aim A: IH-LM vs. external pretrained models) has not been run. The paper can claim that retrospective cyclic-peptide benchmarks are heavily confounded by laboratory concentration, near-duplicates, and censoring, and that simple analog lookup performs as well as learned models in few-label settings. It cannot claim that the closed-loop system provides a generalizable advantage over random selection or one-shot learning, as the in-distribution gain (P1) is explicitly acknowledged to be inflated by transductive leakage, and the scaffold-shifted gain (P2) failed its pre-registered criterion. 

**Overclaims and internal inconsistencies:**
- **Transductive Leakage in P1:** Claiming "+186.3 hits" while admitting in the same sentence that a causal check drops this to 151 (and random to 47) makes the headline number an overclaim. The transductive normalization uses all labels from a source to standardize and threshold, leaking future/unrevealed information into the selection process.
- **K_phys Exploratory Leads:** Highlighting that 15 of 54 dependent contrasts exclude 0 at 99% without multiplicity correction is statistical noise mining. 

**Missing analyses a referee would demand:**
- The causal normalization arm (currently running) must replace the transductive results entirely.
- Aim A must be completed. A paper introducing an evaluation instrument and a "loop-native" model without evaluating the model against the intended baselines is incomplete.

**Interval-type and multiplicity issues:**
The mixing of seed-based intervals (spread, boot-mean) and cluster-based intervals is confusing and risks misinterpretation. Seed-based intervals on a fixed library do not establish generalization. The 54 uncorrected K_phys contrasts are a severe multiplicity issue.

**Publishability and framing:**
The framing of Aim B (the audit and evaluation instrument) is honest and rigorous. However, without Aim A, the paper is a "negative results and dataset audit" paper. It is publishable in venues like *NeurIPS Datasets and Benchmarks Track* or *Journal of Cheminformatics*, but not as a premier machine learning or chemistry discovery paper until the IH-LM is actually tested.

**Ranked list of required revisions:**
1. Complete Aim A (IH-LM vs. external models).
2. Replace all transductive loop results with the causal normalization results.
3. Apply rigorous multiplicity corrections (e.g., Holm) to all K_phys and exploratory contrasts, or remove them.
4. Standardize interval reporting to prioritize cluster-bootstrap over sources/families, as seed-based intervals are misleading for generalization claims.

## ROLE 2. CODE / STATISTICS REVIEWER

**`aggregate_l7.py : learner_key`**
- **Defect:** Relying on directory names (`"blind" in name`, `"confirm" in name`) to assign learner keys is extremely fragile and prone to silent failures if directory naming conventions change. 
- **Impact:** Changes interpretation if files are misclassified, though currently patched.

**`aggregate_l7.py : cluster_contrast`**
- **Defect:** `np.random.default_rng(_seed(per_src, lo, hi))` derives the random seed from the data itself (`per_src`). This is highly unorthodox and potentially breaks the statistical properties of the bootstrap by coupling the RNG state to the sample values. 
- **Impact:** Changes reported numbers (confidence intervals).

**`validity_gate.py : _family_ci`**
- **Defect:** `fm = d.groupby("family").auc.mean().values`. Averaging AUCs across targets within a family before bootstrapping treats all targets equally regardless of the number of items or variance within the target. 
- **Impact:** Changes reported numbers (family-cluster CIs).

**`acq.py : causal_z`**
- **Defect:** `var = (n * vs + k * v_g) / (n + k)`. Shrinking the variance directly via a weighted average of variances is mathematically incorrect. Variance shrinkage should operate on the sums of squares, accounting for the shift in the mean (`mu`). 
- **Impact:** Changes reported numbers (causal standardized scores).

**`acq.py : run_arm`**
- **Defect:** `w = N0 / (N0 + len(labeled))`. The fusion weight decays deterministically based on the number of labeled items, regardless of the actual variance or reliability of the learned model.
- **Impact:** Interpretation only; this is a heuristic choice, not a statistical error, but limits the fusion technique's effectiveness.

**`make_ud.py`**
- **Defect:** `$(nproc --all)` vs `$(nproc)`. The `OMP_NUM_THREADS=1` bug mentioned in Packet 0a was fixed, but relying on shell commands for process counts in Python scripts can still lead to resource overallocation on shared instances.
- **Impact:** None on results, but risky for the RUNNING NOW jobs.

## ROLE 3. DATA / EVALUATION REVIEWER

**Leakage routes:**
- **Transductive Normalization:** The most severe leakage. Using all labels of a source to define the standardization parameters and hit thresholds means the model indirectly "sees" the distribution of unrevealed compounds.
- **Compound Overlap:** Analysis I is Pfam-family-disjoint but not compound-disjoint (11.6% of rows have the same compound in another fold). This allows the model to memorize compound properties across families.

**Validity gates and the control-adjusted rule:**
The finding that censoring dominates (63.6% of inactives are '>' vs 3.1% of positives) completely invalidates Analysis I as a binding benchmark. The model is likely just learning to predict the assay's dynamic range limits rather than physical binding. The validity gates correctly caught the bias, but the benchmark remains fundamentally flawed.

**Regime definitions:**
Regime L (leave-laboratories-out) is highly irregular. Holding out a random subset of 18 smaller labs while the two dominant labs (Townsend and Kelly, 65% of peptides) are never held out means Regime L does not test true out-of-distribution generalization for the majority of the chemical space.

**Power and multiple comparisons:**
Power is severely limited by the small number of families (26 in Analysis I) and sources. The 54 dependent contrasts for K_phys without multiplicity correction are uninterpretable.

**Can public CycPeptMPDB-style data support the claims?**
Barely. The extreme laboratory concentration, lack of shared anchors (only 21 peptides across ≥2 labs), and assay heterogeneity mean that "generalization" on this dataset is mostly just recognizing which laboratory synthesized the peptide.

## CLAIMS I WOULD DELETE

1. **P1: In-distribution the GBM loop beats random selection.** 
   *Reason:* Fatally confounded by transductive normalization leakage; wait for the causal arm.
2. **P2: Physicochemical rule ties the loop under scaffold shift.**
   *Reason:* The loop failed its primary pre-registered claim here; framing it as a "tie" with a rule is spin.
3. **K_phys exploratory leads (15 of 54 contrasts exclude 0).**
   *Reason:* Severe multiplicity mining without correction; statistically invalid.
4. **Any claim regarding the IH-LM.**
   *Reason:* Missing control; the model has not been run.

## THE SINGLE MOST DAMAGING FLAW

**Flaw:** Transductive leakage in the primary loop replay (L5).
**Why it is the most damaging:** The entire premise of a closed-loop active learning simulation is that the model only has access to the labels it has explicitly acquired. By standardizing labels and defining hit thresholds using the *entire* source's label distribution (including unrevealed compounds), the simulation leaks future information, artificially inflating the loop's yield and rendering the primary baseline (P1) invalid.
**Cheapest test:** The causal normalization arm (A2) is already running. Compare the yield of the transductive loop against the causal loop on the exact same seeds. If the yield drops significantly (as the single-seed check suggests: 251 down to 151), the transductive results must be entirely discarded.
