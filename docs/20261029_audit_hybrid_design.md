# Hybrid implementation against original design — 29 October 2026

Read-only source audit; no tests, scientific computation, downloads or model execution were performed. This audit compares the original design and implementation plan, not merely the revised manuscript. Paths below are relative to `research/guangzhou_all_atom/cyclic_llm/allatom_paper/` unless prefixed with `docs/`.

## Conclusion

The current runtime is a partial implementation: pretrained ChemFM with fresh LoRA, constrained prefix continuation, an initially empty online fingerprint store, optional conditional parent selection, continuous-score DPO, a stopping monitor and final held-out scoring. It does not yet execute the originally planned peptide-adapted, known-series-conditioned system. Synthetic contract tests do not close these gaps. The recent integration note explicitly narrows some choices, but requires a prospective freeze and real-model acceptance rather than treating that narrowing as completed science.

## P1 — blockers to testing the intended method

### 1. Masked adaptation does not initialise the integrated generator

Original anchors: `docs/20261031_ALLATOM_LLM_PAPER_DESIGN.md:48`, `:80`, `:86–87`, `:132`; implementation plan U1 at `docs/20261031_ALLATOM_IMPLEMENTATION_PLAN.md:42`.

`hybrid/model.py:29–36` loads base weights and creates fresh rank-eight Q/V adapters. `hybrid/run_stage1.py:35–48` exposes no preparatory-adapter argument; `:100` constructs that fresh generator. The standalone trainer uses Q/K/V/O adapters with independent rank and dropout (`rules/lora_mask_smoke.py:51`), and saves a PEFT adapter directory (`:72`). The integrated restore function instead expects its own dictionary containing optimiser, RNG and configuration fields (`hybrid/model.py:196–207`). Thus the standalone fine-tune output is neither automatically loaded nor format-compatible with the integrated resume path. A successful DPO run through this entry point would not test mask-plus-domain-adaptation as originally planned.

Required repair: freeze compatible adaptation and preference stages, explicitly transfer the adapted checkpoint, verify equivalent forward likelihoods at hand-off and record both identities. Decide whether the DPO reference is the initial pretrained base or the frozen post-adaptation policy: current `hybrid/model.py:167–168` disables adapters, making it the original base. The recent integration note deliberately specifies that base reference; a post-adaptation reference is a new explicit configuration, not a silent correction.

### 2. Planned known-series retrieval is replaced by an empty online store

Original anchors: design `:96`; implementation plan I-B `:40`.

`hybrid/adapters.py:8–16` creates an empty `Retriever`, and `hybrid/run_stage1.py:131` never builds it from the existing known-peptide store. `orchestrator/loop.py:175–181` queries neighbours of the current best generated molecule; `:257–259` adds only the run's scored outputs. `hybrid/model.py:61` discards retrieved value dictionaries and retains only SMILES; `:65–69` conditions on part of a single parent. No k-series-with-values or target pharmacophore context reaches the generator. This is a meaningful molecular-prefix mechanism, but a narrower intervention than the original design.

Required repair: connect a reviewed initial store with split metadata, choose and document an executable chemical conditioning mechanism, and compare its contribution separately from online replay. Do not encode numeric/prose inputs as untrained token strings.

### 3. External mined evidence cannot pass the current source allowlist unchanged

The later knowledge extension promises real source-qualified evidence (`docs/20261029_REAL_HYBRID_INTEGRATION.md:56–62`). However, `hybrid/run_stage1.py:114–116` derives allowed evidence families exclusively from CycPeptMPDB train-source membership. `hybrid/knowledge_parent.py:87–89` rejects any evidence family outside that set. A newly mined external article with its genuine independent family identifier is therefore rejected; one must not relabel it as a database training source to bypass this check.

Required repair: use a frozen reviewed allowlist for external evidence families, alongside explicit benchmark overlap and held-out exclusions. Verify this through the real entry-point configuration, not only selector fixtures with arbitrary allowed families.

### 4. Online generated parents can disable the knowledge intervention

`hybrid/knowledge_parent.py:162–167` falls back for the entire pool if any parent is absent from the frozen parent map. Since the runtime's retrieval store is populated with generated molecules, subsequent retrieved parents will generally lack reviewed metadata. An accepted nonempty catalogue therefore does not ensure actual repeated knowledge use.

This fail-closed behaviour is preferable to invented chemistry metadata; the architectural gap is the lack of an explicit policy for mixing reviewed eligible parents with newly generated ones. Required repair: define that policy and test/log knowledge-use coverage over rounds, with a real reviewed catalogue. Otherwise the knowledge-on arm can become ordinary retrieval after its initial round.

### 5. The stall gate does not observe the rounds in which learning stalls completely

Original anchors: design `:126`, `:132`; implementation plan U3 `:44`.

`orchestrator/loop.py:253–256` calls the updater only when a pair exists. The gate runs inside that step (`hybrid/adapters.py:51–61`), and its counter advances only after an actual optimiser update. Rounds with insufficient valid members or no qualifying preference pairs neither advance the gate nor trigger its escalation/stop. Thus the planned check after initial rounds can be postponed indefinitely precisely when the system cannot learn. It is an update-count gate, not the described search-round gate.

Required repair: separate per-round diagnostics/control from conditional optimiser steps, specify treatment of no-pair rounds, and test persistent no-pair trajectories. The logger at `orchestrator/loop.py:273–280` also omits small-group fraction, retained-group fraction, loss and gate action despite these being returned by components; retain them for audit.

### 6. Memorisation protection from the original design is absent

Original anchors: design `:55`, `:70`, `:126`.

The DPO reward uses the train verifier's score (`orchestrator/loop.py:235–256`); `hybrid/model.py:158–183` adds no memorisation term. The budget harness deduplicates evaluated molecules within a run, but neither integrated inputs nor outputs supply novelty checks against the full adaptation corpus and reviewed retrieval corpus. In particular, repeated generation of a known training structure is not the same condition as a duplicate oracle call.

Required repair: bind the relevant structure-key sets and report novelty against each set; prospectively specify any reward penalty and the distinction between allowed conditioning seeds and generated novelty. Corpus exclusions also remain prerequisite to a domain-adapted run.

### 7. Required attribution arms are not executable through the stage-1 entry point

Original anchors: design `:21`, `:87`; implementation plan `:53` permits no-rules/no-feedback first but does not eliminate later attribution.

`hybrid/run_stage1.py:39` supports only hybrid, no-rules and no-feedback. There is no no-retrieval or no-monitor route, nor a mask-only versus mask-plus-adaptation route. Knowledge off/on flags do not remove ordinary molecular retrieval. Required repair: implement the specified intervention matrix and test that each arm changes only its named component. Until then, code presence for the main arm cannot establish the original falsification criteria.

### 8. The claimed held-out learning-curve endpoint is not implemented and the original protocol conflicts with itself

Original design claim `:20` uses held-out AUC; design `:112` simultaneously says held-out verifiers are called only on final top-k. Implementation-plan stage-1 gate `:53` repeats train/held-out SD-AUC. Runtime `hybrid/run_stage1.py:143–147` computes only one final held-out mean; train AUC comes from `orchestrator/loop.py:296–298`. The A6 manifest comparison (`hybrid/run_stage1.py:63–70`) freezes a training SD-AUC margin, not a final held-out-mean margin.

Required resolution: prospectively reconcile the endpoint and margin without changing historical outcomes. The runtime's final-only held-out separation is appropriate for avoiding selection leakage; it simply does not produce the originally claimed held-out AUC. F1's failed admissibility floor remains independent of this issue.

## P2 — specification and verification gaps

### 9. The rule predicate is narrower than the original peptide-topology promise

Design `:80`, `:94` specify head-to-tail topology, D-residue patterns and PAINS prefix screening. `rules/spec.py:21–29` checks connectivity, a large ring, an N-methyl SMARTS count, MW, TPSA and PAINS; it does not establish head-to-tail peptide identity or a D-residue requirement. `rules/tracker.py:243–253` implements mass, N-methyl and remaining-token lower bounds, not all these prefix checks. Exact EOS validation ensures the implemented predicate only. Decide whether the broader conditions are needed, then implement or explicitly amend them; do not claim their presence from generic macrocycle validity.

### 10. Real-model acceptance remains unverified; boolean gate checks are not substantive evidence

`hybrid/run_stage1.py:52–56` verifies hashes and `passed`/`real_model` flags, but does not validate checkpoint identity, nonzero updates, restore evidence or control result contents against the current model/run configuration. A reviewed signed-off artifact can serve this role only if its schema and identity bindings are actually enforced. `docs/20261029_METHOD_REMOTE_VALIDATION.md` records 50 CPU synthetic/small-policy tests, explicitly not ChemFM learning or real-model restore. The 200-step and 5,000-model-sample U1 criteria from implementation-plan `:42` also remain unverified. Source code and toy tests are prerequisites, not milestone completion.

### 11. Resume is not yet an exact continuation of all observable state

`orchestrator/loop.py:202` recreates the stop-score cache empty; checkpoint restoration at `:204–215` restores model/monitor/oracle and reconstructs retrieval, but not this cache. Repeated stop evaluations after resume alter reported stop-call counts and cost; stochastic evaluators could also alter values. `hybrid/run_stage1.py:143–147` evaluates held-out results every invocation, including rerunning an already-finished output directory. Idempotent finalisation and complete accounting require explicit state. The new run-identity/deadline/restore code has not itself established real-GPU replay.

## Boundaries already implemented correctly

- Inherited ChemFM is loaded locally and only PEFT parameters are optimised; no scratch LLM pretraining is performed by this entry point.
- Sampling and DPO apply the same recorded temperature, mask and optional potentials; completion log probabilities include EOS and exclude the parent prefix.
- Same-round pairs share the realised prefix; preference scores determine pair order/eligibility, not a fabricated rank-advantage-weighted objective.
- Held-out scoring occurs after the search, outside updater and monitor signatures. Three-way role/source checks are called before the loop.
- Invalid, failed and duplicate proposals do not earn charged unique oracle evaluations, and proposal failures are represented rather than silently resampled.
- Source-qualified knowledge checks reject unsupported records. These guards should be preserved while repairing the real evidence and online-parent pathways.

## Evidence level

The latest inspected CPU QA document reports 14 eligibility tests, 19 mining/launcher contracts and 50 hybrid/adapters/policy-math/orchestrator/budget tests on existing EC2 Spot. These reports predate some resume changes and do not demonstrate end-to-end pretrained adaptation, an accepted real literature catalogue, ChemFM DPO updates, real-model restore, or improved candidate outcomes. No test was run as part of this audit.
