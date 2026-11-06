# U1 rule automaton: build notes and measurements (2026-10-29)
Code: `research/guangzhou_all_atom/cyclic_llm/allatom_paper/rules/` (spec, vocab, tracker, constraint, soft, golden, masked_sampling, lora_mask_smoke, prep_train, ec2/). All runs on EC2 spot, none on the laptop. Constraint set C = pilot-3 `satisfies` exactly (spec.py; test asserts equality with gen_pilot).

## What exists (measured)
* ChemFM-1B tokenizer: atom-level, 266 real tokens in a 320-entry vocabulary, eos = 265; the HF tokenizer is greedy longest-match (max 2 characters), so 'Cn1' becomes 'Cn','1'; `vocab.encode` replicates it and the tracker expands merged tokens (`expand2`).
* Hard rules as a logit mask: syntax, ring-closure bookkeeping, sound lower bounds (mass, N-methyl amide count among finalised atoms, token budget); EXACT eos gate (eos allowed only if the complete string satisfies C by RDKit) => every finished sample satisfies C by construction.
* Golden set (2,200+ strings: 900 satisfying, 700 valid-but-violating, 600 invalid): **false-prune 0 of 900 satisfying strings (126,195 prefix positions)**; fast mask == brute-force reference on 40 strings x every 5th position; N-methyl lower bound never exceeds the true count; eos gate exact on all non-invalid strings; 383 of 600 invalid strings are cut by the mask before the end, the rest are never accepted at eos.
* Mask cost: 0.43 ms per step (fast) vs 3.1 ms (reference), c6i.xlarge.
* Soft rules: pluggable `SoftSource` {none (primary), literature_uniform, literature_kb (knowledge_kb_v1.json, weight_eligible AND quote_verified), groupA_descriptive (labelled 'data-descriptive, unvalidated'; 2 sources)}; refuses sources mined from stop/held-out groups. N-Me and D-flip carry no validated weight.

## The key risk, measured: completion under the mask (ChemFM-1B, seeded completion, CPU spot)
| run | n | frac | completed (ended on eos) | of those satisfying C | Y per 1000 (all rows in denominator) |
|---|---|---|---|---|---|
| masked (smoke) | 32 | 0.85 | 8 (25 %) | 100 % | 250 |
| unmasked (same seeds) | 32 | 0.85 | 32 (100 %) | 25 % | 250 |
| masked | 64 | 0.85 | 21 (32.8 %) | 100 % | 328 |
Small n; descriptive only. **67 % of masked rows end in a dead end (mask empty), none at the length cap.** Seed prompts are not the cause (model-free check: 98.7 % of 1,500 prompts at 85 % prefix and 100 % at 50 % have a feasible continuation).
Dead-end dump (39 states, n = 48): all at tracker mass 1384-1397 (just under the 1400 cap) with junk BRACKET atoms, e.g. `[C@HH@5423842`, `[P+@@-2-H-1-3`, `[Si...`. Cause 1 (a bug of mine, fixed): the loose bracket handling let a bracket atom run on with arbitrary `@ H + - digit` tokens and counted its mass only at `]`, so near the cap `]` was forbidden and the 12-token bracket limit ran out. Fix: strict OpenSMILES bracket grammar + the element's mass is charged at the element token. Cause 2 (inherent, to be measured after the fix): when a complete string fails C (typically N-Me < 2) eos is blocked and the model must continue past its natural end, which it never trained to do; this pushes it out of distribution. A stronger look-ahead that gates the macrocycle-closing token on the N-methyl bound is NOT sound for arbitrary SMILES orderings; if used it will be an explicit option with its measured false-prune rate. Fine-tuning under the mask is the principled remedy and is the next measurement.

## LoRA under the mask (CPU smoke only; no GPU spot capacity on 2026-10-29: InsufficientInstanceCapacity for g5/g6/g6e in all four zones)
6 steps, batch 2, 1,701 satisfying library peptides (monomer-library enumeration, NOT CycPeptMPDB; 102 held-out): masked NLL on the held-out strings 0.8933 -> 0.8075 (plain NLL 0.8943 -> 0.8084), loss finite, no NaN; mean log feasible mass about -0.001 (the unconstrained model already puts ~99.9 % of its mass on feasible tokens on satisfying strings, so the mask changes the loss little there; the effect shows at sampling time, not in this teacher-forced loss). 200-step run NOT done (CPU: about 30-40 s per step).
