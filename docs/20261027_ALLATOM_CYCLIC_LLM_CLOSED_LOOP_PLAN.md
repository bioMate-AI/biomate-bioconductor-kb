# All-atom cyclic-peptide LLM in a closed loop with knowledge, rules and feedback — plan (2026-10-27)

Owner session priority (user, 2026-10-27). Protocol: `research/guangzhou_all_atom/cyclic_llm/allatom/PREREG.md` (committed before any training).

## What exists (verified by reading the repo, not recalled)
* Monomer-level (HELM) model, 387 tokens, conditioned on target/enrichment/permeability; design pipeline `cyclic_llm/design.py`; capstone `docs/20261008_SESSION_CYCLIC_LLM_SYSTEM_CAPSTONE.md`.
* Rule/knowledge assets: acceptance gate, FTO scorer, liability flags, peptide availability, medchem KB, target KB, rule induction + a rule-conditioned ENUMERATOR (its docstring calls itself a stand-in, not a neural generator).
* Data: CycPeptMPDB (8,466 peptides, 7,298 PAMPA labels, 56 sources), `binding_affinity_v1` (136k), display NGS pools, approved cyclic drugs.
## What the evidence from this session constrains
1. Learned loop beats random (+347/+260 hits per 500 picks) but an N-methyl-count rule alone recovers 70-83 % of that yield (`loop_retro/results/rule_baseline.json`).
2. Literature descriptors as INPUT FEATURES did not improve the loop; knowledge must be tested in other roles (constraint, reward, prior).
3. Display-binding LM gains vs a trivial k-mer baseline are not distinguishable from family memorisation on 3 of 5 targets (`docs/20261027_SELECTOR_LEAKAGE_AUDIT.md`), so earlier in-silico claims of the HELM/binding system need re-measurement under family-/source-disjoint splits before they are reused.
4. Pose selection from co-folding samples failed its pre-registered test; structure confidence is not a usable feedback signal for cyclic peptides without new independent signals.
## Design
* Representation: atom level (SELFIES or SMILES with ring-closure tokens), so unseen non-canonical monomers are expressible; pretrain on a large public corpus (never on tiny data), fine-tune on cyclic peptides.
* Knowledge/rules in three roles: hard constraints at decoding, verifiable reward (RL), prior via conditioning; each tested against its own control.
* Feedback: retrospective rounds that reveal measured labels only for selected molecules; v2 replaces them with wet-lab assays.
* Uncertainty/abstention: carried over from the ladder idea; only after the generator beats baselines.
## Gates
G0 corpus + source-disjoint split + leakage filter; G1 validity/ring closure/novelty; G2 hit recovery vs baselines (PREREG claims C1-C3). Kill rule: if the best atom-level system does not beat B_nme and B_helm, no generation claim is made.
## Compute
AWS spot GPU only; checkpoint to S3 every N steps; resumable job; instance-state AND file-count monitoring (two earlier jobs were lost to spot reclaims or silent failures).
