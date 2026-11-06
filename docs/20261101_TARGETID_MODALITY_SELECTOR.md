# Target-ID modality selector (gap T5): design and measured evaluation

Date: 2026-11-01. Code: `backend/lib/galaxy/ai/target_id/modality.py` (+ `modality_test.py`, `modality_gold.py`,
`modality_gold.json`, `modality_eval.py`, `modality_eval_results.json`). All numbers below were printed by a script
from `modality_eval_results.json`.

## What it does
Given a gene symbol, `suggest_modality(symbol)` returns four ranked options (small_molecule, biologic,
macrocycle_peptide, other), the property values used (with the UniProt accession as source), a rationale string, and a
confidence statement. The result is marked `validated: false` and carries a guidance note.

## Anti-circularity
The evaluated selector uses only UniProt annotations that are not drug-precedent: signal peptide, transmembrane
count, extracellular/cytoplasmic topological-domain length, subcellular-location text, EC number, family /
keyword text, chain length. It does not use Open Targets tractability, ChEMBL activity, ligand-bound structures or
any drug text. A separate `precedent_aware_modality` (Open Targets tractability, which partly derives from
precedent) exists, is labelled `uses_drug_precedent: true`, and was NOT scored on the gold set. Its GraphQL query
shape was not verified against the live API in this session.

## Gold set
Source: ChEMBL REST (`mechanism.json`: 7,561 mechanism rows; `molecule.json?molecule_chembl_id__in=...` for the
3,025 molecules whose mechanism rows have max_phase 4; `target.json` for 796 targets), queried 2026-11-01. Molecule
type maps to class: Small molecule -> small_molecule; Antibody, Protein, Enzyme -> biologic; Oligonucleotide,
Oligosaccharide -> other. A target is labelled when it has at least 2 approved drugs and at least 75% are one class.
Counts over the 796 targets: small_molecule 211, biologic 59, other 1, mixed 12 (reported separately, not forced), single-drug
239 (excluded). 36 non-human targets were dropped, leaving 235 scored targets (179 small molecule, 55 biologic,
1 other). Split by sha1(accession) parity: dev (even) used for rule tuning, test (odd) frozen.

## Results (selector top-1 vs gold class)
Headline: held-out test split.

| Method | Accuracy (95% CI) | Macro-recall | SM recall | Biologic recall |
|---|---|---|---|---|
| Selector (test, n=127) | 0.858 (0.787-0.908) | 0.452 | 0.980 | 0.375 |
| Baseline exposed -> biologic else SM | 0.441 (0.358-0.528) | 0.438 | 0.314 | 1.000 |
| Baseline majority class (small_molecule) | 0.803 (0.726-0.863) | 0.333 | 1.000 | 0.000 |
| Selector (all, n=235) | 0.834 (0.781-0.876) | 0.462 | 0.966 | 0.418 |
| Majority baseline (all) | 0.762 (0.703-0.812) | 0.333 | 1.000 | 0.000 |
| Membrane baseline (all) | 0.481 (0.418-0.545) | 0.437 | 0.330 | 0.982 |
| Selector (dev, n=108) | 0.806 (0.721-0.869) | 0.700 | 0.948 | 0.452 |

Test confusion (rows gold, columns predicted small_molecule / biologic): small_molecule 100 / 2; biologic 15 / 9;
the single "other" target predicted biologic. The selector never ranks macrocycle_peptide or other first (no gold
class exists for macrocycles, since ChEMBL types peptides as Protein or Small molecule).
Accuracy by stated confidence (all): high 0.881 (n=160), medium 0.600 (15), low 0.767 (60).
Mixed-modality targets (n=12): selector top was small_molecule for all 12; each of those targets has approved small-molecule drugs.

## Honest reading
- The selector beats the simple "exposed -> biologic" baseline by a wide margin (0.83 vs 0.48 accuracy).
- Against the majority-class baseline the accuracy gain is small and the confidence intervals overlap (test 0.858
  vs 0.803; all 0.834 vs 0.762). The gold is 76% small molecule, so accuracy flatters any small-molecule-leaning rule.
- Biologic recall is weak (0.38 test, 0.42 all): receptors and ectoenzymes with both antibodies and kinase or
  catalytic inhibitors are routed to small molecule. This does not meet the proposed 80% agreement bar on the
  biologic class, and it was only measured on binary SM vs biologic.
- The stated 80% agreement target in the gap register refers to an expert panel; this evaluation is agreement with
  approved-drug precedent, a different and weaker criterion. The panel check has not been done.
- Process disclosure: the first rule set (written a priori) scored all 0.757, test 0.740, dev 0.778 and biologic
  recall 0.65. Three rules (class B GPCR peptide receptors, and heavier weight for catalytic membrane and secreted
  enzymes) were then changed after inspecting DEV errors only. The first-pass aggregate test number had already been
  printed, so the test split is not perfectly blind. These first-pass numbers are not in the saved results file.
- Therefore the output stays `validated: false` (guidance). It is useful for confidently flagging the clear cases
  (accuracy 0.88 when confidence is high) and for giving a transparent rationale, not for deciding a program.

## Limits
Human targets with approved drugs are a precedent-rich subset; novel targets may behave differently. Peptide /
macrocycle suggestions are exploratory and unmeasured. Protein-level annotations only: no structure, no
interface or pocket analysis. ChEMBL returned intermittent HTTP 500 on large pages; the builder batches by id and retries.

## Public API (for wiring; not wired)
`modality.suggest_modality(symbol, http_get=None, cache_dir=None)`, `modality.select_modality(props)`,
`modality.fetch_uniprot_features(accessions, http_get=None, cache_dir=None)`,
`modality.fetch_features_for_symbol(symbol, ...)`, `modality.baseline_membrane_rule(props)`,
`modality.precedent_aware_modality(symbol, http_post=None)` (labelled, unevaluated).
Tests: `PYTHONPATH=lib python -m galaxy.ai.target_id.modality_test`. Rebuild: `modality_gold`, then `modality_eval`.
