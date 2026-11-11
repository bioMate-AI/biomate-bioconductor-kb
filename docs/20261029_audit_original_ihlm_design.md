# Original IH-LM architecture versus the current generative study

Audit date: 2026-10-29. Static source inspection only; no experiments, model loading, tests or numerical aggregation were performed. Existing document reports are identified as reports, not independently verified measurements.

## Main finding

The repository contains two different architectures under the IH-LM research programme. The original `ihlm/model.py` is a molecular **predictor and acquisition/edit-proposal system** with M1–M5. The current `allatom_paper/hybrid/model.py` is a **ChemFM causal generator** with Q/V LoRA, symbolic token masking, scoped parent selection and DPO. The original modules exist in code, but are not connected to the generator instantiated by `allatom_paper/hybrid/run_stage1.py`. Describing the latter alone as the complete original model loses substantial intended architecture; describing all original modules as active in the generator would also be inaccurate.

Paths below are relative to `research/guangzhou_all_atom/cyclic_llm/` unless prefixed `docs/`.

## Design lineage and representation

- `docs/20261027_ALLATOM_CYCLIC_LLM_CLOSED_LOOP_PLAN.md:14–20` specifies atom-level SMILES or SELFIES, large-corpus pretraining, cyclic-peptide fine-tuning, hard constraints, verifiable reward, conditioning priors, measured-label replay, and later uncertainty. It does not define a coordinate-generating network. Line 13 explicitly cautions against using unsupported co-folding confidence as feedback.
- `ihlm/model.py:17–43` represents molecules as atom/SMILES tokens with stereochemical symbols and optional graph-derived topology flags. These flags summarise rings of at least eight atoms and disulfide matches. They are not coordinates, conformers, protein–peptide geometry, or an equivariant model. `Tokenizer.fit` expands a vocabulary from observed tokens; it is not an unlimited pretrained representation of arbitrary new chemistry.
- `ihlm/model.py:47–73` implements a standard configurable encoder/decoder: learned absolute positions, LayerNorm, fused self-attention QKV, optional memory cross-attention and GELU MLP; the LM head is tied to token embeddings. This differs from the ChemFM Llama-family backbone used in the present generator.
- `docs/20261030_IHLM_PRETRAINING_PLAN_P1.md:16–30` registers a separate in-house P1 pretraining design and intrinsic/extrinsic gates. Lines 53–60 explicitly report that P1 training had not started in that document. Those statements do not establish current cloud status, which was not inspected here. The P0 statistics at lines 39–51 concern a separate checkpoint and cannot validate the ChemFM initialisation.

## Original modules: what is actually implemented

| Module | Code and behaviour | Connection to current generator |
|---|---|---|
| M1 knowledge-prior channel | `ihlm/model.py:160–187` accepts a numerical callable K(smiles), combines batch-standardised neural and K scores, and adds similarity-weighted retrieval. `ihlm/symbolic.py:110–111` uses w=n0/(n0+n). This is numeric score fusion, not textual knowledge conditioning. | Not imported or instantiated. Scoped evidence-to-parent selection is a different mechanism. |
| M2 assay/source offsets | `ihlm/symbolic.py:124–157` fits replicate-anchor ridge offsets; sources without replicate anchors use K-residual or grand-mean residual offsets. `ihlm/model.py:184–186, 253` adds offsets to ranking scores and corrects training labels. | Not integrated into the generator's learned architecture. Source-standardised verifier data do not constitute this M2 module. |
| M3 analog retrieval and cross-attention | `ihlm/model.py:90–105` constructs analog-token embeddings plus label projections, cross-attends to them, and uses similarity-biased attention/readout with a learned gate. `:137–143` packs up to k neighbours, truncating analog tokens to at most 64. `ihlm/symbolic.py:175–192` implements chirality-aware retrieval. | Current ChemicalRetriever provides molecular parents; it does not insert analog-token/label memory into ChemFM attention. |
| M4 edit effects and proposals | `ihlm/symbolic.py:53–101` detects or enumerates N-methyl additions/removals and stereocentre flips. `:159–173` estimates shrinkage edit effects. `ihlm/model.py:102–105` adds a learned edit residual; `:212–221` ranks enumerated edits using uncertainty/UCB or prior fallback. | This predictor-side edit executor exists, but is not called by the current generative runner. The generator's evidence adapter permits only `select_parent`; it does not invoke M4. |
| M5 fast/slow feedback, uncertainty and verifier head | `ihlm/model.py:228–273` writes symbolic memory on every non-frozen update and schedules neural fitting. Training uses Gaussian NLL, pairwise ranking and optional verifier BCE. `:198–210` returns uncertainty and a verifier-aware score. | Current generator uses DPO updates and a separate stop monitor, not this M5 training/uncertainty implementation. |

The module list is not a complete switchboard: M4's neural residual is nested inside the M3 branch (`model.py:97–105`); M5's memory schedule, uncertainty heads and fitting logic are not conditioned on `'M5' in modules` (`:81–84, 228–273`). An M5-off arm cannot be assumed to ablate these behaviours simply by removing its name.

## Pretrained component integration

The generic `IHLM.init_backbone_from` hook at `ihlm/model.py:127–134` copies only shape-compatible state-dictionary entries and reports counts. It is a partial-load hook, not evidence of a particular pretrained integration; it can record `open_weights` even when zero tensors match.

A more substantive integration exists separately:

- `ihlm_backbone/adapter.py:40–54` defines `PClmIHLM`, replaces the in-house tokenizer/backbone with the PeptideCLM wrappers, and strictly loads the external checkpoint.
- `adapter.py:15–37` adds a new cross-attention module after each encoder attention sublayer; its output projection is zero-initialised. This preserves the original encoder calculation at initialisation when evaluated consistently, while creating a trainable analog-memory channel.
- `pclm_encoder.py:27–67` defines the bidirectional encoder with LayerNorm, interleaved RoPE, fused QKV, SwiGLU and an MLM head. It is not a causal generator.
- `pclm_tokenizer.py:9–16, 42–48` reconstructs the published WordPiece vocabulary and special-token handling, with no topology tokens and no vocabulary expansion.
- `adapter.py:5–6` explicitly records analog truncation and a single learning rate for backbone and new modules. The default `_slow_fit` trains all model parameters (`ihlm/model.py:255–257`), except the explicit LayerNorm-only mode. This is not frozen-backbone LoRA.
- Repository search found `PClmIHLM` construction in `ihlm_backbone/test_backbone.py:123,137`, not in the current generative runner. The test source is not proof that parity or scientific validation passed in this audit.

## Current generative wiring

`allatom_paper/hybrid/run_stage1.py:91–100` imports and constructs `ChemFMGenerator`. Lines 105–129 optionally attach `ConditionalParentSelector`; lines 130–140 construct the rule constraint, chemical retriever, stopping monitor and DPO updater, then call the loop. This concrete call graph contains no `IHLM`, `PClmIHLM`, `Net`, M2 offsets, neural analog cross-attention, learned edit residual or M5 uncertainty module.

`allatom_paper/hybrid/model.py:18–36` loads a causal Hugging Face base and Q/V LoRA. Its sampling path selects a chemical parent and token prefix; its DPO path updates adapters using sampled completions. This may be a valid generative branch, but it is not a completed integration of the original M1–M5 architecture.

## Static issues requiring resolution before claiming the original design is validated

1. **Calibration information separation is incomplete.** `ihlm/model.py:250–253` chooses fit/calibration rows but constructs analog packs and corrected labels from the full memory before fitting. `FastMemory.write` already fitted offsets and edit effects to all observed rows (`symbolic.py:115–121`). Thus calibration labels can affect training inputs through analog label embeddings and symbolic estimates. Excluding calibration rows from the neural loss (`model.py:259`) does not restore the usual split-conformal separation. `:269–273` therefore does not by itself justify a distribution-free coverage claim. Separate calibration data from every fitted memory/statistic and audit the entire dependency graph.
2. **Vocabulary growth after network creation is unsafe without resizing.** `model.py:233` fits new tokens on updates, but `_ensure_net` only constructs the embedding when `net is None` (`:123–125`). A genuinely new token arriving after the first neural fit can receive an ID beyond the existing embedding and LM-head size. Freeze a verified vocabulary or resize embeddings and tied output weights consistently.
3. **Score fusion is candidate-batch dependent.** `model.py:175–183` standardises each score component using the candidates in that call. A singleton has zero centred components; different batching or pool composition changes absolute scores. This may be intended for a fixed-pool ranker, but must not be treated as a pool-invariant molecular predictor or directly comparable acquisition score across batches.
4. **Stereochemical edit labels are an approximation.** `symbolic.py:54–67` uses S→R and R→S changes to name D/L flips. CIP R/S is not a universal mapping to amino-acid D/L. The chemical inversion exists, but residue-aware stereochemical assignment is needed before claiming D/L-specific knowledge transfer.
5. **Prior units and provenance require explicit bindings.** `symbolic.py:11–26` disables previously pooled, leakage-affected priors by default and offers train-source-clean effects in within-source z units. `FastMemory` otherwise works in the caller's label units. The caller must establish unit compatibility and source exclusions before non-neutral priors are used; passing a rule file alone is insufficient.

## Implication for the paper and next implementation decision

The manuscript should distinguish the original predictive/selection architecture, its PeptideCLM-backed variant, the proposed in-house P1 backbone, and the current ChemFM generative branch. Architectural novelty cannot be inferred from combining their descriptions. Select the intended main model, then either connect the original modules through explicit generator/selector interfaces with controlled ablations, or present the branches as separate systems. Preserve the original M1–M5 design in the architecture inventory until that decision is made; the present generator illustration should not silently replace it.
