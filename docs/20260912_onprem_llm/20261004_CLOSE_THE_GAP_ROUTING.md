# Closing the LLM+harness gap — routing (error-analysis-driven)

**Date:** 2026-10-04
**Mandate:** the task is to **improve the system and close the LLM+harness gap**, not to note that a 9B is
smaller than a frontier model (that difference is trivial and known). Everything here targets the
**catalog / LLM+harness** score.

## Where the gap actually is (item-level, not hand-waving)
RealBio routing, catalog (LLM+harness) mode, n=200:
- base Qwen3.5-9B = **0.815**, frontier Opus-5 = **0.960** → a **31-item** gap.
- Decomposition of those 31: **opus-right/base-wrong = 31; both-wrong = 6; base-right/opus-wrong = 2.**

**The candidate menu is the full 91-workflow label set — gold is ALWAYS in the menu.** Verified: 0/31 gap
items are retrieval-misses. **100% of the routing gap is SELECTION-miss** — base was shown the right answer
and picked a wrong *sibling in the same domain*.

### The 31 misses cluster into 3 teachable discrimination failures
1. **Input-stage blindness** (rna_010, rna_011, tx_004, adv_010, sc2_010): query says *"I already have a
   count matrix / counts table"* → gold `nf-core/differentialabundance`; base routes to the upstream
   `nf-core/rnaseq` / `scrnaseq`. Base ignores that alignment is already done.
2. **Platform / assay discrimination** (Drop-Seq, Parse split-seq, BD Rhapsody microwell+AbSeq, cell-hashing
   → `hadge`, CITE-seq ADT, DDA vs DIA proteomics, Visium vs Xenium): base picks a generic/wrong sibling.
3. **Modality confusion** (Affymetrix microarray `.CEL`, Oxford Nanopore long reads, miRNA/isomiR, somatic
   tumor, shotgun metagenome "how many species"): adjacent-assay mix-ups.

## Root cause (why base misses what frontier gets)
The catalog prompt gives the model **bare workflow NAMES only** (`', '.join(labs)` in `run_baseline.py`) —
no descriptions. A frontier model knows what `nf-core/differentialabundance` vs `nf-core/rnaseq` *do* from
pretraining; a 9B often does not recognize the opaque name. So base is not failing to reason — it is failing
to **recall what each name means**. The discriminating signal is explicit in every query ("already have a
count matrix", "Drop-Seq", "BD Rhapsody microwell", "cell hashing", "DIA with spectral library", "Nanopore",
"Affymetrix .CEL"); the model just can't map it to an opaque id it doesn't recognize.

This is a **harness context gap**, and it is **model-invariant** — fixing it helps any model, most of all a
small one. It is also the architecturally correct place to fix routing per this repo's own doctrine
(rules/retrieval own selection-from-catalog; the LLM is not the lever for deterministic mapping).

## Fix — two tracks, both measured on catalog (LLM+harness)

### Track 1 (harness, cheap, immediate, model-invariant): describe the candidates
Enrich the candidate menu with a grounded **one-line description + input data types** per workflow, pulled
from the production workflow catalog (source being confirmed; must be real metadata, NOT benchmark-fitted
id→id rules). Then "I already have a count matrix" matches "differential expression **from a count matrix**"
— reading comprehension a 9B can do. Expected to recover most of the 31 selection-misses.
- **Where:** the real routing/selection prompt the harness assembles for the LLM (and, to measure it, the
  `cross_domain_routing` catalog prompt in `run_baseline.py`).
- **Validation:** re-run base 9B routing-catalog with enriched menu; score with `score.py`; target 0.815 →
  ~0.96. Guard against regression on the 165 already-correct items.
- **Non-overfit discipline:** descriptions come from the workflow catalog's own metadata, so they generalize
  to any query, not just these 200. No per-item id→id mapping.

### Track 2 (model, targeted): internalize the discrimination
Even with a described menu, production retrieval returns a *tight top-k* (not the full 91), and some
discriminations (stage, platform) should be reflexive. Build **contrastive SFT** on exactly these three
clusters — grounded in catalog metadata — so the model internalizes signal→workflow mapping:
- input-stage: "{have raw reads | have counts}" → {alignment wf | differentialabundance}
- platform→wf: Drop-Seq/Parse/BD Rhapsody/cell-hashing/CITE-seq/Visium/Xenium/MERFISH → specific wf
- modality: microarray/.CEL, Nanopore, miRNA, DDA vs DIA, somatic vs germline, amplicon vs shotgun
This is **targeted discrimination SFT**, NOT generic concept CPT — short to train, directly on the gap.

## What this does NOT cover (the genuinely LLM-bound residual)
Routing is selection → mostly a harness fix. The tasks where model capacity truly matters — findings
interpretation, out-of-catalog workflow generation, clarification/decomposition — are a separate track and
are where model improvement (and, if it earns its place, CPT) is the lever. Each gets the same treatment:
item-level error analysis → localize → targeted fix → re-measure on the LLM+harness metric.

## Status
- [x] Routing gap localized item-level: 31 selection-misses, 3 clusters, 0 retrieval-misses.
- [ ] Confirm grounded description source for the 91 catalog workflows (recon in progress).
- [ ] Track 1: implement described-menu; re-run base catalog; score; target ≈0.96.
- [ ] Track 2: build contrastive discrimination SFT; short targeted train; re-measure.
- [ ] Repeat the localize→fix→measure loop on the LLM-bound tasks.
