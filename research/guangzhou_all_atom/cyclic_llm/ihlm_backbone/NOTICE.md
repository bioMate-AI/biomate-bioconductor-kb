# Third-party notice: PeptideCLM-2 / PeptideMTR weights

The IH-LM backbone option `pclm2` initialises from the open-weight models `aaronfeller/peptideclm-2-mlm-small` and
`aaronfeller/peptideclm-2-mlm-base` (Hugging Face; author handle `aaronfeller`; model card "PeptideMTR: MLM Variant").

* Licence: **MIT**, as declared in the model-card metadata (`license: mit`, tag `license:mit`). The repositories contain no separate
  LICENSE file and the model card gives no copyright line, so the exact copyright holder/year text could not be reproduced here; the
  MIT licence requires that the copyright notice and permission notice accompany copies, so **before any redistribution of the weights
  or of derived weights, obtain the copyright line from the authors** (open item). We redistribute no weights: `fetch_weights.py`
  downloads them from the original repository at a pinned commit and verifies sha256.
* Code: the encoder and tokenizer in this directory are **our own re-implementation** written from (a) the published `config.json`,
  `tokenizer.json`, `tokenizer_config.json`, (b) the safetensors tensor names/shapes, and (c) a reading of the repository's
  `ChemPepMTR.py` as text to reproduce the architecture (pre-LayerNorm blocks, fused QKV attention without bias, rotary position
  embedding on interleaved channel pairs, SwiGLU feed-forward with biases, final LayerNorm, linear MLM head). No file from the repository was
  imported or executed (`trust_remote_code` is never used). The rotary-embedding formulation follows RoFormer (Su et al., 2021) as
  commonly implemented (e.g. torchtune); that formulation is public and not specific to the PeptideCLM-2 code.
* Pinned commits: small `7fe899df4d9753224aefa955ed0cf859d181e693`, base `d4e8bafa378b8670d178029d6f97af5a5ee209fc`.
* Pretraining data (per the model card of the PeptideCLM-2 suite as summarised in docs/20261030_PEPTIDE_CHEM_LM_MODEL_SURVEY.md): PubChem, ESM Atlas
  peptides, LIPID MAPS. Whether CycPeptMPDB-like structures occur in it is NOT verified (leakage caveat carried to every result using this backbone).
