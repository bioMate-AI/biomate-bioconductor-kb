# parse_helm dropped / mis-mapped non-canonical residues (found and fixed 2026-10-27)

Found while building the KN-2 simulated assay (its candidate sequences come from `parse_helm`). `cyclic_llm/knowledge_liability_flags.parse_helm` took the FIRST LETTER of each HELM token after stripping NMe/d- prefixes: `[2Nal]` was DROPPED (first character is a digit), `[Phe4F]` and `[Phe4Cl]` became PROLINE, `[Cit]` became CYSTEINE, `[Orn]` became `O`. The repo's own docs claimed "2Nal→F" for this function; `fto_score._backbone` had a correct length-preserving map (`_BB_MAP`) and was not affected.

Fix (commit d71657b27): explicit parent table (same entries as `fto_score._BB_MAP` plus Orn→K, Cit→R), length-preserving; unknown tokens become `X` and are listed in `scaffold["unmapped"]`. Tests: `cyclic_llm/test_parse_helm_ncaa.py` (4) + the existing gate/KB/availability/experience suites pass.

Impact assessment (what was and was not affected):
* Callers of the buggy function: `knowledge_liability_flags.flag_candidate`, `docking_gate` (sequence join), `make_updated_sequences_v2`, `run_fto_on_kset`.
* 40 distinct earlier candidates containing the mishandled tokens (cofold plan v2, PD-L1 G1, round-4 αvβ6, generated/loop sets): the parsed sequence differed in all 80 (candidate, target) comparisons, but the liability flags and knowledge tiers were IDENTICAL in all 80 (the flagged dipeptides/Met/Trp/charge did not change). No earlier tier decision for these candidates changes.
* The 35 sequences stored in `results/docking/cofold_mmgbsa_plan_v2.json` for candidates with affected tokens all equal the CORRECT mapping (none equal the buggy output), so those co-folding inputs were not corrupted.
* KN-1 (knowledge-novelty frontier) used `fto_score` and `rule_induction` predicates, not `parse_helm`; it is unaffected.
* Not verified: any `docking_gate` / `make_updated_sequences_v2` output that is not stored in the repo.
Lesson recorded: an explicit round-trip length test on every non-canonical token would have caught this at creation; it now exists.
