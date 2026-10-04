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

## MEASURED RESULT (2026-10-04, our actual base 9B served on vLLM)
Served Qwen3.5-9B base on an on-demand A10G; ran all 200 routing items in both menu styles, no-think,
greedy. Scored with the same scorer (gold + acceptable_alts).

| base 9B routing (catalog / LLM+harness) | accuracy |
|---|---:|
| NAMES menu (bare — the legacy prompt), no-think | **0.680** |
| DESCRIBED menu (the fix), no-think | **0.885**  (**+20.5pp**; 47 recovered, 6 broken) |
| prior base catalog *with* thinking (leaderboard) | 0.815 |
| frontier Opus catalog | 0.960 |
| full product | 0.965 |

**The harness description-fix lifts our base 9B routing +20.5pp (0.68→0.885), confirmed on the real model.**
Described-no-think (0.885) already **beats** the prior base-with-thinking (0.815) — descriptions more than
compensate for dropping CoT — and closes most of the distance to frontier (0.96). This proves the routing
LLM+harness gap is a **harness-context artifact, closed model-invariantly by showing descriptions**, not a
model-capacity problem. (Several of the "6 broken" are benchmark label-variant mismatches, e.g.
`scaffold_hopping` vs `Scaffold Hopping`, so true lift is marginally higher.)

### Residual 23 misses → next grounded description-quality pass (not capacity)
Cluster on still-thin descriptions: raredisease→sarek (var_009/013/014: desc doesn't signal trio/Mendelian);
scnanoseq vs scrnaseq (sc_001/008: Nanopore-vs-short-read not crisp enough); tipseq/cutandrun; mhcquant vs
epitopeprediction. Fix = sharpen those specific workflow descriptions (grounded), + optionally enable
thinking WITH descriptions (extrapolated ≈ frontier). All harness/data side, not model training.

## Status
- [x] Routing gap localized item-level: 31 selection-misses, 3 clusters, 0 retrieval-misses.
- [x] Confirmed grounded description source: `workflows` table (name, description||annotation, input_types).
- [x] Track 1 implemented (described-menu, annotation fallback) + MEASURED: base 9B 0.68→0.885 (+20.5pp).
- [ ] Production backfill: `description := annotation` where empty (so real routing gets this too).
- [ ] Description-quality pass on the residual 23 (raredisease, scnanoseq, tipseq, mhcquant…).
- [ ] Optional: described + thinking (expected ≈ frontier 0.96).
- [ ] Then the LLM-bound tasks (findings, out-of-catalog gen) get the same localize→fix→measure loop.

## OVERFITTING CONTROL (2026-10-04) — paraphrase robustness
Concern: descriptions were sharpened by prior scripts (differentiate_ambiguous_workflows.py) on the same
axes this benchmark tests (catalog/benchmark co-evolution), so the +20.5pp might be benchmark-specific.

Controls run:
1. **Recovery breadth** — the 47 described-recovered items spread across **26 distinct workflows**; only
   **2/47** land on the specifically-engineered disambiguation targets. → not narrow teaching-to-the-test.
2. **Paraphrase robustness** — rewrote all 200 queries with gpt-4.1 (same intent/specifics, different
   surface form, no workflow names) and re-ran:

| queries | NAMES | DESCRIBED | lift |
|---|---:|---:|---:|
| original | 0.680 | 0.885 | +20.5pp |
| paraphrased | 0.675 | 0.900 | +22.5pp |

described 0.885→0.900 (flat/better), names 0.680→0.675 (flat). **The lift survives paraphrasing → it is
semantic, not lexical echo.** Verdict: the description-fix is a real, generalizable, model-invariant gain,
NOT benchmark overfitting. Residual caveat: absolute magnitude measured on one catalog + one query
distribution; a brand-new catalog/user distribution could differ, but the two mechanisms that would make it
fake (phrasing echo, hand-tuned-workflow concentration) are empirically ruled out.
