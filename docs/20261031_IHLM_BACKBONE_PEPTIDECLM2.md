# IH-LM on an open-weight backbone: PeptideCLM-2 (our re-implementation, no remote code) — 2026-10-28 evening

Owner decision (2026-10-28): no from-scratch LLM pretraining. The IH-LM = our hybrid modules M1–M5 (`ihlm/model.py`, `ihlm_v2`) around an **open-weight pretrained backbone, initialisation disclosed**.
Code: `research/guangzhou_all_atom/cyclic_llm/ihlm_backbone/` (`pclm_tokenizer.py`, `pclm_encoder.py`, `adapter.py`, `fetch_weights.py`, `test_backbone.py`, `NOTICE.md`). Nothing trained, no GPU, no cloud spend.

## 1. Provenance (goes into the Methods provenance table)
| item | value |
|---|---|
| models | `aaronfeller/peptideclm-2-mlm-small` (31,668,629 params; d=512, 14 blocks, 8 heads, FFN 768 (SwiGLU), vocab 405, max 2048) and `-mlm-base` (114,011,541; d=768, FFN 1024) |
| pinned commits | small `7fe899df4d9753224aefa955ed0cf859d181e693`; base `d4e8bafa378b8670d178029d6f97af5a5ee209fc` |
| weights sha256 | small `713fb214c51d42bd038b4dd71928ea5f5e0c3c2cf58be1fce8345cc395ef5f4a` (126,690,964 B); base `2ee9244b84ff636080bbb7ef874d4a2d5159f70a8518f67a5065ff13fcab54e3` (456,074,420 B) |
| licence | MIT per model-card metadata. **Open item:** the repositories carry no LICENSE file and no copyright line, so the exact notice text could not be reproduced; obtain it from the authors before redistributing weights (we redistribute none: `fetch_weights.py` pulls from the source at the pinned commit and checks the hash). |
| repo files | `config.json`, `config.py`, `ChemPepMTR.py` (12,905 B), `tokenizer.json` (11,304 B), `tokenizer_config.json`, `special_tokens_map.json`, `README.md`, `__init__.py`, `model.safetensors`. Model card: "PeptideMTR: MLM Variant … BERT-based Transformer … Pretraining: MLM … Input: SMILES". Only data files are fetched; the `.py` files were read as text only. |
| architecture (as re-implemented) | embedding → N × [LayerNorm → fused QKV (no bias) with rotary embedding on interleaved channel pairs → out-proj (no bias) → residual; LayerNorm → SwiGLU (biases) → residual] → LayerNorm → linear MLM head. Dropout 0.1 on attention output and FFN output. The model-card/survey statement "small = 32M, 6 layers, d=384" does not match the repository config (14 blocks, d=512); the repository is what is loaded. |
| tokenizer | WordPiece (vocab 405; specials PAD 0, UNK 1, CLS 2, SEP 3, MASK 4; prefix `##`; max 100 chars/word) behind a regex `Split` (behaviour Isolated) of SMILES fragments; [CLS] … [SEP] template. No topology tokens. |
| pretraining data | PubChem, ESM Atlas peptides, LIPID MAPS (per the survey/model card). Overlap with CycPeptMPDB or our benchmark compounds: **not verified** — the leakage caveat travels with every result that uses this backbone (a compound-level overlap check against PubChem is the cheap test; not run). |

## 2. What was verified (CPU, all committed in `test_backbone.py`; 10 tests pass)
* **Strict load:** missing keys 0, unexpected keys 0 for both sizes; parameter counts equal the HF-API counts exactly. RoPE buffers are non-persistent in the source (recomputed).
* **Tokenizer parity:** our tokenizer vs the Rust `tokenizers` loader (reads the JSON only): 0 mismatches on 3,007 strings (3,000 CREMP SMILES + edge cases: ring `%11`, bracket atoms, `Cl/Br`, unknown tokens, empty, 150-/101-character words).
* **Encoder correctness (masked-token test; public data only):** 200 CREMP (CC BY 4.0) 4-/5-mers, any structure matching a CycPeptMPDB flat structure removed (CycPeptMPDB used only for that exclusion; 0 of the sampled candidates matched), 15 % of non-special tokens replaced by [MASK], seed 0, 776 masked tokens:
  | model | masked-token NLL (nats) | top-1 accuracy |
  |---|---|---|
  | small, pretrained, our implementation | **0.317** | **0.890** |
  | base, pretrained, our implementation | 0.411 | 0.858 |
  | small, **negative control: half-split instead of interleaved RoPE** | 3.005 | 0.281 |
  | small, random weights | 6.192 (ln 405 = 6.004) | 0.000 |
  The negative control shows the test can fail, i.e. the weight-to-architecture mapping (including the rotary pairing) is right. **Caveat:** CREMP molecules may be in PubChem, so a low NLL here partly reflects familiarity; this test validates the implementation, not generalisation.
* **Padding invariance:** hidden states of a molecule alone vs inside a padded batch agree to < 2e-4 (max abs). **Determinism:** identical outputs on repeated calls and after a fresh load.
* **Stereo/N-methyl sensitivity of the mean-pooled embedding** (1 − cosine; 80 edits each; the edits come from `symbolic.propose_edit_smiles` on 60 CREMP peptides): D-flip 0.0164, N-methyl add/remove 0.0652, different molecule 0.328. Edits move the embedding (> 1e-5) but far less than a molecule swap. Part of this is trivial (the edit changes tokens); it is reported, not a quality claim.
* **Adapter (`PClmIHLM`):** the unchanged IH-LM `Net`/`IHLM` classes run on it for all of M1–M5: update → score → uncertainty (conformal, n ≥ 24) → propose_edits → fingerprint/clone/frozen semantics (test `test_loop_interface_all_modules`). New cross-attention sublayers (for M3) have zero-initialised output projection: hidden states with and without a memory equal the pretrained encoder to < 1e-5 at initialisation. Planted signal (label = count of N-methylated amides, net only, 240 train rows, 120 steps, lr 1e-4): **held-out Spearman 0.915** (n = 160) — indicative, single seed, tiny data.
* **Existing suites unchanged:** `ihlm/test_ihlm.py` 12 passed + 3 expected failures; `ihlm_v2/test_ihlm_v2.py` 11 passed. `ihlm/model.py` was **not modified** (the swap is a subclass: tokenizer + backbone replaced after construction).

## 3. What could not be verified
* **Bit-level parity with the authors' remote-code outputs.** Running their code is excluded by rule, so no reference logits exist; evidence of faithfulness is indirect (strict load + MLM loss with a failing negative control + tokenizer parity with the Rust loader). Possible undetected differences: details that do not move MLM loss much (e.g. dropout placement, numerical precision of RoPE in float32).
* The copyright line (above); overlap of PeptideCLM-2's pretraining corpus with our evaluation compounds; behaviour of the base model beyond the MLM check (no planted-signal run on base).

## 4. Limits and open issues for the ladder
1. **No topology tokens** for this backbone (the atom tokenizer's macro-ring/S–S tokens are absent); M1–M4's symbolic parts are unaffected.
2. **One learning rate** for all parameters in `IHLM._slow_fit` (default here 1e-4): the new heads/cross-attention (random init) and the pretrained encoder share it. A per-group rate or LoRA needs a small hook in `ihlm/model.py` (not made; decision for the ladder owner).
3. Analog memory is truncated at 64 tokens (`_pack`), same as the base IH-LM.
4. The 1.0 s/step-class CPU cost is irrelevant on GPU; on CPU one `update` of the small model with the default 150 steps is minutes, so loop replays with many rounds should use GPU or fewer steps.
5. Max length: tokenizer truncates at `max_len` (default 512; model supports 2048).

## 5. Fine-tune cost estimate (from the survey table, `20261030_PEPTIDE_CHEM_LM_MODEL_SURVEY.md`; **an estimate, not measured**; no job launched)
Per fine-tune run on 2–5 k compounds: small ≈ 0.1–0.4 GPU-h (≈ USD 0.05–0.3 at spot prices), base ≈ 0.7–1 GPU-h (≈ USD 0.3–0.8); a 200-step timing probe on the target box should replace these before committing budget. The loop replay multiplies this by rounds × seeds × regimes: a full ladder-style grid with this backbone must be re-estimated from a measured per-update time.
