# Reviewer D_llm_architecture -- moonshotai/kimi-k3.1-pro
_(elapsed 179s; usage {'prompt_tokens': 30928, 'completion_tokens': 7123, 'total_tokens': 38051, 'cost': 0.133086, 'is_byok': False, 'prompt_tokens_details': {'cached_tokens': 0, 'cache_write_tokens': 0, 'audio_tokens': 0, 'video_tokens': 0}, 'cost_details': {'upstream_inference_cost': 0.133086, 'upstream_inference_prompt_cost': 0.061856, 'upstream_inference_completions_cost': 0.07123}, 'completion_tokens_details': {'reasoning_tokens': 4276, 'image_tokens': 0, 'audio_tokens': 0}})_

## 1. VERDICT ON OUR FINDINGS

1. **“Neural proposer/closed optimizer” implies learned design capability → it currently demonstrates neither learned repair nor affinity design** (Brief §2; Reveal §5). `neural_generator.py` re-ranks only \(4\times5\times4=80\) triples using null-target/permeability conditioning; `loop.py:revise()` remains deterministic. **Evidence needed:** comparison against exhaustive enumeration, random edits, and the deterministic repair at equal verifier cost, on held-out scaffolds and an action space too large to enumerate.

2. **“FEP is the trustworthy arbiter; MM-GBSA is a fallback” → neither is presently admissible** (`reward.py`; Brief §2–3; CaDA §§3–6). FEP has a −0.18 versus measured −0.95 kcal/mol control miss, ran metal-free, and still lacks unrestrained metal validation. Both MM-GBSA variants were ruled invalid. Treating pending physics as zero reward and pending binding as `0.0` in `rank_key` further confuses *unknown* with *neutral/good*. **Evidence needed:** metal-correct, unrestrained coordination validation; replicated prospective control edges with sampling uncertainty, including Asp→Ala; and assay-condition/metal justification. Until then, binding reward must be masked and affinity output must abstain.

3. **“The closed DPO loop has an independent evaluator” → it is anti-leakage, not independent experimental validation** (`methodology_close.py`; Brief §2). Oracles A and B share assay distribution, featurization, and systematic label biases; cluster-disjointness does not make B ground truth. The +0.098 result is valid narrow methodology evidence, not evidence of better binding or even reliably better measured permeability. **Evidence needed:** an external measured set or prospectively generated predictions, absolute held-out oracle performance, and comparison with non-DPO selection at equal oracle calls.

4. **“Availability transfers and all candidates pass” → robust but narrow transfer, with no demonstrated relevance to extracellular candidate function** (Availability doc; Reveal §3). LODO ρ≈0.40 on linear canonical SH3 peptides does not validate cyclic/ncAA macrocycles, solubility, aggregation, or surface-target activity. “First-of-its-kind” is also **[UNVERIFIED]** without a literature search. **Evidence needed:** external cyclic/ncAA measurements and explicitly named developability endpoints; otherwise retain it as an informational hydrophobicity/charge risk feature.

5. **“Hard gates produce decision-ready candidates” → several gates encode hypotheses or incomplete checks** (`score.py`; Reveal §4). RGD is a reasonable campaign constraint, not a universal binding theorem; developability heuristics are not measured failures; FTO has `patents_checked:false`. Conversely, gate passage is compatible with non-binding. **Evidence needed:** separate pharmacophore, legal-screen, and heuristic-developability verdicts, each with scope and provenance. Never aggregate them into “validated lead.”

6. **The audit findings themselves are strong, but the missing baseline is methodological:** with 80 free-space triples, an LLM is currently overhead. **Evidence needed:** a preregistered LLM-utility experiment showing value beyond exact enumeration before further generator training.

## 2. YOUR PROPOSAL FOR YOUR MANDATE AREA

Build a **hybrid, verifier-conditioned edit-policy proposer with a deterministic constrained executor**. Do not build a small αvβ6 affinity LM, and do not initially fine-tune the general LLM. Start with the strongest instruction-following LLM available through BioMate, frozen; retain the 4.8M domain LM only as an optional permeability-biased proposal prior.

### Inputs and action space

Add `policy_state.py` containing:

- canonical HELM/structure and scaffold/edit-site definition;
- target-product constraints and campaign-specific pharmacophore rules;
- verifier records with `{value, status, fidelity, provenance, applicability_domain, uncertainty}` rather than bare numbers or `"pending"`;
- an explicit oracle budget and completed computation results;
- typed SAR evidence cards;
- the data-split/anchor manifest.

Add `edit_actions.py` with a versioned JSON schema:

- `ReplaceMonomer(site, monomer)`;
- `SetNMethylation(site, state)`;
- `SetStereochemistry(site, state)`;
- initially restricted `ChangeCycleLinkage(...)` only after executor support exists;
- `RequestOracle(candidate_id, fidelity)`;
- `Abstain(reason)`.

Each proposal contains one or a few edits, evidence IDs, categorical expected effects, assumptions, and a cheapest next discriminator. The LLM never supplies authoritative ΔG, selectivity, FTO, or constraint verdicts.

Add `edit_executor.py:apply_edit()` to validate the schema, apply edits deterministically, canonicalize the molecule/HELM, and return a new candidate plus an execution certificate. Invalid monomers, unsupported chemistry, malformed rings, and unauthorized edits fail closed. `loop.py:revise()` becomes a baseline; the production path becomes `propose → execute → verify → optionally compute → propose/abstain`.

### Hard constraints versus soft objectives

Implement this distinction in a refactored `score.py`:

- **Hard/executor constraints:** parseability, supported chemistry, allowed edit sites, explicit campaign pharmacophore, and explicit user/business exclusions. A literal patent-claim exclusion may remain a conservative screen, but never be labelled legal FTO clearance.
- **Soft or separately reported:** heuristic developability, novelty, availability, permeability, and any predicted property. A heuristic can become hard only for a named campaign requirement.
- **Masked, not zero:** unrun, inadmissible, or out-of-domain computations. Remove the MM-GBSA fallback from `reward.py` and remove pending-binding `0.0` from ranking. Compare preference pairs only within compatible tasks and fidelity states.

The LLM may request computation, but `physics_dispatch` alone decides admissibility. No binding reward exists until the physics gate passes prospective validation.

### Retrieved SAR knowledge

Add `sar_store.py` with `EvidenceCard` fields for exact structure/edit, target and construct, assay type, value/unit, conditions, uncertainty, source, and split role. Retrieval should return concise cards and deterministic transformations—for example, matched-pair direction and magnitude—not unfiltered literature prose.

The model conditions on these cards but cannot convert ten points into a general affinity model. Display-NGS enrichment must not re-enter as binding supervision; sequence-only pretraining is permissible after deduplication, with no affinity claim. The in-cell data supervise availability only; permeability labels supervise permeability only.

### Training and evaluation without circularity

1. Establish frozen-prompt, deterministic-repair, random-edit, and exhaustive/greedy-search baselines first.
2. Create synthetic repair tasks by applying known edits to valid/invalid structures. Use executor search to produce *verified action traces*; train action prediction, not explanatory prose.
3. Only if prompting underperforms, add `train_edit_policy.py` for SFT and then conservative DPO on held-out task families. Reward valid execution, constraint repair, and verifier-call efficiency; keep a frozen reference and shuffled-reward placebo.
4. Split before retrieval or training by scaffold/cluster and, where relevant, target. Maintain an anchor registry: any anchor used in prompting, calibration, model selection, or force-field choices is permanently marked development data. Keep a separate automated-pipeline audit set; acknowledge that already inspected literature values are not pristine human-level holdouts.
5. Evaluate on new edit operators and scaffolds, not merely new examples of the same repairs. Report execution validity, repair success, oracle calls, diversity, constraint violations, and calibration. Binding evaluation remains a small, interval-reported anchor challenge—not a training set.

The deliverable for each candidate should be a **design certificate**: canonical structure, edit history, evidence IDs, gate scope, applicability-domain warnings, pending/admissible computations, explicit affinity/selectivity abstention where necessary, and the next falsifying computation.

## 3. THE ONE INNOVATION I WOULD BET ON

**Falsification-Contracted Edit Policies (FCEP):** every proposed chemical edit must carry a prospective, executable contract—predicted direction of a named observable, applicable evidence/domain, cheapest discriminating computation, and an abort condition. The policy’s permitted chemical trust region expands or contracts only from prospective contract outcomes, not from reward-oracle self-consistency.

SynCraft already establishes LLM-proposed deterministic molecular edits with retrieval; constrained generation, verifier-guided optimization, DPO/RLVR, and multi-fidelity active learning are also established directions. Their combination is not itself novel. The specific bet is that **counterfactual edit contracts, rather than scalar candidate rewards, can govern both chemical proposals and fidelity transitions**. Novelty of that exact formulation is **[UNVERIFIED]** pending a systematic literature and patent search.

**Falsifier:** on held-out multi-scaffold tasks, FCEP fails to reduce best-candidate regret at equal expensive-oracle budget versus the same edit policy without contracts and an uncertainty-aware search baseline, with bootstrap intervals excluding no meaningful benefit. A secondary falsifier is no improvement in prospective calibration/error of its predicted edit directions.

## 4. 30-DAY PLAN

1. **Days 1–3 — freeze data semantics [cheap].** Add split manifests, anchor roles, assay-unit/sign checks, and retrieval exclusion tests. **Go/no-go:** automated tests show zero audit-anchor records in prompts, retrieval, training, or tuning; otherwise stop model work.

2. **Days 2–6 — implement typed edits and executor [cheap].** Add the files above plus property-based round-trip tests. **Go/no-go:** 100% of supported edits execute deterministically and 100% of malformed/unsupported actions fail closed; unsupported operators are removed from the schema.

3. **Days 4–8 — repair verifier semantics [cheap].** Refactor `score.py` and `reward.py`; separate hard, soft, pending, and inadmissible states. **Go/no-go:** tests demonstrate that pending physics cannot improve rank/reward and no MM-GBSA value can enter αvβ6 binding reward.

4. **Days 6–10 — run the LLM-utility baseline [cheap].** Compare exhaustive enumeration on the current 80 triples, deterministic repair, random search, and frozen prompted edits; then construct held-out multi-site/multi-scaffold repair tasks. **Go/no-go:** do not train unless prompting beats the best non-LLM baseline by a preregistered margin—suggested ≥10% absolute repair success at equal verifier calls, with a bootstrap CI excluding zero.

5. **Days 9–16 — build verified trace training only if gated in [moderate GPU].** Train SFT/DPO on task-disjoint repairs, with fixed reference, multiple seeds, and shuffled-reward placebo. **Go/no-go:** retain the model only if held-out improvement reproduces across seeds without increased constraint violations or material diversity collapse; otherwise ship the frozen policy or deterministic search.

6. **Days 12–20 — integrate auxiliary oracles honestly [cheap/moderate].** Wrap permeability and availability with applicability-domain flags and external/cluster-held-out evaluation. **Go/no-go:** neither may gate extracellular binding or be described as functional availability; out-of-domain candidates must produce warnings rather than confident property gains.

7. **Days 15–25 — connect physics behind an admissibility interface [expensive spot GPU; deferrable].** Require the live-path readiness guard, restrained setup checks, then unrestrained metal validation before any binding edge. **Go/no-go:** if coordination or prospective controls fail, binding remains masked and no affinity-ranked candidates are emitted. Longer/replicated sampling occurs only after that gate.

8. **Days 24–30 — prospective challenge and release [cheap except optional physics].** Evaluate design certificates, reward-hacking/red-team cases, reproducibility, and the FCEP budgeted comparison. **Go/no-go:** release only if one command reproduces splits, baselines, seeds, placebo, and certificates; otherwise release the negative result and tools without a design-performance claim.

## 5. STOP DOING

- Stop training or presenting display-enrichment models as binding evidence.
- Stop calling oracle B independent experimental validation.
- Stop using MM-GBSA as an αvβ6 fallback or unvalidated FEP as a trustworthy reward.
- Stop treating pending values as zero and gate passage as evidence of binding.
- Stop expanding the LLM before beating exhaustive enumeration on the 80-triple space.
- Stop reporting availability “passes” for surface candidates as functional validation.
- Stop repeated anchor-driven tuning while retaining “held-out” language.

## 6. BIGGEST RISK WE ARE MISSING

**Optimization theatre:** the system can become excellent at producing articulate, gate-compliant repairs while affinity remains entirely unmeasured and the LLM contributes nothing beyond search overhead. The current chemical proposal space is exactly 80 triples, while only roughly ten binding anchors exist and are already being reused across physics and narrative decisions. Consequently, statistically persuasive DPO gains, clean certificates, and high gate-pass rates can all coexist with zero improvement in binding. The decisive safeguard is not a larger model: it is a preregistered requirement for **LLM value over enumeration at matched computation cost**, plus explicit affinity abstention until a prospective, admissible binding signal exists.