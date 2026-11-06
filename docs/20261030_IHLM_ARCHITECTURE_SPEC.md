# IH-LM — in-house hybrid, loop-native cyclic-peptide language model: architecture specification (2026-10-30)

Status: **specification before implementation; no result.** Working name IH-LM (rename freely). Owner direction: our own model with architectural innovation, claimed as ours; lineage of standard parts disclosed honestly.

## 1. Design principle
A configurable backbone (standard transformer family) wrapped by **five innovation modules that make the model loop-native and hybrid**. The innovation claim lives in the modules and their integration, not in the backbone. Every module is an ablation rung (pre-registered), so each claim is measured.

## 2. Components: what is standard, what is ours
| component | role | status / provenance |
|---|---|---|
| Backbone (decoder or encoder transformer, RoPE/standard attention, configurable depth/width) | sequence modelling | **Standard.** Our implementation of a standard design; initialisation options: (a) from scratch, (b) initialised from open weights where architecturally compatible (e.g. PeptideCLM-2, MIT) — disclosed, licence notice kept. Both reported. |
| Tokenizer: atom-level SMILES with explicit chirality, ring-closure/topology tokens, open vocabulary for unseen monomers | representation | Overlaps published peptide LMs (survey: high prior-art risk) — **not claimed as novel**; our ablation of stereo/topology tokens is a measured contribution only if the survey's gap holds. |
| **M1 Knowledge-prior channel with evidence-weighted fusion** | y_hat = f_K(x) + learned residual; weight n0/(n0+n) shrinks as feedback accumulates; rules carry effect size, CI, provenance, within-source validity | **Ours (design).** Prior art for Bayesian priors/shrinkage is general; the integration as a loop-updated symbolic memory for cyclic-peptide LMs is the claim to test. |
| **M2 Lab/assay offset module** | hierarchical random effect b_s per lab/assay, estimated from k anchor compounds; makes pooled multi-lab data usable | **Ours (design)** for the integration with an LM and anchor protocol; random effects themselves are standard. |
| **M3 Analog-retrieval cross-attention** | conditions predictions on the k nearest revealed analogs (stereo-aware similarity), because analog lookup is the strongest baseline | **Ours (design)** for stereo-aware peptide retrieval conditioning inside the loop; retrieval-augmented models exist generally. |
| **M4 Edit-space head** | predicts effects of edits (N-Me add/shift, D-flip, residue swap, ring change) with transferable priors; proposes edits from a measured parent | **Ours (design)**; matched-pair modelling exists generally — prior-art check before claiming. |
| **M5 Dual-memory loop interface** | fast symbolic memory updated in closed form from graded results + slow neural memory updated by fine-tuning/DPO; calibrated uncertainty head for acquisition; verifier-aware reward head | **Ours (design).** |
| Constrained decoding (rules enforced at generation) | generation validity | Pattern from SNG literature; our rules and integration; evaluated for validity only retrospectively. |

## 3. Provenance and disclosure table (maintained in the repo; goes into the paper's Methods)
For every checkpoint used: name, source URL, licence, whether initialised from it, what we changed. For every standard component: cite the original. Claims in the paper: (i) the five modules and their integration, (ii) measured ablation results, (iii) the loop evaluation design — never the backbone, the tokenisation idea, or third-party weights.

## 4. Implementation contract (for workstream 1)
One model class `IHLM(backbone_cfg, tokenizer_cfg, modules=[M1..M5])` with a `LoopModel`-compatible interface: `score`, `update(mode)`, `fingerprint`, `uncertainty`, `propose_edits`. Backbone swap must not change module code. Each module has a planted-signal test and a leave-labs-out test. Training budget and cost per the staged rules (USD 40 against the high spot price). Own code in `research/guangzhou_all_atom/cyclic_llm/ihlm/`; do not copy third-party modelling code into our files without attribution; any adapted file keeps its licence header.

## 5. Evaluation (unchanged rules)
Ablation ladder on the same backbone: plain → +M1 → +M2 → +M3 → +M4 → (+M5 loop updates); comparators = external pretrained peptide/chemistry LMs fine-tuned plainly + baselines; leave-labs-out, H4b few-label, five controls, validity gates, contamination-controlled reporting; nulls reported.
