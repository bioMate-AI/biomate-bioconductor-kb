# Manuscript publication-readiness — committee verdict + punch-list

**2026-10-28.** A three-lens publication-readiness committee (handling editor; methods/stats reviewer;
computational-biology domain reviewer) assessed the three preprints for submission to a top venue (NeurIPS
Datasets & Benchmarks / Nature Methods / Bioinformatics). **Unanimous: all three need major revision before
submission; none is submit-ready as-is.** RealBio is closest; DrugDev is furthest. This records what was fixed
this round and the remaining punch-list (several items require the author's input and cannot be done without it).

## Readiness ranking (committee)
| Paper | Readiness (of 5) | Single biggest blocker |
|---|---|---|
| RealBio | 2–3.5 | the matched comparison / full results not fully specified to reproduce the headline |
| Channel Routing | 2 | 84-item author-labeled pilot — too small/lightly-validated for a standalone benchmark |
| DrugDev-Bench | 1–? | dose ground-truth vs oracle vs executable reference not reconciled |

## Fixed this round (applied to the drafts)
- **Front matter** on all three: cleaned, non-promotional titles (dropped "— and What the Knowledge Layer
  Buys"; narrowed the DrugDev "execution-grounded" title; marked Channel as a "pilot"); author/affiliation/
  corresponding-author placeholders; keywords; an explicit scope note.
- **Back matter** on all three: data-and-code availability with a repository/DOI placeholder and a per-item-
  predictions release; ethics/intended-use; author-contributions/funding/competing-interests placeholders.
- **Full numerical results table** (named models + versions) added to RealBio (Table 2).
- **Tone scrub**: removed product/pitch/internal phrasing the reviewers quoted ("the defensible statement is",
  "shipping system vs. the raw model", "under-measures the deployed system", "cost- and compliance-friendly
  path", "the honest reading", "most determines"); replaced with neutral estimand language.
- **Task-name accuracy**: parameter-fill framed as two distinct estimands (raw model vs. model+rule layer);
  "failure-category classification" wording.
- **Scope leak fixed**: removed the "channel selection" mention from RealBio's synthesis.
- **Statistics caveat**: Channel now states the Wilson/per-item sensitivity (one error ≈ 1.2 pp overall,
  8.3 pp per channel) and corrects the "models are not beating the keyword baseline" overstatement.
- **Oracle vs. executable reference**: DrugDev now states throughout that the 0.85 mechanistic reference is an
  *oracle* (rule on the hidden true curve), not an executable-from-inputs pipeline and not a guaranteed upper
  bound; the three oracle misses are framed as a target-definition question.
- **References**: removed the irrelevant BOIN citation from RealBio.

## Remaining punch-list — REQUIRES THE AUTHOR (cannot be completed without your input)
1. **Author list, affiliations, corresponding author, funding, competing-interests, author-contributions** —
   placeholders are in place; fill them in. (Hard desk-reject requirement at all three venues.)
2. **Public repository + archival DOI** — the drafts promise a release; a real URL + DOI (e.g. Zenodo) must
   be created and inserted. A CC-BY license alone is not a reproducibility package.
3. **External / blinded label adjudication** — especially the protocol-threshold golds (RealBio), the
   acceptable-alternatives (Channel), and the dose decision policy (DrugDev). Reviewers require independent
   adjudication, not author-only labels.
4. **Dataset expansion** — Channel (84 → a larger, held-out set with paraphrase/lexical-confound items);
   DrugDev (more dose scenarios / PK compounds) to move beyond a pilot.

## Remaining punch-list — doable without the author (next revision pass)
5. **Dataset-curation & task-specification sections** (all three): who authored the items, sources, QC,
   ambiguity adjudication; exact prompt templates and candidate-menu construction (to a supplement).
6. **RealBio**: reconcile the three routing numbers explicitly in one place — conditional-on-retrieval (~0.90+),
   end-to-end including retrieval misses (~0.80), and the retrieval-only system (0.965); add paired uncertainty.
7. **Channel**: add the per-channel table and confusion matrix (promised in Methods); add a lightweight
   learned-classifier baseline alongside the keyword baseline; reframe consistently as policy-adherence.
8. **DrugDev**: define the dose decision policy first (target toxicity, admissibility, tie-handling, no-safe-
   dose, whether exact match is the right primary outcome); give the exact selection algorithm and its relation
   to sequential BOIN; add full dose and PK results tables with scenario-level diagnostics; multi-seed the LLM
   rows (single-run n=20 is noisy — Opus-5 dose spans 0.30–0.40 across runs).
9. **Numbered tables + captions** everywhere; complete reference metadata (arXiv IDs/venues).

## Disposition
RealBio is the paper to finish first. With items 1–2 and 5–6 it is a scoped, defensible workflow-selection/
extraction benchmark paper. Channel is best positioned as a short pilot/benchmark note unless expanded (item 4).
DrugDev needs the decision-policy reconciliation (item 8) before its headline comparison is interpretable.
Per the submit-review gate, **do not submit** until the author completes items 1–4 and reviews the final drafts.
