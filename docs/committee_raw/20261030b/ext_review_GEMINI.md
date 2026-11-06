<!-- model=google/gemini-3.1-pro-preview finish=stop tokens_in=33862 out=3756 reasoning=1790 cost=0.112796 -->
# External reviewer GEMINI (google/gemini-3.1-pro-preview)

## ROLE 1. MANUSCRIPT REFEREE

**What the paper can and cannot claim given the evidence**
The manuscript accurately reflects its incomplete state: it can claim that baseline gradient-boosted models (GBMs) achieve selection yield improvements over random selection in retrospective loops, and that this gain is largely driven by analog lookup and laboratory-specific series interpolation. It can claim that no tested benchmark passes the retrospective validity gates. It *cannot* claim anything regarding the efficacy of language models (IH-LM or pretrained), as Aim A is entirely unrun. It cannot claim that closed-loop feedback improves held-out ranking on new laboratories for plain GBMs, as the source-cluster intervals include zero. 

**Overclaims**
The manuscript is generally cautious, but the inclusion of 54 exploratory knowledge-channel contrasts (K_phys) without multiplicity correction risks over-interpretation. While the text labels these as "exploratory leads," highlighting the 15 out of 54 that exclude zero at 99% without a family-wise error rate correction borders on p-hacking, especially when the yield advantages are explicitly noted as being largely the cost of shuffled noise.

**Internal inconsistencies**
The abstract states that the pre-registered claim "loop beats random in both primary regimes" was not met by the letter of the rule (regime B spread includes 0). However, the discussion (Section 6) states "model-guided selection from a finite library beats random selection in-distribution... under scaffold shift the margin is not established and a label-free physicochemical rule matches it." This is consistent, but the framing of the K_phys results oscillates between "zero-fit association" (offline) and "exploratory leads" (loop), which muddies the takeaway.

**Missing analyses a referee would demand**
1. Multiplicity correction (e.g., Holm-Bonferroni) for the 54 K_phys contrasts.
2. The actual execution of Aim A. A paper proposing a novel hybrid LM cannot be published without evaluating that LM.

**Interval-type and multiplicity issues**
The manuscript uses a confusing mix of intervals: 95% spread, post hoc boot-mean, and cluster-boot over sources. The pre-registered rules relied on the spread (which is not a confidence interval for the mean), leading to post hoc additions of boot-means when the spread failed. This shifting of goalposts, even when transparently documented, weakens the statistical rigor. The 54 uncorrected contrasts are a severe multiplicity issue.

**Framing and publishability**
The current framing (two aims, one paper, but Aim A is unrun) is unpublishable in any standard machine learning or cheminformatics venue (e.g., NeurIPS, ICLR, JCIM) as a standard research paper. It reads like a pre-registration document or a technical report. To be publishable now, it must be completely reframed as a dataset, benchmark, and audit paper (e.g., for the NeurIPS Datasets and Benchmarks track), stripping out the unrun Aim A entirely.

**Ranked list of required revisions**
1. Execute Aim A (the central hypothesis).
2. Apply strict multiplicity corrections to all 54 K_phys contrasts.
3. Standardize the interval reporting (prioritize cluster-bootstrap over sources for all generalization claims).
4. Reframe the manuscript to match the actual evidence (a benchmark audit) if Aim A cannot be run.

## ROLE 2. CODE / STATISTICS REVIEWER

**`aggregate_l7.py`**
*   **Defect:** Line 65: `if den > 0: vals.append(...)`. If a bootstrap draw `draw` happens to select seeds that do not contain the sources in `d[s]`, `den` will be 0, and `vals` will not be appended to for that source. If this happens for all sources in a draw (unlikely but mathematically possible with small seed overlaps), `vals` is empty. Line 66 `np.mean(vals)` will then raise a warning and return `NaN`, which will crash `float()`.
*   **Impact:** Changes interpretation if the script crashes on certain random seeds; indicates fragile resampling logic.

**`validity_gate.py`**
*   **Defect:** Line 28: `fm = d.groupby("family").auc.mean().values`. This averages the AUCs within a family first, then the bootstrap resamples these family means (`fm[idx].mean(1)`). This gives equal weight to each family regardless of the number of targets it contains.
*   **Impact:** Changes interpretation. It is a valid unweighted cluster bootstrap, but it masks target-level variance within large families.

**`05_folds.py`**
*   **Defect:** Lines 12-13: The greedy bin-packing algorithm sorts by `(-weight, family_id)` where weight is the number of distinct compounds. It assigns to the fold with the lowest current compound load.
*   **Impact:** Changes interpretation. This balances compounds but does not guarantee balance for the number of targets or families per fold, potentially leading to highly skewed target distributions across folds.

**`stereo_eval.py`**
*   **Defect:** Line 40: `sp.append(0.0 if len(set(s)) == 1 else float(spearmanr(s, y)[0]))`. Assigning exactly 0.0 to ties is a deterministic imputation for an undefined statistic.
*   **Impact:** Changes reported numbers. If a model predicts a constant value for a group, it gets a 0.0 rather than being dropped, which penalizes models that collapse to the mean but artificially shrinks the variance of the metric.

**`technique_sprint/fusion/fusion.py`**
*   **Defect:** None found in the excerpted logic. The Tanimoto weighting and leave-one-out reliability calculations correctly handle matrix diagonals and minimum mass thresholds.

## ROLE 3. DATA / EVALUATION REVIEWER

**Leakage routes**
The manuscript correctly identifies severe laboratory leakage (52.8% of hits from one lab, Townsend). The in-distribution regime A is heavily confounded by near-duplicates (22.9% identical fingerprints to the initial pool). The reliance on CycPeptMPDB means that any pretrained model (which Aim A intends to use) has likely already ingested the underlying literature, making true zero-shot evaluation nearly impossible.

**Validity gates and the control-adjusted rule**
The finding that *no benchmark passes the validity gate* (Analysis I fails the fingerprint control at 0.584) is devastating. It means the target labels can be predicted better than chance using only the compound's chemotype, without any target information. The control-adjusted rule is a necessary band-aid, but it highlights that the dataset is fundamentally flawed for target-specific binding tasks.

**Family-disjoint folds**
The Pfam-Jaccard family splitting is a good attempt, but with only 26 families in Analysis I and an ICC of 0.23, the effective sample size is ~39 targets. The statistical power is too low (MDE 0.11 AUROC) to detect meaningful improvements, rendering the null results weak.

**Regime definitions and power**
Regime L (leave-laboratories-out) is the only regime that tests true generalization, but the set sizes are highly variable (6 to 18 labs held out per seed). The cluster-bootstrap over sources correctly identifies that plain GBMs do not improve held-out ranking, but the power is limited by the small number of eligible labs (11).

**Public CycPeptMPDB-style data support**
The data cannot support the claims intended for Aim A. The anchor test explicitly failed because only 57 rows have shared anchors, proving that retrospective public data without prospective, standardized anchor panels cannot support laboratory-offset calibration. The dataset is a collection of isolated, laboratory-specific analog series.

## THE SINGLE MOST DAMAGING FLAW

**The Flaw:** The primary benchmark (Analysis I) fails the no-target validity gate (fingerprint control AUROC 0.584), meaning the dataset contains residual chemotype separability that allows models to guess the label without knowing the target.

**Why it is the most damaging:** If a model can predict binding better than chance using only the 2D structure of the peptide without any information about the protein target, the benchmark is not measuring target-specific binding affinity; it is measuring dataset bias and laboratory-specific assay artifacts. Any subsequent comparison of advanced language models on this benchmark will be hopelessly confounded by this bias.

**The cheapest test:** Within one day, randomly permute the target labels across the families in Analysis I and re-run the fingerprint logistic regression control 100 times. If the AUROC remains near 0.584, the bias is a structural artifact of the negative sampling. If it drops to 0.500, the 0.584 is a true signal of chemotype bias in the real labels, confirming the benchmark is invalid for target-aware learning.
