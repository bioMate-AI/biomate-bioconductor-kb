# IH-LM provenance table (2026-10-30) — what is ours, what is standard, what is third-party

Rule (owner): the model is claimed as ours — our backbone implementation, our hybrid modules, our loop interface. Every standard component is disclosed and cited; no third-party modelling code is copied; any external weights are an optional, separately disclosed initialisation arm. This table goes into the paper's Methods. Code paths are under `research/guangzhou_all_atom/cyclic_llm/` unless noted.

## 1. Code
| component | file | status | provenance / citation | third-party code copied? |
|---|---|---|---|---|
| Transformer backbone (pre-LN blocks, scaled-dot-product attention, learned positions, tied embedding head; configurable depth/width; encoder or decoder; optional cross-attention to a memory) | `ihlm/model.py` (`Block`, `Backbone`), earlier iterations `allatom/atom_lm.py`, `v4_eval/v5_train.py` | **standard architecture, our implementation** | Vaswani et al. 2017 (Transformer); Xiong et al. 2020 (pre-LN); PyTorch `scaled_dot_product_attention` (BSD-3 library call, not copied code) | no |
| SMILES atom-level tokenizer regex | `ihlm/model.py` `SMILES_RE` | **standard public pattern** | Schwaller et al. 2019, ACS Cent Sci 5:1572 (Molecular Transformer); same pattern in `allatom/atom_lm.py` | the regular expression only (a public pattern) |
| Topology tokens (macro-ring count, S–S flag) | `ihlm/model.py` `Tokenizer.topo_tokens`; heuristic head-to-tail/lariat split in `v4_eval/v5_atom_tokens.py` (accuracy measured: lariat recall 0.983, head-to-tail recall 0.642 vs CycPeptMPDB `Molecule_Shape`) | ours (graph rules with RDKit) | RDKit (BSD-3) for ring perception | no |
| Chirality-aware similarity (Morgan counts, `includeChirality=True`) | `ihlm/symbolic.py` | standard method, our use | Rogers & Hahn 2010 (ECFP); RDKit (BSD-3) | no |
| M1 knowledge-prior channel with evidence-weighted fusion w = n0/(n0+n) | `ihlm/symbolic.py` `FastMemory.evidence_weight`, `ihlm/model.py` `score`; K_phys from `kb_audit/peptide_sar_kb.py` | **ours (integration)**; shrinkage is a standard Bayesian idea | conjugate shrinkage (general); rule mining and K_phys channel: our `kb_audit` | no |
| M2 lab/assay offset module (hierarchical random effect b_s; replicate-anchor and residual estimators) | `ihlm/symbolic.py` `estimate_offsets`, `_fit_offsets` | **ours (integration)**; random effects are standard | linear mixed models (general) | no |
| M3 stereo-aware analog-retrieval cross-attention (analog tokens + label embedding as cross-attention memory; similarity-biased analog read-out) | `ihlm/model.py` `Net.forward` | **ours (design)**; retrieval-augmented models exist generally | retrieval-augmented language models (Lewis et al. 2020, Borgeaud et al. 2022) as general context — prior-art check for peptide-specific use still open | no |
| M4 edit-space head (edit detection, conjugate-shrunk effects, proposals, learned residual) | `ihlm/symbolic.py` `edit_type`, `propose_edit_smiles`, `FastMemory._fit_edit_effects`; `ihlm/model.py` `edit_res` | **ours (design)**; matched-molecular-pair analysis is standard | Hussain & Rea 2010 (MMP); priors from our `stratification` analysis (docs/20261029_CYCLIC_PEPTIDE_STRATIFICATION_ANALYSIS.md B4) | no |
| M5 dual-memory interface (closed-form fast memory + scheduled slow neural update), split-conformal intervals, aleatoric head, verifier-aware reward head | `ihlm/model.py` | **ours (design)**; conformal prediction is standard | split-conformal: Vovk et al.; Lei et al. 2018 | no |
| Loop adapters / cost meter | `v4_eval/loop_model.py`, `atom_loop_model.py` | ours | — | no |
| Pretraining and corpus filter code | `v4_eval/v5_train.py`, `filter_corpus.py` | ours | — | no |
| Chemistry toolkit | RDKit (BSD-3) | third-party library, used as a dependency | RDKit | not copied |

## 2. Weights and data
| item | source | licence | used how |
|---|---|---|---|
| P0: 25.5 M-parameter atom-level LM | ours, trained 2026-10-27 on 2.87 M ChEMBL-derived molecules (1.7 % macrocycles), 49 min on one L4 | ChEMBL CC BY-SA 3.0 corpus (share-alike on derived databases; model-weight position needs legal view) | **pipeline proof only (P0); no foundation-model claim** |
| P1: our pretrained backbone | to be trained (see `20261030_IHLM_PRETRAINING_PLAN_P1.md`) | corpus licences per source in the plan | main model if it passes the pre-registered gates |
| External-weight initialisation arm (optional, later): PeptideCLM-2 (MIT) | Hugging Face `aaronfeller/peptideclm-2-*` | MIT (HF model cards) | **only as a separately disclosed arm**, never as the main model; modelling code not executed (custom code); architecture would be re-implemented by us and weights loaded where shapes match (`IHLM.init_backbone_from` records source, licence and tensors loaded) |
| External comparators (not our model): ChemBERTa, PeptideCLM(-2), HELM-BERT, MoLFormer, ChemFM etc. | Hugging Face | per model card (see survey) | compared against, never merged into IH-LM |

## 3. Claim boundary
We claim (i) the five modules and their integration into one loop-native model, (ii) measured ablation results of each module, (iii) the loop evaluation design with its controls. We do **not** claim the transformer backbone, the SMILES tokenisation idea, ECFP similarity, random effects, conformal prediction or MMP analysis as novel. Prior-art checks for M3/M4 (retrieval-conditioned and edit-space models for peptides) remain open items before the paper's novelty statement.
