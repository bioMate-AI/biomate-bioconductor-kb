# Do the in-repo knowledge-base rules enrich for measured cyclic-peptide permeability? (exploratory, 2026-10-27)

Code `research/guangzhou_all_atom/cyclic_llm/loop_retro/kb_rule_validation.py`; outputs `loop_retro/results/kb_rule_validation.json`, `kb_nme_within_lab.json`. Data: CycPeptMPDB PAMPA rows, 6,960 peptides, 41 literature sources; hit = top 10 % (base rate 10.2 %). Rules taken from `medchem_kb.py` (physchem canon, modality heuristics, liability domain). NOT pre-registered; descriptive.

| KB rule | peptides passing | hit rate pass / fail | odds ratio (95 % CI, resampling sources) |
|---|---|---|---|
| Lipinski Ro5 (small-molecule rule) | 1.7 % | 29.7 % / 9.9 % | 3.9 (0.04-75) |
| Veber (small-molecule rule) | 7.8 % | 19.5 % / 9.4 % | 2.3 (0.18-62) |
| N-methylated >= 1 (KB cyclic-peptide heuristic, Biron 2008) | 87 % | 11.3 % / 2.8 % | 4.4 (0.32-58) |
| N-methylated >= 2 | 62 % | 15.5 % / 1.7 % | 10.8 (0.38-62) |
| PAINS-free | 100 % | no variation (no peptide flagged) | not informative |
| BRENK-free | 94 % | 10.5 % / 5.3 % | 2.1 (0.47-9.6) |

Within-laboratory check (`kb_nme_within_lab.json`): more N-methyl groups -> higher mean permeability in 7 of 8 laboratories (>= 2 groups, >= 5 peptides per arm) and 6 of 10 (>= 1 group); median within-lab Spearman(N-methyl count, permeability) = 0.10 (11 of 19 labs positive).

Reading. (1) The KB's cyclic-peptide N-methylation heuristic is the strongest rule in the KB and points the right way in most laboratories, but the within-lab effect is modest; the pooled enrichment (and the "one rule recovers 70-83 % of the loop yield" result) is partly between-laboratory (N-methyl-rich series come from papers whose assays read high). (2) The small-molecule rules (Ro5, Veber) are almost never satisfied by cyclic peptides (1.7 %, 7.8 %), so as filters they would discard nearly the whole library. (3) The PAINS domain is inert for this library. (4) Source-resampled intervals are wide for every rule (heterogeneous, small sources).
Implication for the closed loop: KB rules are useful as priors/ordering, not as hard gates, and any evaluation of their value needs assay/source-aware splits and controls.
