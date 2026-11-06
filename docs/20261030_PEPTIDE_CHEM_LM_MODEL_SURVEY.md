# Peptide / chemistry / protein language models: candidates for the cyclic-peptide comparison (survey, 2026-10-30)

Purpose: choose pretrained comparators for a small (~25M, atom-level) cyclic-peptide LM trained in a feedback+knowledge loop, to be compared against larger pretrained models fine-tuned on the same revealed labels (cyclic-peptide permeability, binding ranking). Read-only survey; no weights were downloaded and no model code was executed (no `trust_remote_code`).

Method and conventions. Parameter counts below are either (a) read from the Hugging Face API `safetensors` field ("HF-API"), (b) stated in a paper/model card ("card"), or (c) derived by me from config.json arithmetic ("derived", approximate, flagged). Anything I could not open or confirm is in the "Unverified" list at the end. SMALL = <=~50M, LARGE = >=~100M. 30-110M sits in the gap and is labelled MID.

## 1. Peptide / cyclic-peptide-specific models

| Model | Params | Size class | Pretraining data | Tokenizer / representation | Stereo + ring closure | Licence | Weights | Max len | Reported cyclic-peptide result | Source (opened) |
|---|---|---|---|---|---|---|---|---|---|---|
| PeptideCLM-23M-all (RoFormer MLM, v1) | 23M (card) | SMALL | 10.8M peptides + 12.6M small molecules (card) | SMILES; custom SmilesPE-style tokenizer, not loadable via AutoTokenizer (needs repo code) | Yes (SMILES; ring-closure digits; v1.1 fixed a ring-numbering bug in generated peptides) | MIT | OPEN (pytorch_model.bin; custom tokenizer from GitHub) | not stated | Best of the PeptideCLM v1 variants on CycPeptMPDB PAMPA fine-tuning (README, no numbers) | https://huggingface.co/aaronfeller/PeptideCLM-23M-all ; https://github.com/aaronfeller/PeptideCLM ; https://huggingface.co/api/models/aaronfeller/PeptideCLM-23M-all |
| PeptideCLM-12M-smol, -11M-pep | 12M / 11M (model ids; counts not independently opened) | SMALL | smaller-corpus ablations of the same recipe | as above | as above | MIT (smol/pep: licence field blank in listing) | OPEN | n/a | none stated | https://huggingface.co/api/models?search=PeptideCLM&limit=20 |
| PeptideCLM-2 small (MLM / MTR / hybrid) | 31,668,629 (HF-API, mlm-small); paper: 32M, 6 layers, d=384 | SMALL | ~118M molecules: PubChem 108.6M, ESM Atlas peptides 9.6M, LIPID MAPS 49K; per epoch ~10M peptides + 10M small molecules + 250K lipids | SMILES; custom k-mer tokenizer (max 6 chars), 405-token vocab, ~60% shorter than char-level | Yes (SMILES; stereo preserved per paper) | MIT | OPEN (safetensors, but `custom_code`: needs the repo's modelling file; do not enable remote code blindly, vendor and audit it) | not found | Reported only for the large model (below) | https://huggingface.co/api/models/aaronfeller/peptideclm-2-mlm-small ; https://pmc.ncbi.nlm.nih.gov/articles/PMC12803269/ |
| PeptideCLM-2 base | 114,011,541 (HF-API, mlm-base); paper: 114M, 12 layers, d=768 | LARGE (lower edge) | same | same | Yes | MIT | OPEN (custom_code) | not found | none quoted | https://huggingface.co/api/models/aaronfeller/peptideclm-2-mlm-base |
| PeptideCLM-2 large | 336,671,125 (HF-API, mlm-large); paper: 337M, 24 layers, d=1024 | LARGE | same | same | Yes | MIT | OPEN (custom_code); mtr/hybrid variants also released for all 3 sizes (12 repos total across v1+v2) | not found | CycPeptMPDB permeability classification, full fine-tune: AUROC 0.829 +/- 0.020 (MLM), 0.836 +/- 0.011 (hybrid) vs Morgan FP 0.792 and RDKit-99 descriptors 0.800. Paper itself flags structural overlap in CycPeptMPDB (8.06%), so splits matter | https://pmc.ncbi.nlm.nih.gov/articles/PMC12803269/ ; https://huggingface.co/api/models/aaronfeller/peptideclm-2-mlm-large |
| HELM-BERT (DeBERTa) | 54,787,662 (HF-API); card: 54.8M, 6 layers, d=768 | MID (just over small) | ~75K deduplicated peptides from ChEMBL, CREMP, CycPeptMPDB, Propedia (card). The arXiv abstract says 39,079 peptides; the two numbers disagree, see Unverified | HELM notation, 78-token vocab (monomer-level) | Monomer + explicit connections express cycles; atom-level stereo only as far as the monomer vocabulary encodes it (D-residues are separate monomers); cannot represent arbitrary new chemistry outside the 78 monomers | MIT | OPEN (custom_code) | 512 | CycPeptMPDB random split regression R2 0.658, Pearson 0.817 (card). Note CycPeptMPDB is in its pretraining data, so leakage risk on that benchmark | https://huggingface.co/Flansma/helm-bert ; https://huggingface.co/api/models/Flansma/helm-bert ; https://arxiv.org/abs/2512.23175 |
| PepLand | not stated | n/a (graph NN) | ~8M peptides (UniProt-derived, <=30 residues) + 8,977 non-canonical peptides (stage 2) | multi-view heterogeneous graph (atom / fragment / junction) | atom graph; chirality handling not verified | CC-BY 4.0 (article); code licence not checked | Repo claimed in paper (github.com/zhangruochi/PepLand); I did not open the repo, so weights UNVERIFIED | peptides <=30 residues | none verified for cyclic permeability | https://pmc.ncbi.nlm.nih.gov/articles/PMC12315545/ |
| PepFoundry / CHUCKLES | n/a (a featurisation package/format, not a model) | n/a | n/a | CHUCKLES: standardised monomer-ordered SMILES with atom maps | Yes (SMILES-based; cycles preserved) | not checked | package only | n/a | n/a | https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12848965/ (opened only via search snippet, see Unverified) |
| PepINVENT | not stated | n/a (REINVENT-style generative prior) | semi-synthetic peptide set, ~900K training peptides, 6-18 residues, ~60% macrocyclic (from a related paper's snippet, not PepINVENT itself, see Unverified) | atom-level / CHUCKLES-style masked-position generation | Yes (atomic representation) | Apache-2.0 | OPEN: pretrained generative priors AND a macrocyclic permeability predictor in `data/models/` | not stated | ships a permeability predictor (metrics not verified) | https://github.com/MolecularAI/PepINVENT |
| PepALD | not stated | n/a (generative, autoregressive latent diffusion) | ChEMBL + CycPeptMPDB | HELM monomer sequences with learned monomer embeddings | ring topology controllable; stereo not verified | not stated | availability not determined | not stated | generation + permeability/affinity guidance; no clean fine-tunable encoder | https://arxiv.org/pdf/2606.14510 |
| CycPeptMP | not stated | SMALL-MID (atom Transformer + monomer CNN + MLP fusion, trained from scratch) | none (supervised on CycPeptMPDB, 743 PAMPA peptides used) | atom graph features with 3D-distance matrices + monomer + fingerprints | atom graph; ring closure implicit in graph | paper CC-BY 4.0; code licence not checked | code on GitHub (akiyamalab/cycpeptmp); trained weights not verified | n/a | test RMSE 0.63 +/- 0.02, R 0.87 +/- 0.02 (743-peptide PAMPA set, Kennard-Stone split) | https://pmc.ncbi.nlm.nih.gov/articles/PMC11361855/ |
| CPMP (Molecular Attention Transformer) | not stated | SMALL | none (supervised) | MAT graph input | graph | Apache-2.0 | OPEN: `saved_model` directory with trained models in repo | n/a | not verified | https://github.com/panda1103/CPMP |
| Multi_CycGT | not stated | SMALL | none | GCN + Transformer multimodal | graph + sequence | not checked | code repo not found by search | n/a | reported accuracy 0.8206, AUC 0.8650 (search snippet of the bioRxiv abstract) | https://www.biorxiv.org/content/10.1101/2023.06.20.545822.full.pdf (snippet only) |
| MultiCycPermea | not stated | SMALL | none | 2D image + 1D sequence multimodal | image of structure; stereo likely lost in 2D image (my inference) | not checked | code repo not found by search | n/a | MSE 0.16 vs Multi_CycGT 0.29 in-distribution (search snippet; the quoted "44.83%" does not match 0.29 to 0.16, which is 44.8%, so it is consistent) | https://bmcbiol.biomedcentral.com/articles/10.1186/s12915-025-02166-2 (snippet only) |

Take-away: only three peptide-specific pretrained LMs are genuinely open, fine-tunable and cyclic-aware: PeptideCLM (v1 23M; v2 32M/114M/337M) and HELM-BERT (55M). The supervised cyclic-permeability networks (CycPeptMP, CPMP, Multi_CycGT, MultiCycPermea) are trained from scratch on a few hundred to a few thousand labels and are best treated as task baselines, not pretrained comparators.

## 2. General chemistry language models (SMILES/SELFIES)

| Model | Params | Size class | Pretraining data | Tokenizer | Stereo / rings | Licence | Weights | Max len | Cyclic-peptide result | Source (opened) |
|---|---|---|---|---|---|---|---|---|---|---|
| ChemBERTa-2 77M-MLM (DeepChem) | ~3.4M (derived from config: 3 layers, d=384, FFN 464, vocab 600); the "77M" in the name is the pretraining set size, not params | SMALL | 77M PubChem SMILES (naming; data size not independently opened) | RoBERTa BPE-type, vocab 600 | SMILES; stereo tokens possible, not verified | licence not shown | OPEN (pytorch_model.bin) | 515 positions | none | https://huggingface.co/DeepChem/ChemBERTa-77M-MLM/raw/main/config.json ; https://huggingface.co/api/models/DeepChem/ChemBERTa-77M-MLM |
| MoLFormer-XL-both-10pct (IBM) | 46,805,760 (HF-API) | SMALL (despite "XL") | 10% of ZINC15 + PubChem (card) | SMILES custom tokenizer | Stereo REMOVED in pretraining ("isomeric information removed"); sequences >202 tokens dropped; card warns untested above ~200 atoms | Apache-2.0 | OPEN (safetensors; modelling code in repo, remote code needed) | 202 | none | https://huggingface.co/ibm-research/MoLFormer-XL-both-10pct ; https://huggingface.co/api/models/ibm-research/MoLFormer-XL-both-10pct |
| MolT5-base | ~248M (derived from config: 12+12 layers, d=768, gated-GELU FFN 2048, untied output head, vocab 32,128) | LARGE | C4 + ZINC SMILES-text (not opened) | T5 SentencePiece (spiece.model), not chemistry-aware | SMILES; tokenisation fragments rings/stereo awkwardly | Apache-2.0 | OPEN (pytorch_model.bin) | not stated | none | https://huggingface.co/laituan245/molt5-base/raw/main/config.json ; https://huggingface.co/api/models/laituan245/molt5-base |
| SMI-TED (IBM) | 289M "Light" variant (card); an 8x289M mixture variant is also listed | LARGE | 91M PubChem SMILES (~4B tokens) | BERT-style vocab (bert_vocab_curated.txt) | stereo handling not stated | Apache-2.0 | OPEN (pytorch + safetensors) | 202 | none | https://huggingface.co/ibm-research/materials.smi-ted |
| ChemFM-1B | 970,287,104 (HF-API; model card says 1.0B; the mirror text said 1.1B) | LARGE | UniChem (178M molecules per the paper, via search snippet) | SMILES, Llama-style causal LM | not stated on cards | MIT | OPEN (safetensors, Llama architecture, no remote code) | not stated | none for peptides | https://huggingface.co/api/models/ChemFM/ChemFM-1B ; https://huggingface.co/Aurigene-AI/ChemFM-1B |
| ChemFM-3B | 3,004,357,632 (HF-API) | LARGE | UniChem | as above | not stated (README empty) | MIT | OPEN (3 safetensors shards, ~12 GB) | not stated | none | https://huggingface.co/api/models/ChemFM/ChemFM-3B ; https://huggingface.co/ChemFM/ChemFM-3B |
| Uni-Mol | not opened | n/a | 3D conformer-based; for a 100+ atom flexible macrocycle, conformer generation is the bottleneck | 3D coordinates | stereo via 3D | not checked | not checked | atoms-limited | none | not opened, excluded |

Of the ChemBERTa/MoLFormer "XL"/"77M" naming: neither name implies a >=100M parameter model. If a LARGE general chemistry LM is wanted, use MolT5-base, SMI-TED, ChemFM-1B/3B, or PeptideCLM-2 base/large.

## 3. Protein LMs applied to peptide sequences

These cannot represent non-canonical amino acids, D-stereochemistry, N-methylation or cyclisation topology (only a linear 20-letter string; cyclisation could only be crudely encoded by a head-tail cue). They are a lower-bound "sequence-only" control.

| Model | Params | Size class | Licence | Weights | Max len | Source (opened) |
|---|---|---|---|---|---|---|
| ESM-2 t6 8M | 8M (name) | SMALL | MIT (family) | OPEN | 1026 positions | https://huggingface.co/api/models?author=facebook&search=esm2&limit=20 |
| ESM-2 t12 35M | 35M (name; config 12 layers, d=480, vocab 33) | SMALL | MIT | OPEN | 1026 | https://huggingface.co/facebook/esm2_t12_35M_UR50D/raw/main/config.json |
| ESM-2 t30 150M | 150M (name) | LARGE | MIT | OPEN | 1026 | same listing |
| ESM-2 t33 650M | 652,358,616 total tensor elements incl. 1,026 int buffer (HF-API) | LARGE | MIT | OPEN | 1026 | https://huggingface.co/api/models/facebook/esm2_t33_650M_UR50D |
| ESM-2 t36 3B, t48 15B | 3B / 15B (names) | LARGE | MIT (family; not individually opened) | OPEN | 1026 | listing above |
| ESM-C 300M | 300M (name; weights `.pth`, no safetensors) | LARGE | listed as MIT plus "other" third-party terms; read the notice before use | OPEN (.pth) | not checked | https://huggingface.co/api/models/EvolutionaryScale/esmc-300m-2024-12 |
| ProtT5-XL-UniRef50 | ~3B (name "XL"; not opened as a number, see Unverified) | LARGE | not shown | OPEN (pytorch_model.bin) | not stated | https://huggingface.co/api/models/Rostlab/prot_t5_xl_uniref50 |

## 4. Fine-tune cost estimates (single 24 GB L4)

Assumptions (my estimates, not measured): 2-5k compounds, 5 epochs-to-30 epochs with early stopping, treat 30 epochs as the upper bound; average ~200 tokens per cyclic peptide for atom/char-level SMILES (PeptideCLM-2's k-mer tokenizer is ~60% shorter, so ~80-100); total ~30M training tokens per run at 5k compounds x 30 epochs. Cost ~ 6*N*tokens FLOPs for full fine-tune (about 4*N*tokens for LoRA); L4 bf16 effective throughput taken as ~8 TFLOP/s (about 25% of nominal) with padding overhead. Memory: full fine-tune with AdamW needs ~16 bytes/param (fits for <=~650M; 1B is borderline), so >=1B uses LoRA/QLoRA. Multiply by number of seeds/folds (assume 5).

| Model | Method | GPU-hours per run (est.) | x5 seeds |
|---|---|---|---|
| PeptideCLM-2 small 32M, PeptideCLM 23M, HELM-BERT 55M, MoLFormer 47M | full FT | 0.1-0.4 | 0.5-2 |
| PeptideCLM-2 base 114M | full FT | ~0.7-1 | ~4-5 |
| ESM-2 150M / 650M | full FT (650M ~11 GB optimiser state) | 0.3-1 / 1.5-3 (short residue sequences) | 1.5-5 / 8-15 |
| PeptideCLM-2 large 337M | full FT | ~2-3 | ~10-15 |
| MolT5-base ~248M, SMI-TED 289M | full FT | ~1.5-2.5 | ~8-12 |
| ChemFM-1B | LoRA, bf16 | ~3-5 | ~15-25 |
| ChemFM-3B | LoRA, bf16, gradient checkpointing | ~10-15 | ~50-75 (consider 1 seed + bootstrap) |

Note any number above could be off by 2x either way; a 200-step timing probe on the actual box is a cheap 10 minutes and should replace this table before committing budget.

## 5. Ranked recommendation

LARGE (>=100M):
1. PeptideCLM-2 large (337M, MIT, SMILES with stereo and rings, 10M-peptide pretraining, published CycPeptMPDB baseline AUROC 0.83): the strongest peptide-aware LARGE comparator; ~2-3 GPU-h/run. Vendor and audit the custom modelling file rather than enabling remote code.
2. PeptideCLM-2 base (114M): same family and tokenizer at a third of the size, giving a within-family scale ablation (32M vs 114M vs 337M) that isolates pretraining scale from data.
3. ChemFM-1B (970M, MIT, standard Llama arch, no remote code): the strongest general chemistry LM that fits via LoRA; tests whether generic molecular scale helps cyclic peptides; ~3-5 GPU-h/run. ChemFM-3B only if budget allows (about 10-15 GPU-h/run).
4. SMI-TED 289M (Apache-2.0, 91M PubChem): a mid-size general chemistry encoder; caveat: stereo handling unstated and 202-token cap, so verify that cyclic peptides tokenise without truncation.
5. ESM-2 650M (MIT): sequence-only protein-LM control for peptides expressible in 20 letters; cannot see ncAAs/stereo/cyclisation, which is exactly the point of the control. Cheap.

SMALL (<=~50M):
1. PeptideCLM-2 small (32M, same recipe as the large models): the fairest size-matched pretrained rival to our ~25M model; MIT.
2. HELM-BERT (55M, MIT, HELM monomer tokens, cycles explicit): different representation (monomer-level), directly cyclic-peptide-oriented; caveat: its pretraining corpus includes CycPeptMPDB, so avoid using that benchmark for it, or deduplicate against it.
3. PeptideCLM-23M-all (v1) or MoLFormer-XL-10pct (47M): the v1 model gives the closest parameter match (23M); MoLFormer is a non-peptide SMALL control but its pretraining removed stereochemistry, so it will lose D/L information, which makes it a useful ablation.

Leakage rules for every comparator: PeptideCLM-2 pretraining includes ESM Atlas and PubChem molecules (could contain CycPeptMPDB-like compounds; not verified), HELM-BERT explicitly includes CycPeptMPDB, and PeptideCLM-2's own authors report 8.06% structural overlap inside CycPeptMPDB. Deduplicate our test splits against each model's pretraining set where it is available, or document that it could not be done.

## Unverified (do not cite as fact)

- PeptideCLM-12M-smol / -11M-pep parameter counts and PeptideCLM-2 max sequence length: not found.
- HELM-BERT pretraining set size: card says ~75,000, arXiv abstract says 39,079 curated peptides; reconcile by reading the paper (full text not opened).
- PepLand: parameter count, weights availability and chirality handling; I did not open the GitHub repo.
- PepFoundry, PepINVENT training-set details (~900K peptides, ~60% macrocyclic came from a third paper's search snippet about a related generator, not from PepINVENT itself), and PepINVENT parameter count and permeability-predictor metrics.
- PepALD: code/weights, size, results (PDF excerpt did not state them); recommend not using it as a comparator since it is a generator.
- CycPeptMP trained-weights availability and licence; Multi_CycGT and MultiCycPermea code availability and their metrics (search-snippet only).
- ChemBERTa-2 pretraining size and licence; parameter count is my arithmetic from config, not HF-API. MolT5-base parameter count is derived the same way.
- ChemFM tokenizer, max length, stereo handling, and the 178M-molecule UniChem figure (search snippet only; README of 3B is empty).
- ESM-2 3B/15B and ESM-C 300M exact counts (taken from model names), ESM-C max length, and ProtT5-XL parameter count and licence.
- Uni-Mol: not opened; excluded.
- Whether any model's pretraining corpus overlaps our evaluation compounds.
