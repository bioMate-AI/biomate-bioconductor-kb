# Learned computational knowledge bridge: implementation proposal

Status: **static bridge and generator/runner integration implemented; real-source qualification and scientific validation pending**. The static evidence packer and isolated policy/reference attention primitive are described in `20261029_KNOWLEDGE_BRIDGE_COMPONENTS.md`. Typed projection and the isolated pinned-Llama decoder adapter now pass synthetic remote checks; see `20261029_KNOWLEDGE_DECODER_INTEGRATION.md`. Opt-in generator-class sampling, optimiser updates, frozen-reference switching and checkpoint integration now pass tiny-model remote tests. Experiment-runner input wiring now passes remote synthetic contracts, including matched null/on selection, source exclusions and checkpoint restoration. Scientifically qualified real evidence and full-size checkpoint validation remain incomplete. This document does not report a trained model, accepted knowledge catalogue, successful study or validated scientific performance.

## 1. Purpose and design boundary

The original generative branch selected a parent using scoped evidence, supplied a SMILES prefix to ChemFM, and updated Q/V LoRA through masked-likelihood DPO. The implemented opt-in bridge additionally makes source-qualified evidence available to a **trainable attention branch inside the existing decoder**. Typed memory is projected into decoder width and attended after causal self-attention, before the MLP. This extends hidden representations without requiring prose interpretation. Real-source catalogue qualification remains a prerequisite for scientific use.

The extension reuses the memory-attention pattern already implemented for the original predictive IH-LM: molecular/analog features form an external memory; decoder states attend to that memory; a new residual branch starts with zero output so the initial model is functionally unchanged. The current generator, symbolic token mask, sampling protocol and verifier separation remain the integration points. A new neural backbone, a 3D coordinate model and a separate language encoder for literature are not needed.

A reviewed evidence catalogue is a scientific prerequisite. Current mined records that failed endpoint, scope, provenance or structure qualification must not become neural memory merely because attention can consume them. A software fixture can verify shapes and information separation, but cannot stand in for an accepted research catalogue.

## 2. What can be reused from the original M1–M5 design

Paths in this section are relative to `research/guangzhou_all_atom/cyclic_llm/`.

| Existing component | Reuse in this proposal | What is not implied |
|---|---|---|
| M1 numerical knowledge fusion (`ihlm/model.py:160–187`) | Evidence provenance, scope checks and the distinction between knowledge and acquired labels inform feature construction. | Its batch-standardised scalar ranking formula is not silently appended to decoder logits. |
| M2 source offsets (`ihlm/symbolic.py:124–157`) | Remains a separate, explicitly specified verifier/data-preprocessing component if used. | No new decoder “lab correction” or causal laboratory effect is claimed. |
| M3 analog memory (`ihlm/model.py:90–105`) | Reuse the external-memory tensor and attention pattern, with input masks and a residual output. | The predictor's supervised analog labels cannot be copied into a generation round before those labels are available. |
| PeptideCLM memory adapter (`ihlm_backbone/adapter.py:15–37`) | Reuse its attention implementation pattern and zero-initialised output projection. Reuse the existing strict frozen encoder for molecular features. | Its bidirectional encoder is not converted into a causal generator. |
| M4 symbolic edits (`ihlm/symbolic.py:53–101,159–173`) | Qualified edit-type annotations can be categorical evidence features. An accepted measured effect can be a separately qualified numeric feature. | The bridge does not execute edits or supply a universal N-methylation/D-flip reward. |
| M5 memory/update separation (`ihlm/model.py:228–273`) | Freeze an input-memory snapshot for each generation/preference group; incorporate newly revealed train outcomes only in the next snapshot. | The original predictor's conformal uncertainty claim or calibration implementation is not transferred to this generator. |

The original M1–M5 predictor and the ChemFM generator remain distinct software systems. This bridge integrates a specific M3-style mechanism into the latter; it does not establish that all original modules have been integrated.

## 3. Memory construction: exact permitted information

### 3.1 Separate static evidence from acquired experimental history

Use two typed memory channels:

1. **Static evidence K:** approved, source-linked claims with explicit applicability and approved molecule/parent mappings. These are available before the generation round.
2. **Observed history R:** permitted retrieved molecules and their previously revealed training-oracle scores. This channel is optional and separately ablated. It must never contain stop/final-held-out scores or the current round's unrevealed outcomes.

The first implementation should support static K and the already available chemical-parent features; learned use of R can follow behind its own explicit configuration flag. This prevents an improvement from being attributed to mined knowledge when it actually comes from observed-score attention.

For each evidence item, retain a non-tensor audit record containing source ID/hash, quotation offsets, extraction/review revision, evidence ID, matched scope fields, approved parent mappings, exclusions and missing-field decisions. Hashes and document IDs are lineage records, **not numeric predictors**. Arbitrary source IDs should not be embedded as a shortcut to outcome provenance.

### 3.2 Feature eligibility

The minimal computational evidence representation contains:

- A frozen molecular embedding of the **already known, approved parent or associated reference molecule**, when that mapping is structurally verified. Compute with the existing `FrozenPeptideEncoder`; preserve model/file/code identity and truncation diagnostics.
- A typed claim representation: property, endpoint class, assay class, closure class, scaffold class, solvent/context class, and optional qualified edit type. Categorical vocabularies are fixed from development data; unseen categories use an explicit unknown category. Unknown applicability does not become a positive match.
- Payload fields with explicit missingness: qualitative direction or relation class, evidence type, and whether a matched comparison is established. Do not infer a direction from an unrelated endpoint or treat extraction confidence as scientific confidence.
- Numeric effect fields **only if** the item separately passes numeric-prior eligibility: explicit measured endpoint and unit, reference/comparator, direction, scope, and compatible normalisation. Otherwise the numeric fields are zeroed and their availability masks are false. A scope-qualified qualitative claim can still be used without an invented effect size.

Use a frozen unit/property normalisation registry fitted only on allowed development/training evidence. No inference-time normalisation over the complete test catalogue or hidden labels. A paper's reported assay concentration is not an effect size; a docking value is not an experimental affinity label.

Do not average incompatible assays or sum extracted directions into a generic benefit score. Conflict-bearing or unresolved items are excluded in the minimal version; later conflict modelling would be a separate design.

### 3.3 Applicability before feature encoding

For evidence item j and round context c, compute a Boolean eligibility predicate a_j(c) from the frozen source split, approved mapping, task scope and required fields. Only eligible items are dereferenced/encoded. Ineligible slots contain finite zero padding and are attention-masked. This avoids both accidental information access and NaN propagation from masked features.

An always-valid zero/null slot ensures that an empty eligible catalogue does not cause an all-masked softmax. The no-knowledge condition attends only to that null slot. This represents absence of evidence, not evidence that every feature equals zero.

Scope/site-specific rules require an explicit atom/residue mapping before local positional features are admitted. The minimal implementation is **global contextual conditioning**, not an atom-local intervention model; it must not claim to know which generated residue a positional claim refers to when no mapping exists.

## 4. Tensor contracts and neural computation

Use the manuscript's row-vector convention. The dimensions below are symbols; layer choices, widths and capacities belong in the experimental configuration, not the general method description.

| Tensor | Shape | Meaning |
|---|---|---|
| X | B × T | Current SMILES token IDs, including the shared known prefix and only already generated tokens during sampling |
| H^(l) | B × T × d | Hidden states of decoder layer l |
| E_mol | B × M × d_e | Frozen embeddings of permitted known molecules associated with memory slots |
| F_cat | B × M × f_c | Encoded typed categorical evidence features |
| F_num, A_num | B × M × f_n | Qualified numeric payloads and Boolean availability masks |
| A_mem | B × M | Boolean memory-slot eligibility; includes one always-valid null slot |
| E_type | B × M × d_type | Learned type embedding distinguishing static evidence, permitted observed history and null |
| Z | B × M × d | Learned projected memory consumed by attention |

Here B indexes distinct conditioning groups. All samples used in one preference group share the same prefix, memory snapshot and eligibility mask. M is a bounded, deterministically ordered memory capacity, including the null slot. If evidence exceeds capacity, apply a predeclared development-only selection rule and record dropped IDs; do not select using generated-candidate scores or final outcomes.

Construct memory as

Z = P([E_mol ; F_cat ; (A_num ⊙ F_num) ; A_num ; E_type]),

where P is a small trainable projection/MLP. Missing molecular embeddings receive zero padding with a separate presence flag in F_cat. Continuous values must be finite before masking. Fixed feature-extraction operations and frozen encoder weights receive no gradients; P does.

At selected decoder layers l, add the memory branch after the base self-attention residual and before the base feed-forward sublayer:

Q_m = LN_m(H_self) W_Qm,
K_m = Z W_Km,
V_m = Z W_Vm,
A_m = softmax(Q_m K_m^T / sqrt(d_h) + M_elig),
H_mem = H_self + concat_heads(A_m V_m) W_Om.

M_elig is zero for admitted memory slots and negative infinity for excluded slots. It is distinct from both the causal self-attention mask and the chemical next-token mask. The base decoder then continues with its existing normalisation and feed-forward block.

Reusing the original adapter pattern allows a dedicated LayerNorm in the new branch even though the pretrained ChemFM blocks use RMSNorm. This is a new branch parameter, not a replacement of pretrained RMSNorm weights. The number of attention heads must divide the bridge query/key/value width; make this an explicit configuration check.

Initialise W_Om and its bias to zero; initialise Q/K/V and P normally. Do not simultaneously initialise a multiplicative gate to zero, which would suppress the output-projection gradient as well. With this initialisation, the first forward pass equals the original generator; the output projection can learn immediately, and the upstream branch projections receive gradients once it moves away from zero.

Freeze the ChemFM base and frozen peptide encoder. Train the selected LoRA matrices plus P, LN_m and memory-attention parameters. The paper must therefore stop describing the extended model as “only LoRA parameters are trainable.” Parameter accounting should report LoRA and bridge trainables separately after implementation, rather than importing parameter counts from the original predictive model.

## 5. Causality and information separation

A frozen external memory does not require a triangular mask over its own slots because every admitted slot is available before generation. Causality still requires that query state H_t depends only on the known prefix and y_<t through ChemFM's causal self-attention.

The following restrictions are mandatory:

- Build the memory once from the known parent/retrieval set and eligible evidence **before** sampling the group. Do not encode the completed candidate, its future tokens, current-round score, or chosen/rejected label into memory.
- During teacher-forced likelihood computation, each completion token uses its causal predecessor state. Reuse the exact memory snapshot used during sampling. Do not reconstruct memory from the full teacher-forced sequence.
- Retrieval may use the already known full parent if that is the declared input. This is not future generated-token access, but it makes parent copying easier. Give controls the same known chemical inputs and report exact-parent recovery/novelty so copying cannot masquerade as knowledge benefit.
- After scoring round r, its newly revealed train outcomes can enter R_(r+1), never K_r or R_r used to recompute that round's DPO likelihoods.
- Stop and final-held-out outcomes have no route into memory, parent ranking, preference pairs or gradients. Their isolation must be enforced by input schemas and source roles, not only described in prose.
- Do not use evaluation targets, source-specific IDs or unavailable assay outcomes to choose evidence slots. An independently supplied target/task specification is allowed; its hidden response is not.

Static molecular embeddings can be cached by canonical molecule plus encoder identity. Trainable memory projections and K/V tensors cannot be reused across optimiser updates as detached stale caches. For training, recompute them with gradients. Sampling-only caches must be invalidated after every update and keyed by bridge revision and exact memory snapshot.

## 6. DPO reference policy and consistent conditioning

Let c comprise the shared SMILES prefix, static memory tensors, slot masks, evidence snapshot identity and permitted observed history. Let C be the same symbolic rule state/policy used for generation. The extended policy is π_(θ,φ),C(y|c), where θ denotes generator LoRA and φ denotes bridge parameters.

For each pair, use

Δ_policy = log π_(θ,φ),C(y+|c) − log π_(θ,φ),C(y−|c),
Δ_ref = log π_(θ0,φ0),C(y+|c) − log π_(θ0,φ0),C(y−|c),
L = −log σ[β(Δ_policy − Δ_ref)].

Policy and reference must use identical c, temperature, hard mask, admitted soft potentials and completion-token accounting, including EOS. Neither sees the other candidate's future tokens.

**Disabling LoRA alone is insufficient once the bridge trains.** The current `disable_adapter()` reference path would leave a mutable bridge active and no longer represent the initial reference policy. Add an explicit reference context that selects both frozen initial generator adaptation and frozen bridge snapshot φ0. Keep these reference parameters immutable and outside the optimiser. If the bridge is adapted in a separate supervised stage, φ0 is the frozen post-adaptation bridge, not an arbitrarily reset zero branch.

For a first implementation with a zero-output bridge and no separate supervised bridge adaptation, φ0 is the zero-output initial bridge. Both policies receive the same c, but the initial reference has no learned response to it. This is mathematically valid and must be described explicitly; it does not establish pre-existing knowledge competence.

Do not clone the entire billion-parameter base just to store the reference: reuse the frozen base, disable generation LoRA for reference evaluation as currently done, and select a frozen copy/state of the relatively small bridge modules. A context manager must restore policy mode after exceptions and preserve gradient settings. Verify that changing policy bridge weights changes policy logits while leaving reference logits fixed.

The monitored KL must also compare the policy and reference with identical c and masks. Retain the existing precise interpretation: categorical token KL averaged over visited pair contexts, not the full sequence-distribution KL.

## 7. Minimal implementation map

Integration roadmap; standalone packer and attention primitive now exist, while the end-to-end steps remain incomplete:

1. **Extract the reusable attention primitive.** Move the existing `CrossAttn` implementation into a small shared module without `import model as IH` or predictor side effects; retain the old adapter import so its behaviour does not change. Add the dimensions/mask/zero-output checks needed by the generator. Do not import the full original `PClmIHLM` merely to use one attention layer.
2. **Evidence tensor packer.** Extend the reviewed catalogue interface with explicit typed feature/normalisation schema, eligibility flags and approved molecule associations. Emit immutable CPU feature arrays, masks and a digest. Keep source text, evidence IDs and hashes in audit records rather than neural numeric features.
3. **ChemFM decoder integration.** Add an optional explicit decoder-layer wrapper or supported hook that preserves the installed Transformers layer signature, outputs, attention masks and KV-cache behaviour. Validate that exact library version before implementation. Default bridge-off must preserve existing generation. Avoid a module-global mutable memory variable, which could mix concurrent groups.
4. **Forward context.** Pass or bind the per-group memory snapshot for both sampling and teacher-forced log probabilities. Record its digest with every generated completion, alongside the existing prefix and completion record. Reject a pair whose candidates have different conditioning digests.
5. **Optimiser and reference.** Include bridge trainables alongside LoRA; add immutable reference-bridge state and policy/reference switching; update KL to use the same conditioning.
6. **Checkpoint/resume.** Save policy bridge, frozen reference bridge, optimiser state, feature schema, normalisation registry, encoder/code identity, source catalogue hash and group conditioning state required to resume safely. Refuse a resume with changed feature ordering, categorical vocabulary, layer placement, eligibility policy or evidence snapshot.
7. **Runner configuration.** Explicit bridge-off/default and bridge-on arms; freeze architecture/feature configuration in the existing study manifest. Parent selection is an orthogonal switch so the learned bridge can be evaluated without changing which parents are supplied.

No component should silently fall back to the old parent selector when the bridge is requested but missing or unqualified. Fail before a scientific run; allow explicitly marked synthetic fixtures only in integration QA.

## 8. Experimental separation and ablations

The principal causal contrast is **learned evidence conditioning with matched chemical inputs**, not merely comparison against a model with a different parent pool.

| Comparison | What remains fixed | What it tests |
|---|---|---|
| Base LoRA generator versus added null-memory bridge | Parent choices, chemical inputs, rule mask, budget, update protocol | Capacity/optimisation effect of adding the module |
| Null-memory bridge versus eligible static-evidence bridge | Same bridge architecture and parent sequence; R off in both | Incremental benefit from mined evidence |
| Static-evidence bridge with parent selection off versus on | Same evidence catalogue and bridge configuration | Additional contribution of evidence-driven parent selection |
| Static K only versus K plus previously observed R | Same static evidence and architecture capacity accounting | Effect of learned use of acquired feedback history |
| Inapplicable-evidence input | Same interface; predicates must reject all inapplicable slots | Scope enforcement; should reduce exactly to null-memory behaviour |
| Frozen versus trainable bridge | Same eligible evidence features | Whether the learned attention mechanism contributes |
| Appropriate corrupted-evidence control, if registered | Same shape and compatible endpoint/unit strata; explicit synthetic-control labels | Dependence on correct evidence relationships rather than feature availability |

A corrupted control must not be relabelled as authentic source evidence. Preserve the corruption map and prohibit mixing incompatible units/endpoints. The minimal required controls are bridge-off, null memory, applicable memory and inapplicable memory; optional additional controls need a fixed multiplicity family.

Use the existing candidate-quality and efficiency evaluation framework, supplemented with evidence-use diagnostics. Attention weights alone do not prove causal knowledge use. Measure whether removing or replacing an eligible evidence item changes the generated distribution or registered endpoints under matched seeds, while controlling for parent identity and chemistry availability.

No new architecture repairs the failed F1 verifier gate. Keep that limitation and all existing scientific acceptance criteria intact. Any calibration of optimisation diagnostics for the extra trainable parameters must be prospectively documented before confirmatory outcomes, not changed because a desired run stalls.

## 9. Required remote validation before study use

All executable checks remain remote-only. Prepare, then run on approved compute:

- Zero-output equivalence: logits and sampled policy match the existing generator at bridge initialisation, with identical masks and seeds.
- Causal prefix test: changing only future completion tokens cannot change earlier logits under teacher forcing.
- Memory role test: attempts to include current-round, stop or final-held-out outcomes fail before tensor construction.
- Eligibility test: inapplicable evidence equals null-memory output, including empty-memory and padding cases; finite outputs with no accepted facts.
- Differentiation test: bridge output projection has a finite, nonzero gradient; later updates reach upstream projections; frozen base and encoder stay unchanged.
- Reference test: policy bridge updates never move frozen reference logits; both see the same memory digest and masking configuration.
- Cache test: incremental decoding and full forward agree; a weight update invalidates projected-memory caches; no cross-group contamination.
- Resume test: uninterrupted and resumed synthetic runs agree on logits, optimiser state, conditioning digests and reference state; altered schema/catalogue/encoder identity is rejected.
- Ablation test: disabling parent selection does not disable the bridge, and disabling the bridge does not silently change parent selection or oracle accounting.
- Real-checkpoint integration only after synthetic checks: bounded remote run with the pinned causal base and reviewed evidence inputs, then separate scientific evaluation. Synthetic success is not a knowledge-effect result.

## 10. Implementation sequence

Implement the static-evidence feature contract first, then the shared attention primitive and explicit policy/reference context. Choose initial layer placement in a versioned experimental configuration after inspecting the pinned decoder implementation. Preserve the original predictor branch as a distinct model; evaluate the learned generator bridge with matched-parent controls. These source changes fall within the authorised architecture work. Remote execution remains subject to the separate compute budget. Until implementation and validation are complete, illustrations and manuscript claims must label this bridge as proposed rather than operational.
