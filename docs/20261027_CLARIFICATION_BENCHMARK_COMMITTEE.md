# Clarification benchmark — committee review on difficulty, importance, popularity, coverage

**2026-10-27.** Three-lens committee (bioinformatics-core lead; human–agent interaction researcher; ML
benchmark methodologist) reviewed the v1 clarification tasks on the four requested axes. Strong convergence.

## Ratings

| Axis | Rating | Verdict |
|---|---|---|
| **Difficulty** | **1.5–3 / 5** | Too easy. `interpret` items name the tool explicitly (keyword-spotting); `clarify` items just remove the keyword (null-check). A shallow regex would pass — which is why frontier models score ~0.94–0.97. |
| **Importance** | **4–4.5 / 5** | The *slots* are high-stakes: a silent wrong guess on genome/strandedness/variant-type runs successfully but produces garbage science. Right target, wrong difficulty. |
| **Popularity** | **3–4 / 5** | RNA-seq / variant / reference selection are bread-and-butter; cryo-EM SPA-vs-tomo and docking-pocket are specialized/contrived. |
| **Coverage** | **2 / 5** | Misses the hard, common clarification *types* (below). |

## The core design flaw (unanimous)

**"Slot not explicitly stated" ≠ "must ask."** A value is often recoverable from file headers, sample sheets,
prior turns, or an authorized default — asking then is over-asking. Conversely, naming an organism or tool does
not resolve the scientific choice (e.g. "human → GRCh38" is a product *default policy*, not an entailment;
"unknown strandedness" can be *inferred from the reads*). The benchmark must make available evidence and
default policy explicit, and score **which uncertainty was identified** (the most consequential one), not merely
whether any question was asked.

## Top missing scenarios (importance × popularity), converged

1. **Experimental design / contrast selection** — "DESeq2 on counts.tsv, 3 treated + 3 control" → must ask the
   *reference level* (or the fold-change is inverted). Fully-specified file, still a consequential ambiguity.
2. **Reference/genome build + conflicting provenance** — "human" → which build?; user says GRCh38 but the BAM
   header says GRCh37 → clarify the *conflict*, don't silently run a mismatch.
3. **Missing-but-recoverable** — strandedness unknown to the user, but an accessible run manifest records it →
   **interpret from the manifest, do not ask**. The real test of over-asking.
4. **Conflicting tool/data** — "Seurat on my bulk RNA-seq", "CellRanger on Smart-seq2", "Sniffles on short-read
   Illumina" → catch the contradiction and clarify.
5. **Ambiguous entity/artifact** — mouse build (mm10 vs mm39), gene aliases, a PDB entry with two ATP-binding
   chains, compound stereochemistry → interpret the entry, clarify the specific ambiguity.
6. **Almost-specific boundary** — "10x 3′ v3" *determines* strandedness (don't ask); "paired-end" does *not*
   determine strandedness (distinct slot).
7. **Multi-slot / partial-answer follow-up** — resolve one slot, recognize the other consequential one; update
   state after a user's partial answer without re-asking.

## Items to cut / revise

- **Cut the `input` present-vs-absent items** (SMILES / receptor path / counts filename) — they test payload
  presence, not clarification judgment, and inflate the score. Keep two or three as easy anchors.
- **Revise the over-explicit `interpret` branch items** into realistic, slightly-messy phrasings.
- **Revise the organism→assembly golds** to carry an explicit default policy, and the unknown-strandedness item
  to state whether reads/metadata/inference are available.

## Scoring changes recommended

Separate **slot resolution** from **whole-task readiness**; add an **inspect/retrieve** action (the agent may
resolve an omission from accessible context); score *which* uncertainty was flagged; accept multiple valid
clarification phrasings; hold out tool/assay synonyms to reduce lexical leakage; include **matched-context
variants** where the same request requires a different action depending on the available evidence.

## Disposition

v1 is a valid **smoke test** of careless-guessing vs gratuitous-asking, but not yet a discriminating benchmark
of clarification *judgment*. v2 (in progress) attaches **available context** to each item and adds the hard
scenario types above, with the gold turning on evidence + default policy rather than keyword presence.
(Inventory fix: v1 branch tier uses 10 of the deployed fork-points, not 15 — the other 5 are to be added.)
