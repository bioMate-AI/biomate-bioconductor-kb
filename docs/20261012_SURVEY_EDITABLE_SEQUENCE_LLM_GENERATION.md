# Survey: editable-sequence generation in LLM / generative models

**Date:** 2026-10-12 · Scope: methods where a model **edits / transforms** an existing sequence (or
generates under edit / constraint operators) rather than only unconstrained de-novo generation — across
NLP, cheminformatics, and protein/peptide design. Written to inform the cyclic-peptide design program's
move from a rigid pharmacophore *gate* to a **flexible, expert-editable guideline layer** (see §8).

**Citation-confidence key** (honesty contract — no paper, author, or ID below is invented; uncertain IDs
are omitted or flagged, never guessed):
- ✅ verified via web search (author / venue / year / ID confirmed)
- ◆ recalled, high-confidence canonical paper (ID recalled, not re-verified)
- ⚠ work confirmed to exist but a specific detail (lead author / DOI) is recalled, not verified

Per-method tags: **(a)** edit operations supported · **(b)** how constraints are integrated · **(c)**
non-canonical / cyclic chemistry handling.

---

## 1. Edit-based / iterative-refinement sequence models (NLP foundations)
- **Levenshtein Transformer** — Gu, Wang & Zhao, NeurIPS 2019, arXiv:1905.11006. ◆ (a) **insert + delete**
  as first-class atomic ops, refining over rounds, not left-to-right. (b) dual policy (deletion classifier +
  placeholder/token insertion) by imitation learning; can hold fixed spans — the canonical "editable region"
  primitive. (c) NLP, but insert/delete-over-fixed-span maps directly to residue-level peptide edits.
- **Insertion Transformer** — Stern, Chan, Kiros & Uszkoreit, ICML 2019, arXiv:1902.03249. ◆ (a) **insert-only**;
  arbitrary-order generation choosing content + position → infilling between fixed anchors. (b) partial
  sequence = hard constraint. (c) NLP.
- **T5 span corruption** — Raffel et al., JMLR 2020, arXiv:1910.10683. ◆ (a) **span infill**. (b) masked→denoised
  conditioning; text-to-text framing underlies the instruction-edit models below. (c) general.
- **GLM** — Du et al., ACL 2022, arXiv:2103.10360. ◆ (a) **autoregressive blank infilling** of variable-length
  spans. (b) constrained by surrounding unmasked context. (c) general.
- **ILM (Infilling by Language Modeling)** — Donahue, Lee & Liang, ACL 2020, arXiv:2005.05339. ◆ (a)
  **span/word/sentence infill** at `[blank]` slots. (b) concatenated context + blanks; hard-preserves
  non-blank text — the cleanest "edit the masked region, keep the rest" template. (c) general.
- **Diffusion-LM** — Li, Thickstun, Gulrajani, Liang & Hashimoto, NeurIPS 2022, arXiv:2205.14217. ◆ (a) infill
  + **attribute-controlled rewriting**. (b) **classifier/gradient guidance** on continuous embeddings — soft,
  no hard guarantee. (c) general; the guidance pattern recurs in molecule/peptide diffusion.
- **SSD-LM** — Han, Kumar & Tsvetkov, ACL 2023, arXiv:2210.17432. ◆ (a) block-wise simplex diffusion, **local
  rewriting / modular control**. (b) logit-simplex guidance; controllable decoding without base-LM retraining.
  (c) general.
- **PEER** — Schick et al. (Meta AI), 2022, arXiv:2208.11663. ◆ (a) collaborative **edit actions** (add,
  delete, rewrite, explain, plan) as a repeated loop. (b) instruction + edit-plan conditioning; models the
  *reason-for-edit* — parallels "guideline → edit". (c) general.
- **CoEdIT** — Raheja, Kumar, Koo & Kang, EMNLP 2023 Findings, arXiv:2305.09857. ✅ (a) instruction-driven
  **rewrite/edit** incl. composite edits. (b) **instruction tuning** (~82K edit instructions); the edit is
  specified in natural language — closest NLP analogue to "edit this sequence per these guidelines". (c)
  general; template for a guideline-conditioned editor.
- **EditEval** — Dwivedi-Yu et al., 2022, arXiv:2209.13331. ⚠ a *benchmark* for instruction-based text editing
  — relevant as an edit-evaluation-design precedent.

## 2. Controllable / constrained decoding
- **NeuroLogic** — Lu, Welleck, West et al., NAACL 2021, arXiv:2010.12884 ◆; **NeuroLogic A\*esque** — Lu et
  al., NAACL 2022, arXiv:2112.08726 ◆. (a) enforce **lexical include/exclude** (predicate logic over phrases),
  A* adds lookahead. (b) **hard** constrained decoding over a satisfying beam. (c) analog of "must contain /
  must not contain substructure".
- **FUDGE** — Yang & Klein, NAACL 2021, arXiv:2104.05218 ◆; **GeDi** — Krause et al., EMNLP 2021 Findings,
  arXiv:2009.06367 ◆; **PPLM** — Dathathri et al., ICLR 2020, arXiv:1912.02164 ◆. (a) attribute-controlled
  generation/rewriting. (b) **soft** guidance (future-discriminator / class-conditional LM / classifier
  gradient into activations). (c) general; the plug-and-play-guidance lineage behind guided molecular diffusion.
- **RLHF (InstructGPT)** — Ouyang et al., NeurIPS 2022, arXiv:2203.02155 ◆; **DPO** — Rafailov et al., NeurIPS
  2023, arXiv:2305.18290 ◆. (a) preference-controlled generation. (b) control via **learned reward**
  (RL / closed-form preference) — directly importable as "prefer edits that satisfy med-chem rules".
- **Grammar / FSM / regex-constrained decoding** — e.g. Willard & Louf, "Efficient Guided Generation…",
  arXiv:2307.09702 ⚠. (a) any generation masked to a formal language. (b) **hard** next-token masking to a
  grammar/automaton — the only family that *guarantees* syntactic validity (enforce valid SMILES/SELFIES/HELM
  during editing). (c) enables guaranteed-valid chemical strings.

## 3. Molecular (SMILES/SELFIES/graph) editing & constrained generation
- **REINVENT** — Olivecrona, Blaschke, Engkvist & Chen, J. Cheminform. 2017, arXiv:1704.07555 ◆;
  **REINVENT 2.0** — Blaschke et al., JCIM 2020, DOI 10.1021/acs.jcim.0c00915 ◆; **REINVENT 4** — Loeffler et
  al. (AstraZeneca), J. Cheminform. 2024, DOI 10.1186/s13321-024-00812-5 ✅. (a) progressively: de-novo →
  **scaffold decoration + fragment/linker** → unified **R-group replace, linker, scaffold hopping, library
  design, molecule optimization**. (b) **RL / reward** (augmented likelihood) + transfer/curriculum; no
  decode-time hard constraint. (c) SMILES; no native cyclic-peptide / ncAA.
- **MolGPT** — Bagal et al., JCIM 2021, DOI 10.1021/acs.jcim.1c00600. ◆ (a) **scaffold-conditioned**
  completion/decoration. (b) conditioning tokens (scaffold + property). (c) SMILES.
- **Molecular Transformer** — Schwaller et al., ACS Cent. Sci. 2019, arXiv:1811.02633. ◆ (a)
  **reactant→product transformation** (chemically grounded edit). (b) reactant conditioning. (c) SMILES;
  underpins reaction-constrained editing.
- **Chemformer** — Irwin et al., Mach. Learn.: Sci. Technol. 2022, DOI 10.1088/2632-2153/ac3ffb. ◆ (a) BART-style
  **infill / synthesis / optimization** seq2seq. (b) fine-tune per task. (c) SMILES.
- **SELFIES** — Krenn et al., MLST 2020, arXiv:1905.13741. ◆ (a) *representation*: every string is a valid
  molecule → **any edit stays valid**. (b) representation-level hard validity. (c) string-level, not
  peptide-native.
- **SAFE** — Noutahi et al. (Valence Labs), 2023, arXiv:2310.10773 (Digital Discovery 2024, D4DD00019F). ✅ (a)
  reorders SMILES into fragment blocks so **scaffold decoration, fragment linking, scaffold hopping,
  superstructure** become left-to-right infilling. (b) **constrained-by-construction** (fix fragment blocks,
  generate rest) with SAFE-GPT. (c) SMILES; strong fit for fragment-constrained editing, canonical-chemistry
  oriented.
- **Modof** — Chen, Min, Parthasarathy & Ning, Nat. Mach. Intell. 2021, arXiv:2012.04231. ✅ (a) **single-site
  disconnection → fragment removal/addition**, chained across sites while retaining scaffold. (b) learned
  edit policy over graphs + similarity constraint. (c) graph/SMILES; a true lead-optimization editor.
- **DeepFrag** — Green, Koes et al., Chem. Sci. 2021, DOI 10.1039/D1SC00163A. ⚠ (a) **fragment grow/replace**
  at an attachment point in a pocket. (b) structure-conditioned fingerprint prediction + nearest-fragment
  retrieval (post-hoc). (c) small-molecule fragments.
- **JT-VAE** — Jin, Barzilay & Jaakkola, ICML 2018, arXiv:1802.04364 ◆; **HierVAE** — same authors, ICML 2020,
  arXiv:2002.03230 ◆. (a) latent generation/optimization; **local edits via latent interpolation/gradient**,
  HierVAE at motif/fragment scale. (b) property-gradient in latent space (soft); valid-by-construction decoding.
  (c) graph; small molecules.
- **Graph GA** — Jensen, Chem. Sci. 2019, DOI 10.1039/C8SC05372C. ◆ (a) **crossover + mutation** on molecular
  graphs (explicit edit operators). (b) evolutionary fitness selection (post-hoc). (c) graph; strong model-free
  baseline, no cyclic-peptide chemistry.
- **DrugAssist** — Ye et al. (Tencent AI Lab / Hunan Univ.), arXiv:2401.10334; Brief. Bioinform. 2025,
  DOI 10.1093/bib/bbae693. ✅ (a) **interactive, dialogue-driven molecule optimization** (single + multi-property)
  — edits requested in natural language. (b) **instruction tuning** (MolOpt-Instructions) + iterative feedback.
  (c) SMILES; clearest "guideline-as-instruction → edit" exemplar, not peptide/cyclic-aware.
- **Matched-molecular-pair (MMP) transformation learning** — Hussain & Rea, JCIM 2010 ◆ (MMP mining); He,
  Jiazhen et al., "Molecular optimization by capturing the chemist's intuition…", J. Cheminform. 2021,
  arXiv:2103.09919 ⚠. (a) learns **R-group/substituent transformations** from chemist-made pairs. (b)
  conditioning on desired property delta; transformations = the learned "edit vocabulary". (c) small molecules;
  the literal "med-chem rule as edit operator" family.

## 4. Structure / pharmacophore-conditioned generation
- **PGMG** — Zhu, Zhou, Cao, Tang & Li, Nat. Commun. 2023, DOI 10.1038/s41467-023-41454-9, arXiv:2207.00821.
  ✅ (a) **pharmacophore-conditioned de-novo generation**. (b) GNN encodes a spatial pharmacophore graph →
  transformer SMILES decoder; latent var for many-to-many. (c) small-molecule; the key template for "generate
  under a pharmacophore", though generative not edit-based.
- **DeepLigBuilder** — Li, Pei & Lai, Chem. Sci. 2021, DOI 10.1039/D1SC04444C. ⚠ (a) **3D pocket-based growth**
  (MCTS). (b) pocket conditioning + reward search. (c) small molecules.
- **Pocket2Mol** — Peng et al., ICML 2022, arXiv:2205.07249 ◆; **TargetDiff** — Guan et al., ICLR 2023,
  arXiv:2303.03543 ◆; **DiffSBDD** — Schneuing et al., 2022, arXiv:2210.13695 (Nat. Comput. Sci. 2024) ◆;
  **ResGen** — Zhang et al., Nat. Mach. Intell. 2023, DOI 10.1038/s42256-023-00712-7, arXiv:2305.10133 ✅.
  (a) pocket-conditioned 3D ligand generation (autoregressive or diffusion); **DiffSBDD supports
  scaffold/fragment inpainting** (fix known atoms, diffuse the rest — a genuine 3D edit). (b) pocket
  conditioning ± inpainting. (c) small molecules.

## 5. Protein / peptide sequence editing & design
- **ProteinMPNN** — Dauparas et al., Science 2022, DOI 10.1126/science.add2187. ◆ (a) **fixed-region / partial
  redesign** (hold specified residues, redesign the rest). (b) **structure-conditioned** (backbone graph) +
  per-position fixing = hard positional constraint. (c) canonical AA; not cyclic/ncAA out of the box.
- **ESM-1b / ESM-2** — Rives et al., PNAS 2021, DOI 10.1073/pnas.2016239118; Lin et al., Science 2023,
  DOI 10.1126/science.ade2574. ◆ (a) **masked-token editing** (mask residues, predict replacements). (b)
  constrained-mask on surrounding sequence; pseudo-likelihood guidance. (c) canonical AA.
- **ESM-IF1 (inverse folding)** — Hsu et al., ICML 2022, arXiv:2205.15019. ◆ (a) **structure→sequence** with
  positional fixing. (b) structure + fixed-position constraint. (c) canonical AA.
- **RFdiffusion** — Watson et al., Nature 2023, DOI 10.1038/s41586-023-06415-8. ◆ (a) **motif scaffolding /
  inpainting / partial diffusion** — hold a functional motif, (re)generate surrounding backbone; partial
  diffusion = controlled local structural edits. (b) conditioning + inpainting on fixed motif coords (hard
  structural constraint). (c) canonical protein backbones — but the inpainting paradigm is what RFpeptides
  extends to cycles.
- **PepFlow** — Li, Cheng, Wu, Guo, Luo, Ren, Peng & Ma, ICML 2024, arXiv:2406.00735. ✅ (a) **full-atom peptide
  co-design**; partial sampling → fix-backbone sequence design / side-chain packing (edit one modality, hold
  the rest). (b) multi-modal **flow matching** on SE(3)/tori/simplex; receptor-conditioned. (c) full-atom,
  canonical-AA trained (side-chain modeling is a step toward ncAA).
- **PepGLAD** — Kong, Jia, Huang & Liu, NeurIPS 2024, arXiv:2402.13555. ✅ (a) **binding-site-conditioned
  full-atom peptide generation + binding-conformation recovery** (sequence-structure co-design). (b)
  VAE latents + **latent diffusion** with a receptor-specific affine transform for cross-shape generalization.
  (c) full-atom, variable-size residues — architecturally better positioned for non-standard residues.
- **RFpeptides** — IPD (Bhardwaj, DiMaio, Baker et al.), *Nature Chemical Biology*, June 2025 ✅ ("accurate de
  novo design of high-affinity protein-binding macrocycles"; added to RFdiffusion). (a) **de-novo macrocyclic
  (cyclic) peptide binder design** — cyclic backbone generation + side-chain placement into a target pocket
  (RFdiffusion inpainting paradigm). (b) structure/target conditioning via diffusion; cyclization enforced in
  backbone construction. (c) **explicitly cyclic** — ≤20 designs/target gave medium–high-affinity binders for
  4 proteins; one Kd < 10 nM; X-ray-validated to Cα RMSD < 1.5 Å. The single most directly relevant model for
  cyclic-peptide design. (Lead-author attribution recalled as Rettie — IPD/Baker confirmed.)
- **HELM notation** — Pistoia Alliance; Zhang et al., JCIM 2012. ⚠ not a generator: a **hierarchical
  representation** for ncAA, cyclization, branches, conjugates. **Native cyclic/ncAA support** — the
  representation layer a guideline-driven peptide editor needs, which the sequence generators above lack.

## 6. Edit-as-action / matched-pair / human-in-the-loop editing policies
- **Editing as a sequential decision process**: REINVENT (RL over the distribution) → Modof (learned
  single-site disconnect-edit policy) → Graph GA (evolutionary mutation/crossover) → DrugAssist (dialogue
  edits). The action space *is* chemical edit operators (grow, swap, delete, cyclize). Citations as §3.
- **MMP / transformation-rule learning** (Hussain & Rea 2010 ◆; He et al. 2021 ⚠) — the literal "med-chem
  guideline as edit operator": transformations from chemist-made pairs become a learned, conditionally-applied
  edit vocabulary.
- **Activity-cliff-aware editing** — van Tilborg, Alenicheva & Grisoni, "Exposing the limitations of molecular
  ML with activity cliffs" (MoleculeACE), JCIM 2022. ⚠ establishes that **small edits can flip potency by
  orders of magnitude** — motivates cliff-sensitive edit policies and evaluation.
- **Human-in-the-loop / preference editing** — PEER, CoEdIT (§1), DrugAssist (§3), DPO/RLHF (§2) are the
  mechanisms turning a chemist's accept/reject or guideline into a reward/instruction that steers the editor.

## 7. Open problems / gaps
- **Hard-constraint guarantees under learned edits.** Only formal-grammar/FSM decoding and representation-level
  tricks (SELFIES, SAFE fragment-fixing, ProteinMPNN/RFdiffusion positional fixing) *guarantee* a constraint;
  soft guidance (PPLM/FUDGE/classifier-guided diffusion, TargetDiff/DiffSBDD) only biases. Pharmacophore +
  med-chem rules need a **hybrid**: hard-mask the enforceable (valid string, kept scaffold, fixed cyclization)
  + soft reward for the graded (potency, ADMET). No published model does both for cyclic peptides.
- **Cyclic / ncAA / HELM-level support.** Small-molecule editors (REINVENT 4, SAFE, Modof, DrugAssist) are
  SMILES-centric, no native macrocycle/ncAA; peptide models (PepFlow, PepGLAD, ProteinMPNN, ESM) are
  canonical-AA. **RFpeptides** is the lone verified cyclic-macrocycle model, and it is structure-first (needs a
  pocket), not a sequence-editor over a HELM/BILN string. A guideline-driven editor over cyclic-peptide
  sequences with ncAA is an open build.
- **Data scarcity per target.** Conditioning models (PGMG, Pocket2Mol, TargetDiff, PepGLAD) assume enough
  structural/activity signal; novel targets with few actives overfit. Transfer/curriculum and pharmacophore
  conditioning mitigate but don't solve cold-start.
- **Activity-cliff sensitivity.** Similarity-constrained editors (Modof, MMP) can walk off a cliff; edit
  scoring must be cliff-aware, which current generative editors largely ignore.
- **Evaluation.** NLP has EditEval; chemistry/peptide editing lacks an agreed benchmark separating *edit
  fidelity* (respected the constraint / kept the scaffold) from *property gain* from *synthesizability*.
  Docking/affinity proxies are weak; wet-lab-validated edit benchmarks (as RFpeptides provides for de-novo
  cycles) are rare.

## 8. Implications for our cyclic-peptide program (the design this motivates)
The landscape says the closest fits are **RFpeptides** (cyclic, structure-conditioned, wet-validated) for the
binder/backbone layer; **PepFlow / PepGLAD** for full-atom co-design with partial-sampling edit modes;
**ProteinMPNN / RFdiffusion inpainting** for fixed-region redesign; and, on the "edit under guideline" axis,
**DrugAssist** (instruction-driven), **SAFE** (fragment-fixed infilling), **Modof / MMP** (transformation-rule
editing), and **PGMG** (pharmacophore conditioning) as the transferable paradigms. **None combines a
HELM-level cyclic/ncAA representation + a hard pharmacophore constraint + med-chem transformation rules** —
that intersection is the white space, and it is exactly the two-tier design argued elsewhere in this program:

1. **Tier-1 hard invariants, enforced *inside* generation** (constrained decoding / positional fixing, per
   NeuroLogic / grammar-constrained decoding / ProteinMPNN-style masking): RGD·Asp (MIDAS), macrocyclization,
   valid HELM string. Guaranteed, not filtered.
2. **Tier-2 flexible, expert-editable edit-guidelines as the action space** (per MMP / "chemist's intuition" /
   DrugAssist / CoEdIT): N-methylation for permeability, charge tuning for renal dose, turn-inducer swaps for
   conformation, RGDL→RGDLxxL/I for potency — each a transformation with an applicability condition, a
   predicted direction, a tradeoff tag, and a confidence; *scored and suggested*, not pass/fail.
3. **Structure/pocket-conditioned proposal** (RFpeptides / PepGLAD / PGMG) to place and refine edits against
   9xmm / 5O45, with **physics (MM-GBSA) and assay as the arbiter** (cliff-aware, per MoleculeACE), and
   **preference learning (DPO)** to refine which guidelines actually pay off per target — the DMTA loop.

The gap that blocks a drop-in solution is representation + hybrid constraint: a cyclic/ncAA (HELM/BILN) editor
with Tier-1 hard-masking and Tier-2 learned transformation rules. That is the component to build; the pieces
to build it from (RFpeptides, PepGLAD, SAFE-style fixing, MMP rule-learning, DPO) all exist and are cited above.

---
*Verification: ✅ RFpeptides, REINVENT 4, SAFE, Modof, DrugAssist, PGMG, ResGen, PepFlow, PepGLAD, CoEdIT
confirmed via search. ◆ canonical NLP/cheminformatics/protein foundations recalled with high confidence. ⚠
EditEval, grammar-constrained decoding (Willard & Louf), DeepFrag, DeepLigBuilder, He-et-al-2021 MMP,
MoleculeACE, HELM (Zhang 2012), and RFpeptides lead-author attribution have a recalled detail; works confirmed
to exist. No IDs were invented.*
