# Display-binding selector: leakage + trivial-baseline audit (2026-10-27)

Code `research/guangzhou_all_atom/cyclic_llm/selector_leakage_audit.py`; outputs `cyclic_llm/results/leakage_audit_{hPCSK9,Abeta42,hIAPP}.json`. No LM involved.
The 2026-10-06 "within-target win" (`20261006_BINDING_SELECTOR_WITHIN_TARGET_WIN.md`) split a shuffled list of unique sequences 80/20: sequence-disjoint, NOT family-disjoint.

| target | test binders with a train binder within Hamming 1 / 2 | k-mer(1-2) LR AUC, same random split | k-mer LR AUC, Hamming-1-family-disjoint split | LM selector AUC reported |
|---|---|---|---|---|
| Abeta42 | 99.6% / 100% | 0.986 | 0.957 | 0.990 |
| hIAPP | 35% / 56% | 0.698 | 0.521 | 0.689 |
| hPCSK9 | 10% / 15% | 0.841 | 0.653 | 0.357 (solo), 0.815 (unified) |

Reading: a trivial k-mer logistic regression reproduces the LM's AUC on Abeta42 and hIAPP, so the LM adds nothing over a bag-of-k-mers on those splits; Abeta42's number is family memorisation (near-duplicate binders in train). On a family-disjoint split the trivial baseline falls to 0.52-0.96. Added later the same day (spot EC2, standalone script):

| target | unique seqs | test binders within Hamming 1 of a train binder | k-mer AUC random split | k-mer AUC family-disjoint | LM AUC reported |
|---|---|---|---|---|---|
| PADI4 | 370,806 | 22.4% | 0.865 (67 test binders) | 0.864 (68) | 0.968 |
| FIKK13 | 12,914 | 62.5% | 0.924 (only 8 test binders: unreliable) | 0.415 (22; below chance, 47% of binders in one family) | not reported |

PADI4 is the exception: 308 of its 314 binder families are singletons, family leakage is modest, and the k-mer baseline holds up on a family-disjoint split (0.864), so the LM's reported 0.968 may be a real gain of about 0.10 over the trivial baseline. NOT established: the LM was scored on a capped test sample, the baseline on the full 74k test sequences, and ~half of PADI4 "binders" looked like PCR jackpots (label contamination). Needs the LM and the k-mer baseline on the SAME family-disjoint, trajectory-clean split.
NOT yet done: re-running the LM itself on a family-disjoint split. The earlier claim of a selector win over baselines is withdrawn until the LM is evaluated on a family-disjoint split and beats the k-mer baseline there.
