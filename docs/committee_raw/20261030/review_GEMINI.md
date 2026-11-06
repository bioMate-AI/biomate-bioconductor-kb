<!-- model=google/gemini-3.1-pro-preview finish=stop tokens_in=21669 out=3939 reasoning=1824 cost=0.090606 -->
# Reviewer GEMINI (google/gemini-3.1-pro-preview)

## PART A. NOVELTY

**(a) In-house hybrid loop-native cyclic-peptide LM with modules M1-M5**
*   **Closest real prior art:** PeptideCLM and PeptideCLM-2 for cyclic peptide LMs; LLMNN (EMNLP 2025) [UNVERIFIED] and MolRAG for retrieval/knowledge-augmented generation; standard Bayesian shrinkage for evidence weighting.
*   **What is genuinely new:** The specific integration of explicit anchor-based lab offsets (M2) and edit-space heads (M4) with a dual-memory loop interface (M5) tailored for cyclic peptides.
*   **What must NOT be claimed:** Do not claim novelty for atom-level SMILES tokenization, basic retrieval-augmented generation, or Bayesian shrinkage. 
*   **How to make it more novel/innovative:** Prove that the M4 edit-space head can accurately predict the direction of activity changes (e.g., D-flips or N-methylation) on completely unseen scaffolds in a prospective wet-lab setting, rather than just retrospectively fitting known lab biases.

**(b) Family-disjoint matched-decoy cyclic-peptide benchmark with typicality/no-target validity gates**
*   **Closest real prior art:** DUD-E, LIT-PCBA, and CleanSplit for matched-decoy and family-disjoint benchmarking in small molecules.
*   **What is genuinely new:** The strict application of typicality and no-target validity gates specifically to expose compound-only shortcuts in cyclic peptide binders.
*   **What must NOT be claimed:** Being the first to use matched decoys, family-disjoint splits, or typicality filters in ML benchmarking.
*   **How to make it more novel/innovative:** Solve the M3 typicality failure. Currently, the benchmark is invalid because the typicality control exceeds chance (0.665). A benchmark that successfully balances these gates while retaining enough data to be powered would be a major contribution.

**(c) Stereo-resolved within-scaffold ranking protocol**
*   **Closest real prior art:** Rezai 2006 and White 2011 for experimental diastereomer/N-Me series; Amirahmadi et al. for ML models treating stereo as distinct monomers (with stereo ablation as future work).
*   **What is genuinely new:** The specific, corrected leave-one-out metric for within-flat-group ranking in ML, avoiding the artifactual -0.386 Spearman score found in naive implementations.
*   **What must NOT be claimed:** Discovering that stereochemistry or N-methylation matters for permeability.
*   **How to make it more novel/innovative:** Extend the protocol to evaluate 3D conformer ensemble generation rather than just 2D/SMILES ranking, as cyclic peptide permeability is heavily driven by chameleonic 3D behavior.

**(d) In-house hybrid vs larger pretrained peptide LMs compared inside a feedback loop**
*   **Closest real prior art:** LLM-agent BO (Gupta et al.) [UNVERIFIED]; Jablonka 2024 for LLM sample efficiency on small chemistry sets.
*   **What is genuinely new:** The head-to-head ablation of a small hybrid model versus large pretrained LMs *specifically inside an active learning loop* for cyclic peptides, controlling for revealed labels.
*   **What must NOT be claimed:** General superiority of small models over large models outside this highly specific, analog-heavy task.
*   **How to make it more novel/innovative:** Include a rigorous cost-benefit analysis (GPU hours, USD, latency) showing the exact crossover point where large models waste compute without yielding better acquisition decisions.

## PART B. EVALUATION

*   **Leakage routes:** Regime A (in-distribution) contains massive leakage by design: 22.9% of the pool has a fingerprint identical to an initial peptide. The L3 baseline used a chirality-blind fingerprint, meaning the model could not even see the differences between stereoisomers.
*   **Validity gates and the control-adjusted rule:** The M2 and M benchmarks failed the validity gates (typicality control 0.665 and 0.476 respectively). M3 is explicitly stated as "not achievable." Therefore, any zero-shot claims are currently invalid.
*   **Family-disjoint folds & leave-labs-out:** Cross-lab generalization is the true failure point (Spearman drops from ~0.67 to ~0.30 leave-labs-out). The anchor-based lab offset (M2) is a patch, not a demonstration of fundamental physical learning.
*   **H4b few-label design:** The nearest-neighbor (NN) baseline dominates (AUROC 0.869 at k=25). The gain is almost entirely analog lookup within a target's chemical series, not target-biology learning.
*   **Statistics:** The initial within-group Spearman for flat features was artificially -0.386 due to a leave-one-out artifact. This was caught, but highlights the fragility of the evaluation pipelines.
*   **Retrospective-only limits:** The entire study is retrospective. It cannot prove the model generates better *novel* molecules, only that it can rank existing ones.
*   **Missing controls:** A chirality-aware GBM baseline is absolutely mandatory for all stereo claims. The current L3 results using chirality-blind fingerprints are uninterpretable.
*   **What a skeptical reviewer would reject:** Any claim of "zero-shot family-held-out" transfer, because the benchmark fails the typicality gate. They will also reject claims that the LLM "learns biology" when the H4b results clearly show it is just doing analog lookup.

**Ranked issues with concrete fixes:**
1.  **Issue:** The M3 benchmark is invalid/unachievable, killing zero-shot claims. **Fix:** Explicitly abandon zero-shot claims in the manuscript. Restrict claims to the few-shot (H4b) setting and apply the control-adjusted rule strictly.
2.  **Issue:** Missing fair baselines for stereo claims. **Fix:** Rerun all L3 and baseline evaluations using `useChirality=True` Morgan fingerprints. Do not report the blind baseline as the primary comparator.
3.  **Issue:** Regime A leakage inflates perceived loop performance. **Fix:** Disaggregate the L5 loop results to show performance on near-duplicates vs. true scaffold hops.
4.  **Issue:** The KB is incredibly thin (only 2 distinct pharmacophore statements for 16 targets). **Fix:** Do not claim "knowledge-prior fusion" as a major driver of performance until the KB is populated with enough diverse rules to actually test M1.

## PART C. RED TEAM

*   **What will go wrong:** The "neural memory" will simply memorize the analog series, and the "symbolic memory" will overfit to the 73 statements in the thin KB. The M2 lab-offset module will absorb all the variance, masking the fact that the underlying LLM backbone is learning nothing about physics.
*   **Simpler explanations of our results:** 
    *   *Analog lookup:* The model is just doing nearest-neighbor matching to revealed compounds (as proven by the H4b NN baseline hitting 0.869 AUROC).
    *   *Lab effects:* The model is just learning that Townsend's lab reports higher baseline permeability than Kelly's lab.
    *   *Typicality:* The model is just rejecting molecules that are too large or have too many rings, which correlates with inactivity.
*   **What we are overclaiming:** We are overclaiming that the LLM learns "target biology" or "physics." It is learning dataset biases, lab offsets, and 2D analog similarity.
*   **Results that will not replicate:** Cross-lab generalization without the M2 anchor compounds will fail miserably in a prospective setting. The edit-space head (M4) will likely fail to predict the direction of D-flips on novel scaffolds, as the baseline analysis shows D-flips have a standard deviation of 0.52 (no consistent direction).
*   **The cheapest decisive experiment that could falsify our central claim:** Run the H4b few-label task using *only* a chirality-aware Morgan fingerprint k-NN combined with the M2 lab-offset term (no LLM backbone, no M1, no M4). If this simple baseline matches or exceeds the IH-LM's performance, the central claim that the "loop improves the LLM" is falsified, because the LLM is dead weight.

## PART D. THREE HIGHEST-VALUE CHANGES FOR THE NEXT WEEK

1.  **Implement and run the chirality-aware GBM baseline across all tasks.** The current reliance on a chirality-blind baseline for cyclic peptides (where 71% of data are in stereoisomer groups) makes the current baseline comparisons fundamentally flawed. This is required before any stereo-resolution claims (H2) can be evaluated.
2.  **Execute the "cheapest decisive experiment" (k-NN + M2 Lab Offset).** Before spending compute on fine-tuning large LMs or training the full IH-LM, prove that the LLM backbone actually adds value over a simple analog-lookup + lab-bias statistical model. 
3.  **Rewrite the claims to explicitly center on Analog Lookup and Lab Offsets.** Stop fighting the baselines. Acknowledge that analog lookup and lab offsets dominate the variance. Reframe the paper to show how the IH-LM *optimizes* analog lookup (via M3) and *corrects* lab offsets (via M2) better than standard LMs, rather than pretending it is doing zero-shot physics. Abandon the zero-shot benchmark claims entirely.
