# Reviewer B_methodology -- google/gemini-4-argon
_(elapsed 138s; usage {'prompt_tokens': 33707, 'completion_tokens': 9529, 'total_tokens': 43236, 'cost': 0.162704, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 0, 'cache_write_tokens': 0, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 0.162704, 'upstream_inference_prompt_cost': 0.067414, 'upstream_inference_completions_cost': 0.09529}, 'completion_tokens_details': {'reasoning_tokens': 0, 'image_tokens': 0, 'audio_tokens': 0}})_

## 1. VERDICT ON OUR FINDINGS

### Diagnosis of the Cross-Context Generalisation Wall
The consistent collapse across targets and domains (Section 3.3, 3.4) is **not** primarily a model capacity issue; it is the intersection of four distinct methodological failures:
1. **Label Circularity:** Display-NGS enrichment selector (AUC 0.94–0.99) conditioned the model on `<e_hi>`, which is defined by a threshold on the exact enrichment score being predicted.
2. **Covariate/Shortcut Confounding:** Renal biodistribution ($\rho = 0.27 \rightarrow -0.26$ LOTO) learned target-level charge biases rather than sequence-specific kidney retention.
3. **True Distribution Shift (Epistatic/Structural Non-Stationarity):** Cross-target cyclic binding ($\rho = 0.26$) and SH3 LODO ($\rho = 0.28$) hit a fundamental physical wall: binding ΔG is an epistatic, pocket-dependent relational property. Sequence-only or low-resolution models without atomic-resolution co-structures cannot generalize across pockets with zero sequence homology.
4. **Evaluation Design Flaws:** Even your "gold-standard" anti-circular tests suffer from subtle data leakage and shared inductive biases (detailed below).

---

### Specific Audit of Claims (Brief Sections 2–4 & Reveal Doc)

* **Claim:** "`methodology_close.py` is a genuinely closed reward→update loop with a cluster-disjoint evaluator ($R^2 = 0.23\text{–}0.30$, $\Delta B = +0.098$, $p = 0.031$)." (Brief §2; Reveal §3)
  * **Problem:** **Shared-Inductive-Bias Circularity and Generator Pre-training Leakage.** 
    1. In `methodology_close.py`, both `oracle_A` (reward) and `oracle_B` (evaluator) are `HistGradientBoostingRegressor` models trained on the *exact same 8-feature physchem summary* (`[L, ncaa/L, nm/L, ar/L, po/L, ne/L, dr/L, po-ne]`) plus bag-of-monomers (`build_featurizer`). Even on a cluster-disjoint split, both trees learn the same global linear/monotonic trends (e.g., higher N-methylation and aromaticity = higher permeability). If DPO simply shifts the generator toward emitting more N-methylated or aromatic tokens, `oracle_B` *must* increase, even if all generated sequences are physically non-permeable or synthetically impossible.
    2. The generator (`unified_cyclic_llm_v4.pt`) was pre-trained on all of `CycPeptMPDB` conditioned on `<p_hi>`. Thus, the "held-out" `oracle_B` training peptides were already seen by the generator during pre-training!
    3. `_cluster_disjoint_split` uses greedy leader clustering on *unweighted monomer-set Jaccard similarity* (`thr=0.6`), ignoring sequence length, order, and monomer chemotype similarity (e.g., `[NMeF]` and `[F]` are treated as orthogonal tokens with 0 intersection). Furthermore, single-linkage/greedy leader chaining allows a sequence in Cluster A to have 0.59 Jaccard similarity to a sequence in Cluster B.
  * **Evidence Needed:** Re-run `methodology_close.py` where: (a) `oracle_B` is a completely different model class and featurization (e.g., an all-atom 3D conformer-based predictor or a published SOTA model like CycPeptMP [$R^2 \approx 0.77$] held out by Murcko scaffold), (b) `oracle_B` clusters are removed from the v4 LM pre-training corpus, and (c) you include a **"Simple Heuristic Baseline"** control (e.g., rejection sampling from v4 using just `nm/L + ar/L` as the score) to prove DPO learns more than trivial composition shifts.

* **Claim:** "Availability model transfers across domains: in-sample $\rho = 0.72$, LODO $\rho = 0.40$ (0.23–0.49), shipped as an informational score." (Brief §3.5; Reveal §3; `peptide_availability.py`)
  * **Problem:** **Test-Set Snooping in Coefficient/Threshold Locking & Out-of-Domain Extrapolation.**
    1. In `peptide_availability.py`, the shipped coefficients (`_B0=0.3318, _B_HYDRO=-0.2541...`) and the 25th-percentile threshold (`-0.142`) were fit on **all** PCA1 data. While LODO was run to report $\rho = 0.40$, shipping a linear model whose feature selection (3 features) was tuned on the 7-domain dataset without a strictly locked external test dataset risks hyperparameter/feature-selection overfit.
    2. More importantly, for cyclic ncAA peptides, `_residues_from_helm` strips `NMe` and `d-` prefixes (`re.sub(r'^(NMe|Me|N-methyl-|d|D-)', '', t)`), mapping `[NMeK] -> K` and `[dP] -> P`, and completely ignores unknown ncAAs (`2Nal`, `Phe4F`) in the hydrophobicity average! In reality, N-methylation removes a hydrogen bond donor and drastically increases lipophilicity, and `2Nal` is highly hydrophobic ($FP = 2.8$). Stripping `NMe` and dropping `2Nal` makes a greasy macrocycle look artificially hydrophilic and available.
  * **Evidence Needed:** Replace canonical-parent stripping in `peptide_availability.py` with a Crippen/Wildman-Crippen atom-level $\text{cLogP}$ or topological polar surface area (TPSA) calculation via RDKit on the actual monomer SMILES, or at minimum unify it with the `FP` hydrophobicity dictionary in `score.py` so `2Nal` and `Phe4F` are not silently dropped from `mean_h`.

* **Claim:** "Rule-constrained DPO arm (`--kb-gate`) is identical to unconstrained (+0.2513)." (Reveal §3)
  * **Problem:** **Silent Gate Bypass in Code.** Look at `methodology_close.py:259`: `gate_target = args.target if (args.kb_gate and args.signal == "binding") else None`. When `--signal permeability` is run, `gate_target` is passed as `None` to `kb_admissible(m, gate_target)`. Inside `kb_admissible`, it constructs a malformed pseudo-HELM string (`PEPTIDE1{A.R.[dP]}...`) and passes it to `score_mod.developability(helm)`. However, `score_mod.developability` calls `raw_tokens(helm)`, which expects `cyclo(A-R-[dP])` format! When `raw_tokens` fails or parses improperly, the `try...except Exception:` block in `kb_admissible` (`methodology_close.py:139`) catches the error and **fails OPEN** (`reasons["developability"] = True`). The gate never fired!
  * **Evidence Needed:** Fix `to_helm()` in `methodology_close.py` to emit `cyclo(...)` with `-` separators, remove the silent `except Exception: True` fallback, and log the exact rejection count.

* **Claim:** "A1 cyclic nonapeptides (4 points) and A2 cyclic pentapeptides (SDM17 N-methyl scan, ~6 points) + selectivity ratios provide a gold-standard $\alpha\text{v}\beta6$ ground-truth for FEP." (Brief §3.6; Reveal §2)
  * **Problem:** **Underpowered Sample Size & Assay/Chemotype Heterogeneity.**
    1. A1 (Quigley 2023, 9-mer `c[X-RGDL-A-X-dPro-NMeK]`) and A2 (Tomassi 2021, 5-mer `c[RGD-Chg-E]` N-Me scan) are **different ring sizes (9-mer vs 5-mer), different scaffolds (RGDLXXL vs cilengitide-like RGD-Chg), and measured in different labs/assays**. You cannot pool $n=4$ from A1 and $n=6$ from A2 into a single global correlation ($\rho$ or $R^2$) without Simpson's paradox or scaffold-offset domination.
    2. Within A1 ($n=4$: FF, YF, FY, YY), there are only $4! = 24$ possible rank permutations. A perfect Spearman $\rho = 1.0$ has a one-sided exact $p$-value of $1/24 = 0.0417$, and a single swap drops $\rho$ to $0.80$ ($p = 0.167$). Moreover, two of the points (YF = 3.3 nM, FY = 2.8 nM) have a $\Delta\Delta G$ of $0.097\text{ kcal/mol}$, which is inside the experimental ELISA noise floor ($\pm 0.3\text{ kcal/mol}$).
  * **Evidence Needed:** A statistical protocol that treats A1 and A2 as stratified pertubation graphs and accounts for assay noise (see Section 2).

---

## 2. YOUR PROPOSAL FOR YOUR MANDATE AREA

### A. Fixing the Codebase: Leakage-Free Splits, Honest Baselines, and Bug Fixes

1. **Fix `methodology_close.py` (`to_helm`, `kb_admissible`, `_cluster_disjoint_split`, `train_oracles`):**
   * **Bug Fix (`to_helm` & `kb_admissible`, lines 126–148):** Change `to_helm(monos)` to return `"cyclo(" + "-".join(m if (len(m)==1 and m in CANON) else f"[{m}]" for m in monos) + ")"`. Remove the bare `except Exception: reasons["developability"] = True` so gate failures are never silently passed.
   * **Leakage-Safe Clustering (`_cluster_disjoint_split`, lines 85–107):** Replace unweighted set Jaccard with **2D Morgan Fingerprint Tanimoto** (radius 2, 2048 bits via RDKit on the peptide SMILES from `CycPeptMPDB_Peptide_All.csv`) + **Single-Linkage Connected Components** at threshold $T = 0.5$. If two peptides have Tanimoto $\ge 0.5$, they *must* be in the same connected component; no cross-split neighbor can exceed 0.5 similarity.
   * **Decouple Evaluator Featurization (`train_oracles`, lines 110–124):** Train `oracle_A` on sequence/monomer composition features, but train `oracle_B` on **RDKit 2D/3D descriptors** (TPSA, cLogP, MolWt, HBD, HBA, LabuteASA, HallKierAlpha) precomputed for the pool.
   * **Add Mandatory Baselines (`main`):** Add two zero-training baselines before claiming DPO works:
     1. *Best-of-$N$ Rejection Sampling* on `oracle_A` (does DPO beat simply filtering $N$ samples from the base model?).
     2. *Physchem Heuristic Filter* (ranking base samples purely by `nm/L - 0.5*(po/L + ne/L)`).

2. **Fix `peptide_availability.py` (`_residues_from_helm`, lines 43–67):**
   * Stop stripping `NMe` and dropping `2Nal`/`Phe4F`. Import the `FP` dictionary from `score.py` (or map Fauchère-Pliška values into the Kyte-Doolittle scale via linear regression: $KD \approx 1.85 \times FP - 0.2$). When an `NMe` prefix is encountered, add an empirical lipophilicity offset ($+0.8$ KD units per N-methylation) and reduce H-bond donor penalty, rather than pretending `[NMeK]` is unmodified Lysine.

3. **Fix `fep_production.py` & `physics_dispatch.py`:**
   * Add a hard programmatic check in `fep_production.py` that reads `validate_mn_coordination.py --mode post` output JSON (`mn_post_gate.json`) from the unrestrained NPT equilibration (`equil_out/complex/npt.gro`). Abort job submission if any Mn has `< 2` protein/ligand oxygens within $2.6\text{ \AA}$.

---

### B. Evaluation Design to Convince a Hostile Statistician

A hostile statistician will reject your current evaluations on three grounds: (1) pseudoreplication across seeds on the same data split, (2) lack of pre-registered noise-aware baselines, and (3) uncalibrated multi-objective rewards. Here is the exact protocol to implement in a new module `cyclic_llm/statistical_audit.py`:

1. **Nested Grouped Cross-Validation with Scaffold-Graph Connected Components:**
   * Never evaluate on a single 50/50 split across 6 RNG seeds (which tests optimizer variance, not sample variance). Use $5 \times 2$ nested grouped cross-validation where groups are connected components of the SMILES Tanimoto graph ($T = 0.4$).
2. **The Three Mandatory Null Controls for Any Generator/Selector:**
   * **Abundance / Length / Charge Null:** Partial Spearman correlation $\rho(\hat{y}, y \mid \text{Length, NetCharge, cLogP, ReadCount})$. A model is only credited with *structural/sequence intelligence* if the partial correlation conditioned on trivial bulk properties is statistically significant ($p < 0.01$).
   * **Target-Swap Permutation Test (for cross-target / LOTO models):** When evaluating on held-out target $T_k$, evaluate the predictions not just against $T_k$'s labels, but against the labels of $T_1 \dots T_{k-1}$. If a model conditioned on $T_k$ predicts $T_j$ just as well as $T_k$, the target conditioning is dead weight (catching the `unified_cyclic_llm_v4` null-target illusion).
   * **Best-of-$N$ Matched-Compute Baseline (for RL/DPO loops):** If DPO uses $M = 1200$ oracle calls to build pairs and evaluates $E = 400$ post-DPO samples (total 1600 oracle calls), the baseline is **not** the mean of 400 base samples; the baseline is the **top 400 out of 1600 base samples** ranked by `oracle_A` (or a simple ridge regression on those 1200 calls).

---

### C. Turning ~10 Measured $\alpha\text{v}\beta6$ SAR Points into a Valid Statistical Test

With only $n_1 = 4$ (A1: Quigley 9-mer FF/YF/FY/YY) and $n_2 \approx 6$ (A2: Tomassi SDM17 5-mer N-methyl scan, where several points are right-censored at $>5000\text{ nM}$), standard Pearson $R^2$ is statistically invalid. Implement `cyclic_llm/avb6_sar_benchmark.py` using the following **Stratified Perturbation-Graph & Censored Concordance Protocol**:

1. **Explicitly Separate A1 and A2 into Stratified Perturbation Graphs (No Naive Pooling):**
   * Convert IC50s to $\Delta G_{\text{exp}} = RT \ln(\text{IC}_{50})$. For censored values ($>5000\text{ nM}$), record them as lower bounds $\Delta G_{\text{exp}} > -7.2\text{ kcal/mol}$.
   * Construct all within-series pairwise edges $(i, j)$ where $|\Delta\Delta G_{\text{exp}}^{(i,j)}| > 0.40\text{ kcal/mol}$ (2$\times$ IC50 ratio, outside experimental ELISA noise).
     * In **A1** (0.17, 0.84, 2.8, 3.3 nM $\rightarrow \Delta G = -13.33, -12.38, -11.67, -11.57\text{ kcal/mol}$): there are $\binom{4}{2} = 6$ pairs, of which **5 pairs** exceed the $0.40\text{ kcal/mol}$ noise floor (excluding YF vs FY, where $\Delta\Delta G = 0.10\text{ kcal/mol}$). Notably, A1 contains a **non-additive double-mutant cycle**: $\Delta\Delta G(\text{YY}\rightarrow\text{YF}) = +0.81$, $\Delta\Delta G(\text{YY}\rightarrow\text{FY}) = +0.71$, yet the double mutant $\Delta\Delta G(\text{YY}\rightarrow\text{FF}) = -0.95\text{ kcal/mol}$ (epistatic coupling $\Delta\Delta\Delta G = -2.47\text{ kcal/mol}$!).
     * In **A2** (SDM17: parent 1.3 nM vs N-Me scan analogs ranging from ~30 nM to $>5000\text{ nM}$): construct the star/perturbation graph of all valid edges exceeding $0.40\text{ kcal/mol}$ (excluding Censored-vs-Censored pairs). This yields ~12–15 directed high-confidence edges.
     * In **Selectivity** (A3: FF $\alpha\text{v}\beta6/\alpha\text{v}\beta3$ ratio $2494\times \Rightarrow \Delta\Delta G_{\text{sel}} = -4.6\text{ kcal/mol}$; A20FMDV2 $\ge 85\times \Rightarrow \le -2.6\text{ kcal/mol}$): 2–3 cross-receptor edges.

2. **Test Statistic: Noise-Excluded Stratified Concordance Index ($c\text{-index}$) + Exact Randomization Test:**
   * Rather than computing a noisy Pearson $r$, compute the **Stratified Harrell's $c$-index** (fraction of valid within-series directed edges $(i,j)$ where $\text{sign}(\Delta\Delta G_{\text{pred}}^{(i,j)}) = \text{sign}(\Delta\Delta G_{\text{exp}}^{(i,j)})$) combined with **Censored Tobit RMSE** (where right-censored binders $>5000\text{ nM}$ incur zero error if $\Delta\Delta G_{\text{pred}} \ge +3.5\text{ kcal/mol}$ relative to parent, and quadratic penalty if predicted to bind tightly).
   * **Exact Permutation $p$-value:** Because $n_1 = 4$ and $n_2 = 6$, there are exactly $4! \times 6! = 24 \times 720 = 17,280$ joint label permutations across the two strata (reduced further by ties among censored $>5000\text{ nM}$ points). Compute the **exact randomization $p$-value** by evaluating the test statistic across all 17,280 strata-preserving permutations!
   * **The Falsifiable Admissibility Gate:** To pass at $\alpha = 0.01$ against a hostile statistician:
     1. The oracle must achieve $\ge 85\%$ directional concordance across the ~20 noise-excluded stratified edges ($p < 0.005$ by exact stratified permutation).
     2. In A1, it must recover the negative sign of the $\text{YY}\rightarrow\text{FF}$ edge ($\Delta\Delta G_{\text{pred}} < -0.4\text{ kcal/mol}$).
     3. In A2, it must classify every N-methylated RGD-core knock-out ($>5000\text{ nM}$) as $\Delta\Delta G_{\text{pred}} > +2.5\text{ kcal/mol}$ (activity cliff recall = 100%).
     4. It must beat a **0-GPU Null Baseline** (e.g., simple pharmacophore H-bond donor count + Crippen $\text{cLogP}$) on the exact same permutation test.

---

## 3. THE ONE INNOVATION YOU WOULD BET ON

### Thermodynamic Cycle-Closure & Epistatic Active Learning via an Edit-Graph LLM (`CycleClosure-RLVR`)

#### Why "LLM + Rules + Computation" Is Not Enough
As you rightly noted with SynCraft (Li & Lai, *Nat. Mach. Intell.* 2026), having an LLM propose edits filtered by RDKit/docking is already published prior art. Furthermore, your own experiments prove that sequence LMs cannot generalize binding across targets, and running single-replica 0.5 ns/window FEP without cycle checks produces junk ($-0.18$ vs $-0.95\text{ kcal/mol}$).

#### The Innovation
Instead of using the LLM to propose individual candidate peptides ($X$) and scoring them with independent point-estimates, **change the fundamental unit of generation and verification from a *node* (a peptide) to a *closed thermodynamic perturbation cycle* (a 3- or 4-node directed graph of single-site edits anchored on a known active).**

1. **What the LLM Is:** An **Edit-Cycle Proposer** (replacing `revise()` in `loop.py`). Given the anchored scaffold `YY` (Trivehexin monomer, $\text{IC}_{50} = 0.84\text{ nM}$) and `FF` (avebehexin, $\text{IC}_{50} = 0.17\text{ nM}$) and the FTO/developability rules, the LLM proposes a **closed 4-cycle of alchemical edits** $A \rightarrow B \rightarrow C \rightarrow D \rightarrow A$ (for example, $A=\text{YY [known]}$, $B=\text{Y-[2Nal] [novel FTO-clear]}$, $C=\text{F-[2Nal] [novel FTO-clear]}$, $D=\text{FF [known]}$).
2. **Physics as a Self-Verifying Oracle (Zero Wet-Lab Ground Truth Required):** By the First Law of Thermodynamics, around any closed cycle, the true free energy sum must vanish:
   $$\oint \Delta\Delta G = \Delta\Delta G_{A\rightarrow B} + \Delta\Delta G_{B\rightarrow C} + \Delta\Delta G_{C\rightarrow D} + \Delta\Delta G_{D\rightarrow A} \equiv 0$$
   And if both $A$ ($\text{YY}$) and $D$ ($\text{FF}$) have known experimental affinities ($\Delta\Delta G^{\text{exp}}_{A\rightarrow D} = -0.95\text{ kcal/mol}$), then any two-step path through a novel candidate $B$ ($A \rightarrow B \rightarrow D$) must sum to the experimental anchor difference:
   $$\Delta\Delta G_{A\rightarrow B}^{\text{FEP}} + \Delta\Delta G_{B\rightarrow D}^{\text{FEP}} = -0.95\text{ kcal/mol}$$
   The residual $|\Delta\Delta G_{A\rightarrow B}^{\text{FEP}} + \Delta\Delta G_{B\rightarrow D}^{\text{FEP}} - (-0.95)|$ is the **Cycle-Closure Hysteresis ($H_{\text{cycle}}$)** — an exact, physical, label-free measure of sampling error and pose breakdown!
3. **Verifiable Reward & Active Learning:**
   * A candidate $B$ is only credited with a verifiable binding reward in `reward.py` if its cycle-closure hysteresis $H_{\text{cycle}} < 0.4\text{ kcal/mol}$.
   * If $H_{\text{cycle}} \ge 0.4\text{ kcal/mol}$, the loop automatically flags the edge for **adaptive sampling** (extending $\lambda$-windows from 0.5 ns to 5 ns HREX) or rejects the edit as a sterically clashed/slow-relaxing mode.
   * For selectivity ($\alpha\text{v}\beta6$ vs $\alpha\text{v}\beta3$), you compute the **Double-Difference Thermodynamic Cycle** $\Delta\Delta\Delta G_{\text{sel}} = \Delta\Delta G_{A\rightarrow B}^{\alpha\text{v}\beta6} - \Delta\Delta G_{A\rightarrow B}^{\alpha\text{v}\beta3}$, canceling the solvent leg entirely!

#### Prior Art & Defensibility
* **Prior Art:** Cycle-closure hysteresis (Wang et al., *J. Am. Chem. Soc.* 2015, Schrödinger FEP+) is established in small-molecule FEP, and SynCraft (Li & Lai 2026) uses LLMs for chemical edit sequences. However, using **experimental multi-anchor bridge cycles ($A_{\text{exp}} \rightarrow B_{\text{novel}} \rightarrow D_{\text{exp}}$) as the RLVR verification gate for an LLM designing macrocyclic peptides across FTO boundaries** is genuinely novel **[UNVERIFIED: no published work combines LLM FTO-edit generation with experimental-bridge alchemical cycle-closure verification]**.
* **What Would Falsify It:** Run the 4-node cycle on the A1 ground truth ($\text{YY} \rightarrow \text{YF} \rightarrow \text{FF} \rightarrow \text{FY} \rightarrow \text{YY}$). If, after the CaDA-Mn metal fix and 5 ns/window HREX, the cycle hysteresis $H_{\text{cycle}} > 1.0\text{ kcal/mol}$ OR the two paths from $\text{YY} \rightarrow \text{FF}$ fail to bracket $-0.95 \pm 0.5\text{ kcal/mol}$, then your all-atom FEP setup cannot sample macrocycle backbone/sidechain reorganizations on AWS spot budgets, falsifying the physics tier of this architecture.

---

## 4. 30-DAY PLAN

Assuming **zero wet-lab data** and modest AWS spot GPU budget (~$3–5/hr for g5.xlarge/g5.2xlarge):

### Week 1: Code Hygiene, Bug Fixes & Statistical Harness (Cost: $0, CPU only)
1. **Day 1–3: Fix Silent Bugs & Leakage in `cyclic_llm/`.**
   * Patch `methodology_close.py` (`to_helm`, remove open-fail `try/except`, replace Jaccard with RDKit Morgan Tanimoto connected-components, decouple `oracle_B` to RDKit 2D descriptors, add Best-of-$N$ baseline).
   * Patch `peptide_availability.py` to score `NMe` and non-canonical aromatics (`2Nal`, `Phe4F`) using Fauchère-Pliška / RDKitWildman-Crippen $\text{cLogP}$ rather than stripping prefixes.
   * **Go/No-Go Gate 1:** `kb_admissible` rejects 100% of non-RGD and patent-infringing $\alpha\text{v}\beta6$ sequences in unit tests; `methodology_close.py` DPO beats Best-of-$N$ rejection sampling at matched oracle calls ($p < 0.05$ across 5 scaffold-disjoint folds). If DPO fails to beat Best-of-$N$, **drop DPO** and use Best-of-$N$ / SMC sampling.
2. **Day 4–7: Build `cyclic_llm/avb6_sar_benchmark.py`.**
   * Digitise all A1 ($n=4$), A2 ($n=6$), and selectivity ($n=3$) data from Quigley 2023 and Tomassi 2021 into `target_kb/avb6_gold_sar.json` with assay metadata and censoring flags.
   * Implement the Stratified $c$-index, Censored Tobit RMSE, and the 17,280-permutation exact randomization test.
   * Evaluate 0-GPU baselines (pharmacophore rule, sequence similarity, FoldX/Rosetta fast-relax if available).
   * **Go/No-Go Gate 2:** Benchmark script runs in $<5\text{ s}$ on CPU and confirms that random/abundance nulls get $p \approx 0.50$.

### Week 2: Metal-Site Validation & The A1 4-Cycle Falsification Test (Cost: ~$40–$80 Spot GPU)
3. **Day 8–10: Run Restrained & Unrestrained CaDA-Mn Validation (`fep_batch.py`).**
   * Run `avb6-fep-ctrl-build2` equilibration with `--mn-restrain` followed by $5\text{ ns}$ unrestrained NPT (`--mn-validate`) starting from BOTH the cofold pose AND a pose grafted onto the experimental cryo-EM/X-ray structures (`8TCG` / `9XMM`).
   * **Go/No-Go Gate 3:** `validate_mn_coordination.py --mode post` passes (all 3 Mn keep $\ge 2$ protein/ligand O within $2.6\text{ \AA}$ for $5\text{ ns}$ unrestrained, RMSD of MIDAS Asp $< 1.5\text{ \AA}$). If the cofold pose fails unrestrained MD, discard cofold poses and strictly template on `9XMM`/`8TCG`.
4. **Day 11–14: Run the A1 4-Edge Closed Thermodynamic Cycle + Asp→Ala Positive Control.**
   * Enable true GROMACS `-replex` (HREX across $\lambda$ windows, $2\text{ ns}$/window, 3 replicas) in `fep_production.py` and wire the `mn_post_gate.json` hard guard.
   * Run the 4 edges of the A1 cycle ($\text{YY}\rightarrow\text{YF}$, $\text{YF}\rightarrow\text{FF}$, $\text{YY}\rightarrow\text{FY}$, $\text{FY}\rightarrow\text{FF}$) + 1 metal-perturbing edge ($\text{Asp}\rightarrow\text{Ala}$).
   * **Go/No-Go Gate 4:** (a) $\text{Asp}\rightarrow\text{Ala}$ gives $\Delta\Delta G > +3.0\text{ kcal/mol}$; (b) Cycle-closure hysteresis $H_{\text{cycle}} \le 0.5\text{ kcal/mol}$; (c) $\Delta\Delta G(\text{YY}\rightarrow\text{FF})$ is negative and within $[-0.4, -1.6]\text{ kcal/mol}$. *If this fails, halt all FEP spending and pivot to structure-based Rosetta/FlexDDG or physics-prior RFpeptides.*

### Week 3: A2 N-Methyl Cliff Benchmark & Selectivity Cycle (Cost: ~$60–$100 Spot GPU)
5. **Day 15–19: Evaluate A2 (SDM17 N-Me Scan) & $\alpha\text{v}\beta6/\alpha\text{v}\beta3$ Selectivity.**
   * Run the multi-fidelity ladder (Tier 1: `score.py` rules + availability; Tier 2: `9XMM`-templated short MD / MM-PBSA or FlexDDG; Tier 3: HREX-FEP on 4 key SDM17 N-Me edges).
   * Run 1 selectivity double-difference cycle ($\text{YY}\rightarrow\text{FF}$ in $\alpha\text{v}\beta6$ vs $\alpha\text{v}\beta3$ crystal structure `1L5G`).
   * **Go/No-Go Gate 5:** Pass the `avb6_sar_benchmark.py` exact randomization test at $p < 0.01$ ($\ge 85\%$ stratified edge concordance, 100% recall on $>5000\text{ nM}$ N-Me knockouts, and correct sign on $\alpha\text{v}\beta6/\alpha\text{v}\beta3$ selectivity).

### Week 4: Closed-Loop FTO-Bridge Candidate Generation & Pre-Registered Dossier (Cost: ~$50 Spot GPU)
6. **Day 20–25: Wire `CycleClosure-RLVR` in `loop.py` and `reward.py`.**
   * Replace `revise()` in `loop.py` with an LLM/graph proposer that takes `YY` and `FF` and proposes 2-step FTO-clearing bridge paths ($\text{YY} \rightarrow X_{\text{novel}} \rightarrow \text{FF}$) using vetted ncAAs (`2Nal`, `Phe4F`, `Phe4Cl`, `1Nal`, `Cha`, `HomoPhe` at P1/P7; `A`, `G`, `S`, `Abu`, `Nva` at P6).
   * Screen all candidates through Tier 1 (hard gates, FTO outside literal genus, RDKit availability/cLogP) $\rightarrow$ Tier 2 (pose stability in `9XMM` MIDAS pocket) $\rightarrow$ Tier 3 (2-edge bridge FEP $\text{YY}\rightarrow X \rightarrow \text{FF}$ + $\alpha\text{v}\beta3$ counter-target edge).
   * **Go/No-Go Gate 6:** At least 5 novel, FTO-clear candidates satisfy: (a) hard gates = PASS, (b) bridge cycle closure $|\Delta\Delta G_{\text{YY}\rightarrow X} + \Delta\Delta G_{X\rightarrow \text{FF}} - (-0.95)| < 0.4\text{ kcal/mol}$, (c) $\Delta\Delta G_{\text{YY}\rightarrow X}^{\alpha\text{v}\beta6} < -0.5\text{ kcal/mol}$, and (d) $\Delta\Delta\Delta G_{\text{sel}}(\beta6 - \beta3) \le 0\text{ kcal/mol}$.
7. **Day 26–30: Lock Falsifiable Pre-Registration & Benchmark Release.**
   * Freeze the top 10 $\alpha\text{v}\beta6$ candidates with explicit point predictions and 95% confidence intervals for $\text{IC}_{50}(\alpha\text{v}\beta6)$, $\text{IC}_{50}(\alpha\text{v}\beta3)$, and passive permeability before any CRO synthesis.
   * **Go/No-Go Gate 7:** Zero unverified claims remain in repo docs; every candidate in the CRO order sheet passes `avb6_gate` and `validate_mn_coordination`.

---

## 5. STOP DOING

1. **STOP training or fine-tuning sequence-only LLMs (`neural_generator.py`, `unified_cyclic_llm_v4`) to predict cross-target binding or to re-rank 80 enumerated triples.**
   * *Why:* You have a combinatorially tiny design space ($4 \times 5 \times 4 = 80$ triples in `neural_generator.py`, or ~2,000 if expanded to 15 ncAAs). Enumerating all 2,000 triples on CPU takes $<0.2\text{ seconds}$. Using a 4.8M-parameter nanoGPT trained on circular display-NGS data and conditioned on null-target permeability to sample 800 times with replacement from 80 items is theater, not machine learning.
2. **STOP using display-NGS enrichment (`harvest_display_ngs_multitarget.py`) as a supervised or DPO reward signal without abundance/PCR-bias normalization.**
   * *Why:* Raw display enrichment conflates expression/display efficiency, PCR amplification bias, and non-specific stickiness with affinity. Your own audit proved a trivial read-count sort gets $\text{AUC} \approx 1.0$ while the LM gets $0.343$ on hPCSK9.
3. **STOP running single-replica, independent-window 0.5 ns FEP (`fep_production.py`) and quoting analytic BAR standard errors.**
   * *Why:* Macrocycles have slow backbone and side-chain rotamer barriers ($\tau > 5\text{–}50\text{ ns}$). Independent 0.5 ns windows without replica exchange (`-replex`) never equilibrate across $\lambda$ states, and analytic BAR error within a single trapped replica underestimates true variance by $5\text{–}10\times$.
4. **STOP starting $\alpha\text{v}\beta6$ MD/FEP from clashed cofold poses (0.82 Å Mn–O clash) when high-resolution experimental co-structures (`8TCG`, `4UM9`, `9XMM`) exist.**
   * *Why:* Relaxing a 0.82 Å metal-oxygen overlap with harmonic springs distorts the local coordination sphere and Asp/Glu dihedrals. Threading/grafting the cyclic peptide directly onto the `9XMM` cyclic-RGD crystal/cryo-EM backbone preserves the native MIDAS/ADMIDAS/SyMBS geometry from frame zero.
5. **STOP attempting zero-shot cross-target transfer (GLOO on 847 targets, SH3-to-integrin transfer) to justify your $\alpha\text{v}\beta6$ pipeline.**
   * *Why:* You do not need a universal zero-shot binder model to win on $\alpha\text{v}\beta6$. You have exact crystal structures (`9XMM`, `8TCG`) and congeneric SAR series (Quigley 2023). Solve the **local perturbation problem** rigorously rather than chasing an ill-posed global generalization benchmark.

---

## 6. BIGGEST RISK WE ARE MISSING

### The Three-Metal Identity & Protonation/Valence Trap at the Integrin $\alpha\text{v}\beta6$ Binding Site (MIDAS / ADMIDAS / SyMBS)

In `20261025_CADA_MN_METAL_MODEL_VALIDATION.md`, you discovered that the 3 $\text{Mn}^{2+}$ ions were 35 Å away in bulk water, fixed the coordinate translation, and placed **three identical CaDA-$\text{Mn}^{2+}$ models (`Mn1`, `Mn2`, `Mn3`)** into the pocket. You noted in passing (§6 item 6) that *"MIDAS/ADMIDAS/SyMBS are typically Mn/Mg-Ca/Ca depending on conditions — unverified here."*

**This is not a minor footnote; it is a critical biophysics and assay-alignment hazard that can invalidate your entire FEP rebuild:**

1. **Physiological & ELISA Assay Metal Occupancy Is Heterogeneous ($\text{Mg}^{2+}/\text{Ca}^{2+}$, Not $3\times\text{Mn}^{2+}$):**
   * Integrin $\beta$-I domains contain three coupled divalent cation sites: **SyMBS** (LIMBS), **MIDAS** (which directly coordinates the ligand RGD $\text{Asp}$ carboxylate), and **ADMIDAS**.
   * Under standard physiological and solid-phase ELISA conditions (like Quigley et al. 2023, which typically uses $1\text{ mM }\text{Mg}^{2+} / 1\text{ mM }\text{Ca}^{2+}$ or $\text{Mn}^{2+}$ supplementation **[UNVERIFIED: check exact Quigley 2023 buffer composition]**), SyMBS and ADMIDAS are typically occupied by **$\text{Ca}^{2+}$**, while MIDAS is occupied by **$\text{Mg}^{2+}$** (or $\text{Mn}^{2+}$ only in manganese-activated buffers).
   * Replacing $\text{Ca}^{2+}$ (ionic radius $\sim 1.00\text{ \AA}$, 7–8 coordinate, lower charge density) at ADMIDAS/SyMBS with a small, rigid, octahedral 6-dummy CaDA-$\text{Mn}^{2+}$ cage ($b_0 = 2.05\text{–}2.40\text{ \AA}$) artificially contracts the ADMIDAS loop ($\beta1\text{–}\alpha1$ loop), which allosterically controls the $\alpha\text{v}\beta6$ specificity groove (`SDL` loop) that contacts your P1/P7 aromatic flanks!
2. **Why This Directly Affects Your $\text{YY}\rightarrow\text{FF}$ Control Edge:**
   * You wondered why $\text{Tyr1/7}\rightarrow\text{Phe1/7}$ ($\Delta\Delta G_{\text{exp}} = -0.95\text{ kcal/mol}$) is sensitive to the metal setup even though Tyr1 and Tyr7 do not directly touch the MIDAS metal. In $\alpha\text{v}\beta6$, the P1 and P7 aromatic residues pack against the $\beta6$ specificity-determining loop (SDL) and the ADMIDAS-adjacent residues. If ADMIDAS has the wrong metal ion (or a misfitted dummy cage pulling Asp/Glu oxygens to $2.1\text{ \AA}$ instead of $\text{Ca}^{2+}$'s $2.4\text{ \AA}$), the SDL loop shifts by $1\text{–}2\text{ \AA}$, destroying the hydrophobic/H-bond differential between Tyr and Phe!
3. **Immediate Mitigation:**
   * Check `8TCG`, `4UM9`, and `9XMM` PDB headers and the Quigley 2023 experimental methods section today.
   * Measure the input metal–oxygen bond lengths in `8TCG`/`9XMM` before running `build2`: if `Mn1` or `Mn2` in the crystal structure has $d(\text{M–O}) \approx 2.35\text{–}2.50\text{ \AA}$ and 7-coordination, it is a $\text{Ca}^{2+}$ site, **not** an octahedral $\text{Mn}^{2+}$ site, and forcing a 6-dummy octahedral CaDA-$\text{Mn}^{2+}$ cage onto it will warp the binding pocket during unrestrained MD.