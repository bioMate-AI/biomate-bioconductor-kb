# Committee Review — BioMate benchmark + platform manuscripts (A RealBio / B harness / D on-prem)

**Date:** 2026-10-26. **Method:** 3 top-LLM reviewers (OpenRouter), distinct lenses, each peer-reviewing the
~11k-token package (merge proposal + this session's correction docs + `LEADERBOARD_CAVEATS.md` +
channel_routing + Manuscripts A/B/D) to NeurIPS-D&B / *Bioinformatics* standard. Full reviews archived in the
session scratchpad (`review_{opus-5.5,gpt-6.1-sol,gemini-3.1-pro}.md`). A 4th reviewer (DeepSeek-v4) did not
return before the run stopped; three unanimous reviews stand as the committee.

| Reviewer | Lens | Model | Decision | Merge verdict | Preprint-ready |
|---|---|---|---|---|---|
| A | ML / benchmarks methodology & stats | Opus-5.5 | MAJOR REVISION | **AGREE** | NO |
| B | research integrity / reproducibility (adversarial) | GPT-6.1-sol-pro | MAJOR REVISION | (merge implied, favors suite) | NO |
| C | bioinformatics domain & applications | Gemini-3.1-pro | MAJOR REVISION | **AGREE** | NO |

## Editorial decision: MAJOR REVISION — unanimous (3/3). NOT preprint-ready today.
Fundamentally honest work (no fabrication alleged); the problems are **stale/inconsistent numbers,
construct-validity of a few tasks, and over-claims** — all fixable, and the fixes are exactly the direction
this session's work already took.

## The merge question — RESOLVED in your favor (consensus)
**All reviewers who addressed it AGREE** that LLM-vs-harness should be the **results/performance section inside
each benchmark paper**, not a standalone paper. Gemini: *"Separating them leaves the benchmark paper looking
like a rigged product-pitch (C0 vs C2) and deprives it of its most interesting scientific finding."* Opus:
*"separating the same measurements into a thesis paper risks duplication and selective framing."* → **One
benchmark-suite paper (A, absorbing B) + one separate on-prem/platform paper (D); science track stays
separate.** Proceed with the merge.

## Consensus blockers (flagged by ≥2 reviewers — high confidence)
1. **One authoritative, versioned, FROZEN results release; regenerate every table from it.** [A, B] The drafts
   still cite stale/inconsistent numbers — Kimi routing 0.450 (corrected 0.495); BioMate base+harness appears
   as 0.885 / 0.905 / 0.915 / ~0.92 across the package with no condition→artifact map; param 0.634→0.690→0.737
   vs the separate production F1≈0.84 are used interchangeably. Build a claim registry (number → dataset hash,
   scorer commit, prediction hash, endpoint, condition, denominator) and regenerate all tables.
2. **Elevate the +harness (catalog-equipped LLM) condition to the PRIMARY leaderboard; wire the rule layer into
   the eval.** [B, C] The headline C0(bare)-vs-C2(product) framing is apples-to-oranges ("rigged product
   pitch"). The matched same-model bare-vs-harness must be the headline; inject BioMate's deterministic rule
   layer into the param eval (0.634 → ~0.84). *(This session already built `rerun_routing_openrouter.py` +
   measured the production rule layer — finish wiring + make it the main table.)*
3. **Complete the uniform, empties-aware roster re-run; resolve endpoint/provenance.** [B, C] *(Largely done
   this session — 17/20 models uniform described; finish gpt-5.6/qwen3.8-max provenance + flag which endpoint
   served which cell.)*
4. **Establish independence from benchmark-driven tuning.** [B, strongly] The scorer, organism rules, workflow
   descriptions, and description-window were changed **after examining benchmark errors** → those gains are
   *development-set* results. Release the dev history + a training-overlap audit, FREEZE the revised system,
   and evaluate on independently-authored held-out items.
5. **Repair task definitions before interpreting capability.** [B] PBPK prompt omits the target endpoint (yet
   models are called "near-useless at PBPK"); param "fill only if clearly stated" vs penalizing an unstated
   genome; BOIN must state whether it scores algorithmic decisions or recovery of a latent true MTD. Audit +
   rerun affected items on frozen specs.
6. **Manuscript D ("preprint-ready") lacks deployment evidence** — no cost comparison, throughput/latency,
   security/compliance analysis; its "statistically indistinguishable" SFT line conflicts with the documented
   regressions. Rebuild around measured deployment evidence + the corrected (negative) training results.

## Over-claims to soften (reviewer-supplied honest versions)
- "fairness by construction" / "anti-self-grading by construction" → "open deterministic scorer enabling
  independent audit; authors also built the benchmark, scorer, and evaluated product."
- "LLMs used the way they are actually deployed" → "LLMs evaluated **without** the benchmark's candidate
  catalog" (bare ≠ deployment; deployment usually includes retrieval).
- "small on-prem model + harness reaches frontier-parity" → "approaches some frontier results on selected
  tasks; equivalence not established" (0.905 vs 0.94–0.99 is not parity evidence).
- "inverse-scaling harness dividend" → "lower-bare-score models show larger absolute gains on bounded-accuracy
  tasks" (ceiling/headroom effects can produce this without an inverse-scaling mechanism).
- "selection essentially solved" → "selection accuracy high **conditional on successful retrieval**;
  end-to-end ≈ 0.80."
- "near-useless at PBPK" → "low scores on an endpoint-underspecified task; does not establish inability."
- "statistically indistinguishable" → "no advantage demonstrated for the specified runs" (failure-to-reject ≠
  equivalence; use a prespecified margin).

## Strengths (consensus — keep/lead with these)
The **honesty backbone**: withdrawing PBPK 100%→0.200, publishing the SFT negatives + inactive-adapter failure,
cause-based empty handling (truncation vs valid `{}` vs content-filter). The **open deterministic scorer** +
archived predictions + paired context ablations. The **catalog-breadth (4,209) vs clean-execution subset
(1,092)** distinction. The **channel-routing** addition (retrieval-vs-selection decomposition identifies real
bottlenecks). Reviewers call the transparency "exemplary and highly unusual for AI platform papers."

## Path forward (aligns with this session's work)
Most blockers are already in motion: semantic scorer (done), production rule-layer measurement (done), uniform
empties-aware re-run (done 17/20), channel-routing (built), caveats companion (done). Remaining before a
credible preprint: (1) freeze one results release + claim registry + regenerate all tables; (2) make matched
bare-vs-harness the primary comparison + wire the rule layer into the param eval; (3) an independence/held-out
audit for the post-hoc scorer/rule changes; (4) fix PBPK/param/BOIN task specs; (5) give D real deployment
numbers. Then re-convene the committee before declaring submit-ready (per the submit-review gate).
