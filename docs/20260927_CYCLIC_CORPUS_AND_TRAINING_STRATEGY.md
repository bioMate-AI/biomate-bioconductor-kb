# Cyclic-Peptide Corpus Expansion + Training Strategy — Adjudicated by Committee

**Date:** 2026-09-27 · **Status:** ADJUDICATED. Part B was an open question; an 8-member
cross-vendor committee (below) has settled it. The original proposal (broad small-molecule +
linear pretrain → fine-tune, as the *headline* strategy) was **not supported** — the committee's
verdict replaces it. Change log at the bottom.

---

## TL;DR — the verdict (what changed)

- **The training strategy is component-specific — a single recipe is a category error.**
  - **Geometry Autoencoder (AE): Option B — mid-train on cyclic geometry (CREMP), initialized from our
    linear-peptide/protein all-atom AE (the epoch-221 backbone). NOT small-molecule pretrain.**
  - **Co-design Generator: Option D — curriculum: linear peptide–protein complex pretrain (binding-site
    conditioning) → cyclic mid-train (CREMP) → SFT on the scarce target-conditioned cyclic subset.**
- **Broad small-molecule pretraining as the whole-model foundation is a trap** (especially for the AE
  geometry model): negative transfer, wrong inductive bias. Small molecules earn their keep only as a
  chemistry *tokenizer/fragment* warm-start for the sequence/modification channel — never as the AE
  geometry foundation.
- **The true ceiling is NOT corpus size — it is the near-total absence of target-*bound* cyclic
  complexes.** No self-supervised strategy on ~40k isolated cyclics can manufacture binding supervision.
  This reframes corpus priorities (Part A): the highest-value acquisition is *bound* cyclic complexes.
  **This is the same scarce resource behind pharma Pain 2 (new-target generalization) and Pain 3
  (receptor-carrying negatives)** — and the DMTA loop is what manufactures it over time. See the
  pharma-pains ↔ loop ↔ architecture cross-reference in `20260925_PEPTIDE_EXECUTION_PLAN.md`.
- **Decisive cheap gate before any GPU spend:** a frozen-encoder linear-probe transfer matrix
  (3 AE inits: small-mol / linear-epoch221 / random → measure reconstruction + ring-closure on
  held-out CREMP *and* the experimental cyclic-complex subset). One afternoon, no diffusion training.

---

## Part A — Corpus expansion (data) — corrected

**What we already have (S3 `cyclic_peptide/datasets/`, partial):** `cremp_partial`, `pepbdb`, `pepbench`, `bindingdb_peptide`, `peptideclm2_pepmsnd`, `approved_cyclic_peptide_drugs`, `macroconf`, `helm_monomers`, plus `nme_v1` (1,225 N-Me, just built).

**Ranked expansion moves (speed × leverage):**
1. **Aggregate + standardize existing cyclic DBs** → one schema (seq/HELM + SMILES + structure + nme_mask/mods). CycPeptMPDB, PepBDB/PepBench (peptide–protein *complexes with structure*), BindingDB-peptide, approved cyclic drugs, PDB/Q-BioLip cyclic subset (mine by SS-bond / head-to-tail). Mostly de-dup + normalize.
2. **Complete CREMP** — *the* macrocyclic-peptide conformer set (**36,198 macrocycles**, ~31.3M xTB conformers). We have `cremp_partial`. **Biggest single structure-rich win for the AE, no new experiments.**
3. **Acquire / generate target-BOUND cyclic complexes** — *promoted to the top-value move by the committee* (was #3 "structure-generate SMILES-only"). The generator's bottleneck is receptor-conditioned supervision. Mine PDB/BioLip for bound cyclic complexes; generate bound-relevant poses via **HighFold3 / HighFold-MeD** (native N-Me/D-AA cyclic) or Boltz/Chai-1/AF3; prioritize anything with a real receptor over more solution conformers.
4. **Structure-generate SMILES-only entries** — ETKDG (done for nme_v1) → HighFold3/HighFold-MeD. Unlocks CycPeptMPDB as *solution* structure data (representation/AE only — NOT bound geometry).
5. **Augmentation** — multi-conformer (CREMP-style, sampled *per molecule* not per conformer), SMILES enumeration + cyclic-ring-permutation, matched-pair (mmpdb).

**Corrected scale (committee):** CycPeptMPDB is **~7,334** unique (not 8,466 — ~13% overcount). Realistic
post-dedup **unique cyclic count ≈ 36–42k**, CREMP-dominated. The "~45k+" was optimistic by ~10–15%.
Critically, **31M conformers ≠ 31M molecules** — weight/sample by molecule so conformer-rich compounds
don't dominate. The *labeled, structurally-diverse, cyclic-only with a measured property* count is far
smaller (~5–8k); the rest is unlabeled geometry or generated structures.

**Four BLOCKING data-quality fixes (data-strategy + skeptic reviewers) — before any model touches data:**
1. **Monomer canonicalization** — HELM2 monomer mapping across CREMP/CycPeptMPDB/BindingDB/PepBDB
   (Hyp/Aib/Nle etc. are named differently). Gate: HELM→SMILES→HELM round-trips for 200 random entries.
2. **SMILES standardization + priority-merge dedup** — RDKit MolStandardize, tautomer normalization,
   stereo resolution. Exact-match keep order: **experimental crystal > NMR > xTB-CREMP > ETKDG-generated**;
   merge labels. SMILES-only dedup is insufficient (tautomers/undefined-stereo/protonation cause false
   negatives).
3. **Conformer provenance tag** on every geometry: `{xTB_CREMP | ETKDG | HighFold3 | PDB_experimental |
   NMR_experimental}`. Stratify losses by provenance; never train a *bound-geometry* head on xTB conformers.
4. **Cyclic-aware split — NOT Bemis-Murcko** (Murcko is wrong for macrocycles: the whole backbone ring is
   the scaffold; it over-splits near-identical chemistry → cosmetic "hard" test). Use **sequence-identity
   clustering (≤40%) + Tanimoto-MaxMin (Morgan r=2, 2048-bit) fallback**; validate **median train/test
   nearest-pair Tanimoto < 0.35**.

**Leakage gate (hard):** CREMP / CREMP-CycPeptMPDB is the *standard held-out benchmark* in the 2024–2026
cyclic-permeability literature. **Freeze the eval set first, then assemble training data from the
remainder** — family-disjoint (sequence + scaffold), before training, not reported afterward. Also isolate
the ~3,258 CREMP entries with *measured* passive permeability as a premium eval set (never in training
without an explicit flag).

---

## Part B — Training strategy — ADJUDICATED (the doubt was correct)

**Original proposal (now rejected as the headline):** *foundation-pretrain the chemistry-native
representation on small molecules + linear peptides → transfer/fine-tune on cyclic.* The user doubted
this ("why start from small-molecule/linear embeddings — why not SFT/mid-train on cyclic?"). **All 8
reviewers validated the doubt.** The verdict:

### The core reframe: split by component (different data regimes, different objectives)

| | **Geometry AE** | **Co-design Generator** |
|---|---|---|
| **Learns** | geometry manifold: all-atom frames, torsions, ring-closure geometry (self-supervised, label-free) | conditional `p(seq, struct, mod \| binding site)` |
| **Data regime** | **NOT data-starved** — CREMP's 36k macrocycles / 31M conformers is a genuine geometry foundation | **binding-site conditioning is the scarce resource** — CREMP has no receptor, CycPeptMPDB is SMILES-only, PepBDB cyclic subset is small |
| **Verdict** | **B — mid-train on cyclic, init from the linear/protein AE (epoch-221). NOT small-mol pretrain.** | **D — curriculum: linear-complex binding pretrain → cyclic mid-train → target-conditioned SFT.** |
| **Existence proof** | **RINGER** learns gold-standard macrocycle ensembles from ~CREMP-scale geometry alone, no small-mol/protein foundation → ~36k unique macrocycles is *enough* for cyclic geometry near-from-scratch | our epoch-221 DockQ-0.557 backbone already encodes the receptor-geometry prior CREMP can't teach; the cyclic delta (ring closure + ncAA) is a *finetune-sized* gap, not from-scratch |

### (1) What transfers vs. what does not

- **Small-molecule → macrocycle geometry: largely NEGATIVE.** Best-evidenced point: ChemBERTa-class
  small-molecule models degrade on peptides (exactly why PeptideCLM was built and *still* needed
  peptide-specific data). Small molecules lack the repeating backbone, ring-closure topology, and residue
  frames the AE must model. **Do NOT foundation-pretrain the AE on ChEMBL/PubChem.** Small-mol value is
  limited to (a) a chemistry/atom-vocabulary warm-start for the *sequence/modification* channel, and (b)
  non-canonical *fragment* chemistry (staples, N-Me, D-AA motifs) — tokenizer/embedding benefit, not geometry.
- **Linear-peptide / protein-complex → cyclic: POSITIVE, and the highest-value pretraining source.**
  Shares local stereochemistry, rotamers, and — critically — the **binding-site conditioning mechanism**.
  But linear peptides are entropically floppy and don't teach ring closure or the long-range conformational
  coupling of cyclization → useful *stage*, not a substitute for cyclic training.
- **HELM-BERT** (topology-explicit, ~75k mixed peptides) beats SMILES encoders on cyclic permeability
  (0.668 > MoLFormer-XL 0.578) → **representation dominates corpus breadth**.

### (2) Is ~40k cyclic enough to train directly?
- **AE: yes** (RINGER; 31M conformers is the effective count for geometry).
- **Generator: no, not from scratch** — 40k unique cyclics, few with a receptor, is far too thin to learn
  binding-site conditioning cold (→ diverse-but-non-binding output). It must *inherit* the binding prior
  from linear-complex pretraining. Hence generator = curriculum, AE = mid-train.

### (4) Representation dependence (the hinge — it flips the small-mol verdict)
- **Atom-level:** max small-mol transfer, natively expresses ncAA — but dilutes residue/ring bias, most data-hungry.
- **Residue/monomer-level:** best linear→cyclic transfer — but can't express N-Me/D-AA/staples without vocab extension.
- **Topology-explicit (HELM / monomer-graph):** the sweet spot; empirically the top cyclic performer.
- Our **all-atom geometric latent** (PepGLAD-style) is atom-explicit + frame-aware → high linear-complex
  transfer, low small-mol geometry transfer (exactly the split above). **Make modification an EXPLICIT
  conditioning channel** in the generator — do not hope the latent absorbs it, or non-canonical chemistry
  (our differentiator) becomes the silent failure mode.

### Negative-transfer risks (rank-ordered)
1. **AE on small molecules → wrong geometry prior** (highest; well-documented). Avoid entirely.
2. **CREMP distribution shift** — computed (xTB), solution-phase, receptor-free. Mitigate: finalize the
   generator on experimental bound complexes; hold out an experimental-complex test set.
3. **Modification collapse** — if ncAA isn't an explicit channel, the generator regresses to canonical
   (DockQ won't catch it → add a modification-recovery / chemical-validity metric).
4. **Curriculum forgetting** — linear→cyclic can wash out the binding prior → LoRA/DoRA adaptation
   (cf. PepDoRA) or replay linear complexes during cyclic mid-training, not full fine-tuning.

### (5) The decisive cheap experiment — two tiers, converged

**Tier 0 (do this FIRST — one afternoon, no diffusion training, per our "review before expensive
deploy" discipline):** a **frozen-encoder linear-probe transfer matrix on AE reconstruction.**
Three AE inits — (i) small-molecule-pretrained, (ii) our linear/protein epoch-221 init, (iii) random —
freeze each encoder, measure **all-atom reconstruction error + ring-closure validity** on a held-out
CREMP split *and* on the held-out experimental cyclic-complex subset. Optional: Gemini's
**latent-interpolation ring-break test** (interpolate two held-out cyclics in AE latent; broken amide
bonds / open rings in intermediates ⇒ the broad prior dominated ⇒ negative transfer).
- **linear-init ≫ random ≫ small-mol** → confirm AE = B from linear init; kill small-mol pretrain;
  greenlight the curriculum generator (expected outcome given RINGER + ChemBERTa-degradation literature).
- **random ≈ linear-init** → CREMP alone suffices for the AE; drop the linear pretrain for the AE (cheaper),
  keep it only for the generator's conditioning.
- **small-mol ≥ linear-init** (unlikely) → reconsider an atom-level foundation.

**Tier 1 (only if Tier 0 is ambiguous):** full **factorial transfer ablation** — init ∈
{none / small-mol / linear / both} → cyclic FT, *same architecture*, molecule-/scaffold-/receptor-disjoint
splits (never split a molecule's conformers across train/test), AE and generator metrics reported
**separately**, learning curves at several cyclic-data budgets. ~6–8 GPU-h at small scale.
**Note:** neither tier can establish *target-conditioned binding* performance — the bound cyclic data are
too limited. Do NOT present improved reconstruction/denoising as evidence the model learned binding.

---

## Answers to the 5 open questions (consensus)
1. **Which strategy?** Component-split: AE = B (cyclic mid-train from linear init); generator = D (binding
   curriculum → cyclic mid-train → target SFT). Reject A-as-headline and C-from-scratch.
2. **Does small-mol / linear pretrain transfer?** Small-mol → geometry: negative (tokenizer/fragment only).
   Linear/protein-complex → cyclic: positive, the highest-value source (esp. binding conditioning).
3. **Is cyclic data already enough?** AE: yes. Generator: no — the gap is *bound-complex conditioning*,
   not corpus volume.
4. **Decisive cheap experiment?** Tier-0 frozen linear-probe transfer matrix (above); Tier-1 factorial
   ablation if ambiguous.
5. **Depends on representation & AE-vs-generator?** Yes — this is the crux. Representation flips the
   small-mol verdict; AE and generator need different strategies.

---

## Committee record (this adjudication)

Two independent panels, same adversarial prompt, all converged.

**Frontier cross-vendor panel (latest APIs, surveyed live 2026-09-27):**
- **Claude Opus 4.8** — split: AE=B (linear init), generator=D; RINGER existence proof; Tier-0 frozen-probe gate.
- **OpenAI GPT-6** (`gpt-6-luna`, `gpt-6-sol`; 2026-09-14 flagship) — D split by component; "reject C as default, reject unconditional A"; small mols initialize chemistry modules only.
- **Google Gemini-Pro** (`gemini-pro-latest`) — split: AE=A/D, generator=D; "direct SFT on cyclic is suicidal — you have ~zero target-bound complexes"; latent ring-break test.

**Internal panel (Agent tool):**
- ML/foundation (Opus) — B + from-scratch AE; demote broad small-mol pretrain to one ablation control.
- Macrocycle chemistry (Opus) — B, topology-explicit rep; representation dominates corpus.
- Data-strategy (Sonnet) — B default + the 4 blocking corpus fixes; corrected 45k→36–42k, 8.5k→7.3k.
- Transfer-learning skeptic (Sonnet) — B/C, A unsupported; every paper where pretraining helps cyclic used
  cyclic/near-cyclic pretraining, not drug-like small molecules; ~45k overstates labeled cyclic 5–8×.

**Key references (verified by reviewers):** PepGLAD (NeurIPS 2024); RINGER (internal-coordinate macrocycle
diffusion); CREMP (Sci Data 2024); PeptideCLM (peptide-aware CLM); HELM-BERT (topology-aware, JCIM 2026);
PepDoRA (weight-decomposed LoRA); CycPeptMPDB (JCIM); systematic benchmarking of 13 cyclic-permeability
methods (JCIM 2025, scaffold-split inflation).

---

## Change log
- **2026-09-27 (v2):** Adjudicated by 8-member committee. Rejected broad-pretrain-as-headline. Verdict =
  component-split (AE=B/linear-init, generator=D/binding-curriculum). Promoted bound-complex acquisition to
  top corpus priority; corrected scale (45k→36–42k, CycPeptMPDB 8.5k→7.3k); added 4 blocking data fixes,
  the leakage/eval-freeze gate, and the Tier-0 frozen-probe go/no-go experiment. Added committee record.
- **2026-09-27 (v1):** Original proposal — corpus expansion + training strategy as an open question.
