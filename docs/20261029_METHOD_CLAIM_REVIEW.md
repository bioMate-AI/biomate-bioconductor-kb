# Method claim review — 29 October 2026

Reviewed and edited `20261031_MANUSCRIPT_ALLATOM_METHOD_DRAFT.md` after coordination with the restore-plan stream. Read the method/knowledge takeover records, progress record, integration notes, knowledge prior review and prospective interface. No model execution, statistics, tests or cloud jobs were performed. Existing numerical baseline, component, simulation and historical structure outputs were preserved.

## Changes applied

- Reframed the title and abstract as a **proposed all-atom framework**, with an explicit study-status note. Masked fine-tuning, M1 acceptance, full sampling diagnostics, integrated comparisons and knowledge-on ablations are not described as completed.
- Distinguished the recorded six-step adapter smoke (0.8933 to 0.8075 masked negative log-likelihood) from the unmeasured 200-step study. Corpus counts and exclusion checks remain pending, so the draft no longer claims a completed overlap-free fine-tuning corpus.
- Preserved golden-set mask results, adding that 19 U1 tests passed and one was skipped, the skip reason is unresolved, and staged tested source was not committed before its run. Guided walks (37/150, eight novel strings) are not 5,000 model samples. Finite no-false-prune checks do not prove universal prefix feasibility.
- Qualified K3's numerical outputs as **historical statistics from the uncorrected annotation pipeline**. Explicitly disclosed systematic linker-ring errors, CCD/D-residue discrepancies and N-methylidene ambiguity. Leave-one-target-out stability cannot validate systematically incorrect annotations. Affected priors require reviewed repair/filtering and recomputation of values and hashes before use.
- Replaced residual Discussion/related-work claims of working prose conditioning or established knowledge effects with the actual chemical-prefix interface and prospective evidence-qualified parent/proposal selection. Prototype code is not a validated arm. Preserved the 0 unconditional / 10 provisional / 22 excluded prior-review result.
- Made the constructive knowledge experiment explicit: fixed chemical pool, masks, model, seeds and oracle budgets; knowledge off versus applicable knowledge on; inapplicable-evidence rejection control; evidence-to-proposal trace and fallback reporting. This is a test of whether knowledge helps, not a negative result about knowledge.
- Removed the unsupported claim that most groups of 32 contain fewer than 16 valid members at validity 0.67–0.75. Retained the valid point that nominal group size does not guarantee enough valid members.
- Exposed the earlier 100–200 versus current 64 proposals-per-round discrepancy and the planned one-time LR escalation versus old rank-change prose. Final integration settings still require a frozen prospective amendment.
- Corrected claims of oracle calls wasted on rule failures: the stated charging convention excludes failed proposals, so the cost is proposal/time overhead. Corrected the gate's shortcut-cell description to the actually tested conditions. Removed claims that all study artifacts are already archived.

## Evidence boundaries still open

The manuscript remains a protocol and component-results draft, not a completed method-results submission. Tables 8–12 and Figure 1 are prospective. Track-E terminal success does not fill evaluation-seed cells until completeness and aggregation are checked. A6 evaluation-derived margins, real-model M1 evidence, masked sampling/adapter diagnostics, frozen knowledge eligibility and matched comparisons remain required. The F1 verifier's VOID result is preserved; it does not establish generator failure, and its gate ceiling remains INCONCLUSIVE.

The source/registration chronology, six-step smoke's original artifact linkage, complete software defaults and current prototype contracts still require a final reproducibility manifest. This review did not independently reopen all 47 external references or certify every historical numerical claim. No new result or test pass was invented.

Parent owns the Paper 1 review-package index; its portable links and regeneration instructions were left unchanged after the parent reported updating and committing them.
