# Proteomics Search — Social / External Drafts (FOR REVIEW — do not post)

**Date:** 2026-10-01
**Status:** DRAFTS ONLY. Nothing here has been or should be posted. The user reviews + posts.
**Source of truth for every number:** `docs/20261001_PROTEOMICS_SEARCH_BENCHMARK_REPORT.md`
(→ `docs/20260929_PROTEOMICS_SEARCH_SPEED_RECALL.md`).

**Honesty rules applied (per project norms):**
- Lead with the OUTCOME, not the plumbing. No infra-stack disclosure (no AWS/Batch/Nextflow/executor,
  no "we wired together X").
- Numbers are always in benchmark context ("on a standard human-proteome benchmark with
  entrapment-based FDR control, X× faster and Y% more peptide IDs at 1% FDR"), never a bare "222% more".
- Light credibility tag only: built on best-in-class open methods. We do **not** claim BioMate invented
  Sage or Mokapot.
- No "first / best / unmatched" — the field has strong prior art (fragment-indexed engines + ML
  rescoring are established; see the survey).
- Every post carries the one-line honest caveat (relative gains on a specific benchmark).

---

## A. LinkedIn / X short post (primary)

> **Faster proteomics search — without trading away the IDs.**
>
> We ran the same 3-arm head-to-head on four real human-proteome datasets — a ProteomeTools synthetic
> pool, a deep HeLa DDA run, an HLA immunopeptidome, and a two-species mixture — with an identical
> database, settings, and FDR scorer applied to every arm.
>
> On the tryptic searches, a fragment-indexed engine ran the identification end-to-end **~3–5× faster**
> than a conventional brute-force engine (2.7–5.3× measured). Swapping in semi-supervised rescoring on
> top, it found **+57% to +359% more peptides at 1% FDR** across the datasets — the biggest gains on the
> hardest search (the no-enzyme immunopeptidome). On the two-species control it also attributed 97% of
> the IDs to the organism actually in the sample, so the extra depth isn't coming from spurious matches.
>
> The part we care about most: the FDR is **entrapment-validated**, not just target-decoy. We mixed
> known-false (shuffled) sequences into the database and confirmed the measured false-match rate stayed
> at or below the claimed 1% on every dataset. More IDs only count if they're real — here they are.
>
> It runs on best-in-class open methods (a fragment-indexed search engine + semi-supervised rescoring),
> composed so you get the speed *and* the recall in one pass, on real data, through the same path you'd
> use for an actual project.
>
> Caveat worth stating plainly: these are relative gains measured on specific benchmarks, and they vary
> honestly by regime — on the no-enzyme immunopeptidome the indexed engine trades its speed edge for a
> large recall gain.

---

## B. X / Twitter (tighter, thread-safe single tweet)

> Proteomics DB search across four real datasets, same settings, 1% FDR: a fragment-indexed engine runs
> ~3–5× faster on tryptic searches and, with semi-supervised rescoring, finds +57% to +359% more
> peptides than a brute-force baseline — with the FDR validated by entrapment (known-false sequences), so
> the extra IDs are real, not inflated. Built on best-in-class open methods. (Relative gains; they vary
> by dataset — biggest on the no-enzyme immunopeptidome.)

---

## C. Longer blog variant

### Title: Finding more peptides, faster — and proving the "more" is real

**The short version.** Across four real human-proteome search datasets, BioMate's proteomics
identification runs **about 3–5× faster end-to-end** than a conventional brute-force engine on tryptic
searches and finds **+57% to +359% more peptides at 1% false-discovery rate (FDR)** on the same data —
and we verified on every dataset that the extra identifications are genuine, not an artifact of loose
statistics.

**Why "faster" and "more" usually fight each other.** A shotgun-proteomics run produces tens of
thousands of MS/MS spectra, each of which has to be matched against a large space of candidate
peptides. The classic tension: make the search space bigger to find more, and the search gets both
slower and less able to tell true matches from the growing cloud of look-alikes. Most tools win one
axis at the cost of the other.

**What we measured.** We ran a controlled benchmark on four real datasets — a ProteomeTools synthetic
DDA run (about 65,000 spectra), a deep single-shot HeLa DDA run, an HLA immunopeptidome (a harder,
no-enzyme search), and a two-species mixture (a pure E. coli sample searched against a combined
human+E. coli database, a specificity control) — each searched three ways, with everything held
identical within a dataset: the same database, the same tolerances and modifications, the same hardware,
and crucially **the same downstream FDR scorer applied to every run** so no tool grades its own homework.

- A conventional brute-force engine as the baseline.
- A fragment-indexed engine, which organizes the candidate space so each spectrum looks up its
  plausible matches instead of scanning everything. This is where the speed comes from.
- The fragment-indexed engine plus semi-supervised rescoring, which sharpens the line between true
  matches and decoys. This is where the extra identifications come from.

**The result.** On the tryptic searches the indexed engine finished end-to-end about 3–5× faster while
matching or improving recall. Adding rescoring on top produced **+57% to +359% more peptides at 1% FDR**
versus the baseline across the four datasets — the smallest gain on a clean, deep tryptic HeLa run
(where the fast engine alone already captures nearly everything), and the largest on the no-enzyme HLA
immunopeptidome (the hardest discrimination problem, which is exactly where rescoring helps most). On
that no-enzyme search the speed story inverts: building the index over the enormous unconstrained
candidate space makes the indexed engine *slower* than brute force on that one run — so it trades its
speed edge for the biggest recall gain, and we say so plainly.

**The honesty check — this is the part that matters.** Recent proteomics literature (2025) has shown
that machine-learning rescoring can *under-report* FDR, meaning some of the headline "more IDs" numbers
you see elsewhere may partly reflect loosened statistics rather than real discoveries. So we didn't
just trust the standard target-decoy estimate. We built an **entrapment** database — a matched set of
known-false sequences shuffled from real proteins — and measured how often a match landed on one of
them. Across the operating point, the measured false-match rate stayed **at or below** the claimed 1%.
The additional identifications are real.

**What it's built on, and what we claim.** This runs on best-in-class open methods — a fragment-indexed
search engine and a semi-supervised rescorer from the proteomics community. We didn't invent those; our
contribution is composing them into one dependable, benchmarked path and validating the result with
entrapment-based FDR so you can trust the numbers. Fragment indexing and ML rescoring are established
techniques with meaningful prior art; the value here is the honest, reproducible head-to-head and the
fact that it runs on real data in the same place you'd do real work.

**Honest scope.** These are **relative** gains, and they vary by regime — that variation is the point of
running more than one dataset. Absolute identification counts track data quality and scale: the deep
HeLa run yields ~25,000 peptides, while the ProteomeTools synthetic pool against the full human proteome
(with a conservative 1:1 entrapment) yields hundreds, because most proteins are genuinely absent. The
speed advantage holds on tryptic searches but inverts on the no-enzyme immunopeptidome; the rescoring
lever is small on a clean deep run and large on hard/ambiguous search spaces. The ratios are strong and
internally consistent across the four datasets, and we report the per-dataset variation rather than a
single flattering average.

---

## D. One-line caveat footnote (attach to any post)

> Figures are relative gains measured on four real human-proteome search datasets (ProteomeTools, a deep
> HeLa DDA run, an HLA immunopeptidome, and a two-species mixture) at 1% FDR with entrapment-based
> validation. Gains vary by regime — the speed edge holds on tryptic searches and inverts on the
> no-enzyme immunopeptidome, where the recall gain is largest. Built on best-in-class open methods (a
> fragment-indexed engine + semi-supervised rescoring).

---

## Number check (for the reviewer — every figure traces to the report)

| Phrase used | Exact measured figure | Source |
|---|---|---|
| "~3–5× faster on tryptic searches (2.7–5.3× measured)" | ProteomeTools 153.1→~29 s = 5.3×; HeLa 167.7→50.2 s = 3.3×; species-mix 142.5→53.4 s = 2.7× | report §3.1 / §3.2 |
| "+57% to +359% more peptides at 1% FDR" | HeLa 16,276→25,508 = +57% (low); HLA 948→4,352 = +359% (high); ProteomeTools 73→191 = +162%; species-mix 4,889→7,890 = +61% | report §3.2 per-dataset ratios |
| "biggest recall gain on the no-enzyme immunopeptidome" | HLA Sage+Mokapot pep +359% vs Comet; Mokapot lever +12.9% (vs +0.4% HeLa, +2.1% species-mix) | report §3.2 |
| "speed inverts on the no-enzyme HLA search" | HLA Sage 844.5 s vs Comet 217.4 s = 0.3× (slower; 376M-fragment no-enzyme index) | report §3.2 |
| "measured false-match rate at or below 1%" | every arm on every dataset FMR ≤ nominal at 1% (e.g. HeLa S+M 0.60%, HLA S+M 0.41%, ProteomeTools S+M 0.24%, species-mix S+M 0.43%) | report §3.2 / §4 |
| "97% of IDs to the organism in the sample" | species-mix (E. coli sample): 7,679/7,890 peptides = 97.3% E. coli, 211 = 2.67% human @1% FDR | report §3.2; `speciesmix/results/foreign_id.txt` |
| "four real human-proteome datasets" | ProteomeTools PXD010595; HeLa PXD014415; HLA PXD004894; species-mix PXD028735 | report §3.2 |
| "best-in-class open methods (fragment-indexed engine + semi-supervised rescoring)" | Sage (MIT) + Mokapot (Apache-2.0) | report §2.4 |

Every figure above traces to a real scored run at
`s3://biomate-nextflow-work/proteomics_breadth_20261001/<dataset>/results/scored/metrics.json` plus the
per-arm `*.time.txt` wall-clocks (report §8 provenance map). No number is projected.

Deliberately NOT said anywhere (would over-claim or break the honesty rules): no "first/best/unmatched";
no infra stack named; no "BioMate invented Sage/Mokapot"; no bare percentage without benchmark context;
no absolute-count hype (counts are reported with their data-scale context); no claim of a uniform speedup
(the HLA no-enzyme inversion is stated plainly).
</content>
