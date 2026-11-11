# IH-LM design-to-implementation audit

29 October 2026. Static source inspection against the original design documents and current call graph. No models, scientific analyses or tests were executed for this audit. No cloud instances were launched. Findings distinguish missing integration from missing validation and from changes in design.

## Conclusion

**The intended architecture is only partially implemented as an executable system.** Substantial IH-LM modules exist, including a pretrained PeptideCLM-backed predictor with analogue cross-attention. The current ChemFM generation entry point does not instantiate those modules. It implements a narrower generative branch. Documentation should neither erase the original architecture to match that branch nor claim the branches are already integrated.

The public pretrained code and weights are implementation choices. The architectural question is whether IH-LM's designed molecular, knowledge, memory, generation and learning interfaces actually connect. At present, several do not.

## Design lineage

- [27 October closed-loop plan](20261027_ALLATOM_CYCLIC_LLM_CLOSED_LOOP_PLAN.md): atom-level SMILES/SELFIES; constraints, knowledge conditioning, verifiable feedback and later uncertainty.
- [P1 plan](20261030_IHLM_PRETRAINING_PLAN_P1.md): a separate in-house pretraining proposal with intrinsic and extrinsic gates; not proof of a completed checkpoint.
- [Hybrid paper design](20261031_ALLATOM_LLM_PAPER_DESIGN.md), especially sections 2A, 3 and 7: pretrained generator plus peptide adaptation, known-series context, rule compilation, feedback and novelty protection. It later rules out new scratch pretraining for this branch.
- [Implementation plan](20261031_ALLATOM_IMPLEMENTATION_PLAN.md): frozen interfaces and staged acceptance criteria.
- [Later integration note](20261029_REAL_HYBRID_INTEGRATION.md) and [knowledge interface](20261029_KNOWLEDGE_METHOD_INTERFACE.md): explicitly narrower prospective integration choices. They require verification and a configuration freeze; they do not establish completion.

Dates in filenames are not an execution chronology. Original plans, later amendments, source implementation and measured results must be read separately.

## Architecture inventory

| Designed element | What exists | Status in current generative run |
|---|---|---|
| Atom-resolved molecular representation | SMILES atoms, bonds, stereochemistry and ring closures | Implemented; original plans do not specify 3D coordinate generation |
| IH-LM M1–M5 | Numerical prior fusion, assay offsets, analogue cross-attention, edit effects, fast/slow memory and uncertainty | Predictor implementation exists; not imported by the ChemFM runner |
| Pretrained peptide encoder | Strict PeptideCLM loader and new zero-initialised analogue cross-attention in `PClmIHLM` | Connected to predictor; not active in generator retrieval/attention |
| Pretrained causal molecular generator | ChemFM loaded with Q/V LoRA | Connected in source; full real-model acceptance unverified |
| Peptide-domain masked adaptation | Standalone PEFT trainer and short component result | Checkpoint not handed to integrated generator; configurations differ |
| Known-series chemical memory | Provenance-aware store/index and optional embeddings | Runner starts empty and only adds its scored generations |
| Scoped mined knowledge | Hash/quote/scope checks and approved-parent selector | Connected prototype; no qualified real catalogue found |
| Knowledge-conditioned neural fusion | Original predictor analogue memory; separate scoped selector | No evidence tensor or analogue-label cross-attention enters current ChemFM |
| Rule-constrained generation | Prefix checks, exact terminal predicate, masked sampling/likelihood | Connected; narrower than full chemical-completion feasibility |
| Preference learning | Shared-prefix score-ranked pairs and DPO | Connected in source; zero-pair control gap and real-model acceptance outstanding |
| Stop/final evaluation separation | Distinct verifier roles, held-out evaluation after search | Connected; endpoint/margin mismatch remains in original protocol |

## Highest-priority findings

### P1 — preparatory adaptation is dropped at the training-stage boundary

`hybrid/model.py:29–36` loads the original base and fresh rank-eight Q/V LoRA. `rules/lora_mask_smoke.py:51,72` trains and saves a separate Q/K/V/O PEFT adapter. There is no preparatory-adapter argument or compatible transfer path in `hybrid/run_stage1.py:35–48,100`. `load_lora` is a hybrid-run resume function, not a standalone adaptation loader. Therefore the current entry point cannot test the intended adapted-initialisation-to-preference pipeline.

### P1 — original learned IH-LM modules are not connected to generation

`ihlm/model.py:79–105,160–221,228–273` implements the predictor's knowledge/memory/edit mechanisms. `ihlm_backbone/adapter.py:15–54` integrates a pretrained peptide encoder with new analogue cross-attention. `allatom_paper/hybrid/run_stage1.py:91–140` instead constructs a ChemFM generator, fingerprint retriever and DPO updater. These are distinct call graphs. Their scientific results and architectural descriptions cannot be pooled as one trained model.

### P1 — the planned known-series context never reaches the generator

`hybrid/adapters.py:8–16` constructs an empty store; `run_stage1.py:131` does not load a reviewed known-series corpus. `orchestrator/loop.py:257–259` adds only generated scored molecules. `hybrid/model.py:61–69` discards retrieved score dictionaries, chooses one parent and retains part of its SMILES. The planned neighbour structures plus measured values and encoder memory are absent from the active conditioning path.

### P1 — real mined knowledge has no complete runtime path

No reviewed real `conditional_parent_v1` catalogue or approved parent map was found in the inspected repository. Additionally:

- `run_stage1.py:114–116` restricts allowed evidence families to CycPeptMPDB group-A source identifiers, rejecting genuinely external literature families.
- `knowledge_parent.py:162–167` disables evidence selection for the entire pool when any generated parent lacks metadata. This logged fallback can turn later knowledge-on rounds into ordinary parent selection.
- That fallback precedes `selector.select` and bypasses its exclusion checks for mapped members of a mixed pool. This is a static code-path defect, not evidence that an executed run leaked data.

The implementation must preserve unknown-scope rejection while validating all available provenance before fallback and defining how eligible known parents coexist with online molecules.

### P1 — no-learning rounds bypass the intended stall control

`orchestrator/loop.py:253–256` calls the updater only if preference pairs exist. `hybrid/adapters.py:51–61` advances the diagnostic gate only after an optimiser step. Repeated rounds with insufficient scored candidates or no valid pairs never reach the promised search-round stall check. Returned loss, small-group/retained-group diagnostics and gate actions are also not fully persisted in the round log.

### P1 — intended attribution and success criteria cannot yet be executed

The entry point supports hybrid, no-rules and no-feedback, but not no-retrieval/no-monitor or adaptation-specific arms. It lacks the planned novelty/memorisation assessment against adaptation and retrieval corpora. The original claim uses held-out AUC, whereas `run_stage1.py:143–147` computes only a final held-out mean. The training-AUC margin does not define a margin for that final mean. This is a protocol inconsistency requiring a prospective resolution, not permission to change outcomes after analysis.

## Additional component risks

The original predictor has static risks involving calibration labels entering shared memory, vocabulary expansion without embedding resize, candidate-batch-dependent score fusion, incomplete module switches and CIP R/S labels being used as D/L labels. These matter if those modules are reconnected; they are not evidence that the ChemFM branch currently exercises them. Details are in the original-architecture audit.

Optional structure potentials have source code, but no active validated structure prior is established. Target exclusions are supported by the utility and are not passed by the main runner. Literature `mined_from` metadata is empty in one soft-source path, so that intersection guard alone is not complete source clearance. Legacy unguarded loaders must not replace the guarded experimental path.

Checkpoint identity/deadline guards and restore diagnostics exist. Real-GPU continuation remains unverified; stop-cache accounting and idempotent final held-out evaluation also need review. A hashed M1 document with boolean flags is not a substitute for enforcing its model/configuration and result bindings.

## What the existing evidence does establish

The inspected remote-validation report records 14 eligibility tests, 19 mining/launcher tests and 50 hybrid/policy/knowledge/orchestrator tests on EC2 Spot. They use synthetic fixtures or small policies, and predate some resume edits. They support component contracts, not completed ChemFM adaptation, a real knowledge catalogue, multi-round knowledge use or scientific improvement. The standalone six-step masked-training smoke is not the required full integration acceptance.

## Repair order and acceptance evidence

1. Preserve the original architecture and identify its main executable composition; define explicit interfaces joining predictor/memory features to the generative subsystem where intended. Do not substitute manuscript edits for that implementation decision.
2. Implement and verify the domain-adaptation checkpoint hand-off, compatible adapters/tokenizer, and declared frozen DPO reference. Show equivalent outputs at transfer before learning.
3. Load the reviewed known-series store and connect the chosen chemical/label conditioning interface; retain split metadata and provide real no-retrieval controls.
4. Qualify a small real evidence catalogue and molecule mapping; fix external-source eligibility and mixed-pool validation/fallback. Demonstrate sustained evidence use across rounds, with forbidden-source and inapplicable controls.
5. Move learning diagnostics and stall decisions to every search round, including no-pair rounds; preserve all diagnostics, resume state and finalisation accounting.
6. Implement the complete attribution matrix and corpus-based novelty checks; prospectively reconcile endpoints, margins and configuration.
7. Run bounded real-model integration tests on approved AWS compute before scientific comparisons. Verify finite nonzero parameter changes, checkpoint transfer/recovery, evidence-to-input trace and unchanged held-out isolation.

No repair or model execution is claimed by this audit.

## Detailed source audits

- [Hybrid training and evaluation](20261029_audit_hybrid_design.md)
- [Original IH-LM M1–M5 and pretrained encoder](20261029_audit_original_ihlm_design.md)
- [Knowledge catalogue, conditioning and eligibility](20261029_audit_knowledge_design.md)

Paths abbreviated above are under `research/guangzhou_all_atom/cyclic_llm/allatom_paper/`, except explicitly named `ihlm/` and `ihlm_backbone/`, which are sibling packages.
