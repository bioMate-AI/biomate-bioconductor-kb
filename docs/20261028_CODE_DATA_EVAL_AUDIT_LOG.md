# Code / data / evaluation audit log (started 2026-10-28)
Rule (owner, 2026-10-28): nothing is reported until code, data, evaluation design and output analysis are audited; if a method that should work does not, suspect our own code first. Each entry: what was checked, how, result.

## A1. Retrospective permeability loop (run_loop*.py, CycPeptMPDB) — in progress
| check | method | result |
|---|---|---|
| Duplicate structures merged? | canonical SMILES uniqueness after loader filters | OK: 7,027 rows → 6,960 IDs → 6,958 unique canonical SMILES |
| Label column | `Permeability` vs `PAMPA` on PAMPA rows | 73 of 7,027 rows (1 %) differ; loader uses `Permeability` (generic) — to fix in next version |
| Regime B (scaffold-shifted) leakage | pool vs initial: identical fingerprint / flat structure / stereo-free scaffold, 10 seeds | **0.000 / 0.000 / 0.000 — no leakage; regime B valid** |
| Regime A (in-distribution) near-duplicates | same, 10 seeds | 22.9 % of pool has a fingerprint identical to an initial peptide; 21.7 % same flat structure; 60.7 % same stereo-free scaffold — by design "in-distribution" but inflates the gain; must be stated |
| **Representation** | distinct fingerprints / flat structures | **6,960 peptides = 2,380 distinct Morgan fingerprints, 2,460 flat structures**: ~⅔ of the data are stereoisomers; fingerprint uses no chirality, so the model cannot see stereochemistry. Design flaw for cyclic peptides; fix in next version (chirality-aware features) |
Consequence: L3 loop-vs-random stands as measured with the two caveats above; knowledge-arm result is uninterpretable twice over (scale mismatch → L4; chirality-blind features → next version).

## To audit next (not yet done)
Stage B inputs (independent DockQ recomputation, sample↔native pairing, feature extraction); leakage audit of the display selector; selector evaluation (abundance null); integrin T1/T2; v4 unified LLM training/eval code; cyclic LLM paper draft numbers vs artifacts.
